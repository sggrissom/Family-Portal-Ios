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

    private var baseURL: URL
    private var accessToken: String?
    private var refreshToken: String?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let clientId: String

    init(baseURL: URL = URL(string: AppConstants.defaultServerURL)!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.calendar = Calendar(identifier: .iso8601)
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = isoFormatter.date(from: dateString) ?? fallbackISOFormatter.date(from: dateString) {
                return date
            }
            if let date = dateOnlyFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
        }
        encoder.dateEncodingStrategy = .iso8601

        clientId = UUID().uuidString

        accessToken = Self.loadToken(forKey: AppConstants.Keychain.accessToken)
        refreshToken = Self.loadToken(forKey: AppConstants.Keychain.refreshToken)
        if let savedURLString = Self.loadToken(forKey: AppConstants.Keychain.serverURL), let savedURL = URL(string: savedURLString) {
            baseURL = savedURL
        }
        syncCookies()
    }

    func updateBaseURL(_ url: URL) {
        baseURL = url
        Self.storeToken(url.absoluteString, key: AppConstants.Keychain.serverURL)
        syncCookies()
    }

    func setTokens(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        Self.storeToken(accessToken, key: AppConstants.Keychain.accessToken)
        Self.storeToken(refreshToken, key: AppConstants.Keychain.refreshToken)
        syncCookies()
    }

    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        Self.storeToken(nil, key: AppConstants.Keychain.accessToken)
        Self.storeToken(nil, key: AppConstants.Keychain.refreshToken)
        clearCookies()
    }

    func getBaseURL() -> URL { baseURL }

    func getAccessToken() -> String? { accessToken }

    func uploadMultipart<T: Decodable>(path: String, formData: Data, boundary: String, retryOnAuthFailure: Bool = true) async throws -> T {
        guard let url = makeURL(for: path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(clientId, forHTTPHeaderField: "X-Client-Id")
        request.httpBody = formData

        addAuthHeaders(to: &request, requiresAuth: true)

        do {
            let (data, response) = try await session.data(for: request)
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
                return try decoder.decode(T.self, from: data)
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

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientId, forHTTPHeaderField: "X-Client-Id")

        if let body = body {
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw APIError.network(error)
            }
        }

        addAuthHeaders(to: &request, requiresAuth: requiresAuth)

        do {
            let (data, response) = try await session.data(for: request)
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
                return try decoder.decode(T.self, from: data)
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

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientId, forHTTPHeaderField: "X-Client-Id")
        addAuthHeaders(to: &request, requiresAuth: false)

        do {
            let (data, response) = try await session.data(for: request)
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
                refreshResponse = try decoder.decode(RefreshResponseDTO.self, from: data)
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

    private func syncCookies() {
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
            properties[.expires] = Date().addingTimeInterval(AppConstants.TokenExpiry.refreshToken)
            if let cookie = HTTPCookie(properties: properties) {
                storage.setCookie(cookie)
            }
        }
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

    private static func loadToken(forKey key: String) -> String? {
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

    private static func storeToken(_ value: String?, key: String) {
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
