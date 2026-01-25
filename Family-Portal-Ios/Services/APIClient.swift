import Foundation
import Security

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case decoding(Error)
    case server(statusCode: Int, message: String?)
    case network(Error)
    case missingRefreshToken
    case refreshFailed(String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server URL is invalid."
        case .invalidResponse:
            return "The server response was not valid."
        case .unauthorized:
            return "You need to sign in again."
        case .decoding(let error):
            return "Failed to decode server response: \(error.localizedDescription)"
        case .server(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server error (\(statusCode))."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .missingRefreshToken:
            return "Refresh token not available."
        case .refreshFailed(let message):
            if let message, !message.isEmpty {
                return "Could not refresh session: \(message)"
            }
            return "Could not refresh session."
        }
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

actor APIClient {
    static let shared = APIClient()

    // Local constants to avoid main actor isolation issues
    private static let keychainAccessToken = "com.familyportal.accessToken"
    private static let keychainRefreshToken = "com.familyportal.refreshToken"
    private static let keychainServerURL = "com.familyportal.serverURL"
    private static let defaultServerURLString = "https://grissom.zone"
    private static let refreshTokenExpiry: TimeInterval = 30 * 24 * 60 * 60

    private struct DateFormatters: @unchecked Sendable {
        let isoFormatter: ISO8601DateFormatter
        let fallbackISOFormatter: ISO8601DateFormatter
        let dateOnlyFormatter: DateFormatter

        init() {
            isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            fallbackISOFormatter = ISO8601DateFormatter()
            fallbackISOFormatter.formatOptions = [.withInternetDateTime]
            dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.calendar = Calendar(identifier: .iso8601)
            dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        }
    }
    private static let dateFormatters = DateFormatters()

    private var baseURL: URL
    private var accessToken: String?
    private var refreshToken: String?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let clientId: String

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        let initialBaseURL = baseURL ?? URL(string: Self.defaultServerURLString)!
        self.session = session
        self.encoder = JSONEncoder()

        let formatters = Self.dateFormatters
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = formatters.isoFormatter.date(from: dateString) ?? formatters.fallbackISOFormatter.date(from: dateString) {
                return date
            }
            if let date = formatters.dateOnlyFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }
        encoder.dateEncodingStrategy = .iso8601

        clientId = UUID().uuidString

        let loadedAccessToken = Self.loadToken(forKey: Self.keychainAccessToken)
        let loadedRefreshToken = Self.loadToken(forKey: Self.keychainRefreshToken)
        accessToken = loadedAccessToken
        refreshToken = loadedRefreshToken

        if let savedURLString = Self.loadToken(forKey: Self.keychainServerURL), let savedURL = URL(string: savedURLString) {
            self.baseURL = savedURL
        } else {
            self.baseURL = initialBaseURL
        }

        Self.syncCookiesNonisolated(baseURL: self.baseURL, accessToken: loadedAccessToken, refreshToken: loadedRefreshToken)
    }

    func updateBaseURL(_ url: URL) {
        baseURL = url
        Self.storeToken(url.absoluteString, key: Self.keychainServerURL)
        syncCookies()
    }

    func setTokens(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        Self.storeToken(accessToken, key: Self.keychainAccessToken)
        Self.storeToken(refreshToken, key: Self.keychainRefreshToken)
        syncCookies()
    }

    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        Self.storeToken(nil, key: Self.keychainAccessToken)
        Self.storeToken(nil, key: Self.keychainRefreshToken)
        clearCookies()
    }

    func getBaseURL() -> URL { baseURL }

    func getAccessToken() -> String? { accessToken }

    func uploadMultipart<T: Decodable>(path: String, formData: Data, boundary: String, retryOnAuthFailure: Bool = true) async throws -> T {
        guard let url = makeURL(for: path) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(clientId, forHTTPHeaderField: "X-Client-Id")
        urlRequest.httpBody = formData

        addAuthHeaders(to: &urlRequest, requiresAuth: true)

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            captureTokens(from: httpResponse)

            if httpResponse.statusCode == 401, retryOnAuthFailure {
                try await refreshAccessToken()
                return try await uploadMultipart(path: path, formData: formData, boundary: boundary, retryOnAuthFailure: false)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                if httpResponse.statusCode == 401 {
                    throw APIError.unauthorized
                }
                throw APIError.server(statusCode: httpResponse.statusCode, message: message)
            }

            guard !data.isEmpty else {
                throw APIError.invalidResponse
            }

            do {
                return try await MainActor.run {
                    try decoder.decode(T.self, from: data)
                }
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    func callRPC<T: Decodable, Body: Encodable>(_ name: String, payload: Body) async throws -> T {
        try await request(path: "rpc/\(name)", method: .post, body: payload, requiresAuth: true)
    }

    func request<T: Decodable, Body: Encodable>(
        path: String,
        method: HTTPMethod = .post,
        body: Body? = nil,
        requiresAuth: Bool = true,
        retryOnAuthFailure: Bool = true
    ) async throws -> T {
        guard let url = makeURL(for: path) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(clientId, forHTTPHeaderField: "X-Client-Id")

        if let body = body {
            do {
                urlRequest.httpBody = try encoder.encode(body)
            } catch {
                throw APIError.network(error)
            }
        }

        addAuthHeaders(to: &urlRequest, requiresAuth: requiresAuth)

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            captureTokens(from: httpResponse)

            if httpResponse.statusCode == 401, retryOnAuthFailure, requiresAuth {
                try await refreshAccessToken()
                return try await request(path: path, method: method, body: body, requiresAuth: requiresAuth, retryOnAuthFailure: false)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                if httpResponse.statusCode == 401 {
                    throw APIError.unauthorized
                }
                throw APIError.server(statusCode: httpResponse.statusCode, message: message)
            }

            guard !data.isEmpty else {
                throw APIError.invalidResponse
            }

            do {
                return try await MainActor.run {
                    try decoder.decode(T.self, from: data)
                }
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    func refreshAccessToken() async throws {
        guard refreshToken != nil else {
            throw APIError.missingRefreshToken
        }

        struct EmptyBody: Encodable {}
        let path = "api/refresh"
        guard let url = makeURL(for: path) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.post.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(clientId, forHTTPHeaderField: "X-Client-Id")
        addAuthHeaders(to: &urlRequest, requiresAuth: false)

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            captureTokens(from: httpResponse)

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                throw APIError.refreshFailed(message)
            }

            let refreshResponse: RefreshResponseDTO
            do {
                refreshResponse = try await MainActor.run {
                    try decoder.decode(RefreshResponseDTO.self, from: data)
                }
            } catch {
                throw APIError.decoding(error)
            }

            guard refreshResponse.success, let token = refreshResponse.token else {
                throw APIError.refreshFailed(refreshResponse.error)
            }

            setTokens(accessToken: token, refreshToken: refreshToken)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    private func makeURL(for path: String) -> URL? {
        var trimmed = path
        if trimmed.hasPrefix("/") {
            trimmed.removeFirst()
        }
        return baseURL.appendingPathComponent(trimmed)
    }

    private func addAuthHeaders(to request: inout URLRequest, requiresAuth: Bool) {
        if requiresAuth, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        // Keep refresh cookie available for refresh endpoint calls
        syncCookies()
    }

    private func captureTokens(from response: HTTPURLResponse) {
        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                partialResult[key] = value
            }
        }

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: baseURL)
        var updatedAccessToken: String?
        var updatedRefreshToken: String?

        for cookie in cookies {
            if cookie.name == "authToken" {
                updatedAccessToken = cookie.value
            } else if cookie.name == "refreshToken" {
                updatedRefreshToken = cookie.value
            }
        }

        if updatedAccessToken != nil || updatedRefreshToken != nil {
            let newAccess = updatedAccessToken ?? accessToken
            let newRefresh = updatedRefreshToken ?? refreshToken
            setTokens(accessToken: newAccess, refreshToken: newRefresh)
        }
    }

    nonisolated private static func syncCookiesNonisolated(baseURL: URL, accessToken: String?, refreshToken: String?) {
        guard let host = baseURL.host else { return }
        let storage = HTTPCookieStorage.shared

        if let accessToken {
            let properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .path: "/",
                .name: "authToken",
                .value: accessToken,
                .secure: "TRUE"
            ]
            if let cookie = HTTPCookie(properties: properties) {
                storage.setCookie(cookie)
            }
        }

        if let refreshToken {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .path: "/",
                .name: "refreshToken",
                .value: refreshToken,
                .secure: "TRUE"
            ]
            properties[.expires] = Date().addingTimeInterval(Self.refreshTokenExpiry)
            if let cookie = HTTPCookie(properties: properties) {
                storage.setCookie(cookie)
            }
        }
    }

    private func syncCookies() {
        Self.syncCookiesNonisolated(baseURL: baseURL, accessToken: accessToken, refreshToken: refreshToken)
    }

    private func clearCookies() {
        guard let host = baseURL.host else { return }
        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach { cookie in
            if cookie.domain.contains(host), cookie.name == "authToken" || cookie.name == "refreshToken" {
                storage.deleteCookie(cookie)
            }
        }
    }

    nonisolated private static func loadToken(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func storeToken(_ value: String?, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        guard let value else { return }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
