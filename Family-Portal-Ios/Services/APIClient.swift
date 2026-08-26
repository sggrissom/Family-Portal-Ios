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
            if let sentence = APIError.procSentence(statusCode: statusCode, message: message) {
                return sentence
            }
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

    static func procSentence(statusCode: Int, message: String?) -> String? {
        guard statusCode == 400, let message else { return nil }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 200,
              !trimmed.contains("\n"),
              let first = trimmed.first,
              first != "<", first != "{", first != "[" else {
            return nil
        }
        return trimmed
    }
}

enum AccountDeletionError: LocalizedError, Equatable {
    case refused(String)

    static let fallbackMessage = "Could not delete your account."

    var errorDescription: String? {
        switch self {
        case .refused(let message):
            return message
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

    private static let keychainAccessToken = AppConstants.Keychain.accessToken
    private static let keychainRefreshToken = AppConstants.Keychain.refreshToken
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

    private static let sharedDecoder: JSONDecoder = {
        let formatters = dateFormatters
        let decoder = JSONDecoder()
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
        return decoder
    }()

    private static let sharedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    nonisolated static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try sharedDecoder.decode(type, from: data)
    }

    private var baseURL: URL
    private var accessToken: String?
    private var refreshToken: String?
    private let session: URLSession
    private let clientId: String

    private var onSessionExpired: (@MainActor () async -> Void)?

    private nonisolated static let defaultURL = URL(string: AppConstants.defaultServerURL)!

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        let initialBaseURL = baseURL ?? Self.defaultURL
        self.session = session

        clientId = UUID().uuidString

        let loadedAccessToken = Self.loadToken(forKey: Self.keychainAccessToken)
        // Older installs may hold the refresh token only in the cookie jar; adopting it here upgrades them instead of signing them out.
        let storedRefreshToken = Self.loadToken(forKey: Self.keychainRefreshToken)
        let loadedRefreshToken = storedRefreshToken ?? Self.refreshCookie(for: initialBaseURL)?.value
        if storedRefreshToken == nil, let loadedRefreshToken {
            Self.storeToken(loadedRefreshToken, key: Self.keychainRefreshToken)
        }
        accessToken = loadedAccessToken
        refreshToken = loadedRefreshToken

        self.baseURL = initialBaseURL

        Self.syncCookiesNonisolated(baseURL: self.baseURL, accessToken: loadedAccessToken, refreshToken: loadedRefreshToken)
    }

    func setSessionExpiredHandler(_ handler: (@MainActor () async -> Void)?) {
        onSessionExpired = handler
    }

    /// Private on purpose: passing `nil` for the refresh token silently throws away a live session. Use `setAccessToken`.
    private func setTokens(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        Self.storeToken(accessToken, key: Self.keychainAccessToken)
        Self.storeToken(refreshToken, key: Self.keychainRefreshToken)
        syncCookies()
    }

    func setAccessToken(_ token: String?) {
        accessToken = token
        Self.storeToken(token, key: Self.keychainAccessToken)
        syncCookies()
    }

    var hasRefreshCredential: Bool {
        refreshToken != nil || Self.refreshCookie(for: baseURL) != nil
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
                return try Self.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    func callRPC<T: Decodable, Body: Encodable>(_ proc: RPCMethod, payload: Body) async throws -> T {
        try await request(path: "rpc/\(proc.rawValue)", method: .post, body: payload, requiresAuth: true)
    }

    func callRPCData<Body: Encodable>(_ proc: RPCMethod, payload: Body) async throws -> Data {
        try await requestData(path: "rpc/\(proc.rawValue)", method: .post, body: payload, requiresAuth: true)
    }

    func callPublicRPC<T: Decodable, Body: Encodable>(_ proc: RPCMethod, payload: Body) async throws -> T {
        try await request(
            path: "rpc/\(proc.rawValue)",
            method: .post,
            body: payload,
            requiresAuth: false,
            retryOnAuthFailure: false
        )
    }

    func request<T: Decodable, Body: Encodable>(
        path: String,
        method: HTTPMethod = .post,
        body: Body? = nil,
        requiresAuth: Bool = true,
        retryOnAuthFailure: Bool = true
    ) async throws -> T {
        let data = try await requestData(
            path: path,
            method: method,
            body: body,
            requiresAuth: requiresAuth,
            retryOnAuthFailure: retryOnAuthFailure
        )
        do {
            return try Self.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func requestData<Body: Encodable>(
        path: String,
        method: HTTPMethod = .post,
        body: Body? = nil,
        requiresAuth: Bool = true,
        retryOnAuthFailure: Bool = true
    ) async throws -> Data {
        guard let url = makeURL(for: path) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(clientId, forHTTPHeaderField: "X-Client-Id")

        if let body = body {
            do {
                urlRequest.httpBody = try Self.sharedEncoder.encode(body)
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
                return try await requestData(path: path, method: method, body: body, requiresAuth: requiresAuth, retryOnAuthFailure: false)
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

            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    func checkMobileVersion(appVersion: String) async throws -> MobileVersionPolicyDTO {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("api/mobile-version"),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "appVersion", value: appVersion)
        ]

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = HTTPMethod.get.rawValue
        urlRequest.setValue(clientId, forHTTPHeaderField: "X-Client-Id")

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.server(
                    statusCode: httpResponse.statusCode,
                    message: String(data: data, encoding: .utf8)
                )
            }

            do {
                return try Self.decode(MobileVersionPolicyDTO.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    /// Throws `AccountDeletionError.refused` with the server's own sentence for a wrong password or a mistyped email.
    func deleteAccount(password: String, confirmEmail: String) async throws {
        let payload = DeleteAccountRequestDTO(password: password, confirmEmail: confirmEmail)

        let data: Data
        do {
            data = try await requestData(path: "api/delete-account", method: .post, body: payload)
        } catch APIError.server(let statusCode, let message) where statusCode == 400 {
            throw AccountDeletionError.refused(Self.deletionRefusal(from: message))
        }

        let response: DeleteAccountResponseDTO
        do {
            response = try Self.decode(DeleteAccountResponseDTO.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }

        // Belt and braces: a `success: false` returning normally would otherwise be read as a deleted account and erase the device.
        guard response.success else {
            throw AccountDeletionError.refused(response.error ?? AccountDeletionError.fallbackMessage)
        }
    }

    private static func deletionRefusal(from message: String?) -> String {
        guard let message, let data = message.data(using: .utf8),
              let response = try? decode(DeleteAccountResponseDTO.self, from: data),
              let error = response.error, !error.isEmpty else {
            return AccountDeletionError.fallbackMessage
        }
        return error
    }

    func ensureFreshAccessToken(margin: TimeInterval = 5 * 60) async {
        guard hasRefreshCredential else { return }

        if let accessToken, let expiry = Self.jwtExpiry(accessToken),
           expiry.timeIntervalSinceNow > margin {
            return
        }

        try? await refreshAccessToken()
    }

    /// Coalesces overlapping refreshes onto one round-trip. The server rotates the refresh token on every use, so two in flight can each invalidate the other's credential.
    private var refreshTask: Task<Void, Error>?

    func refreshAccessToken() async throws {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }

        return try await task.value
    }

    private func performRefresh() async throws {
        guard hasRefreshCredential else {
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
                if httpResponse.statusCode == 401 {
                    await endSession()
                }
                throw APIError.refreshFailed(message)
            }

            let refreshResponse: RefreshResponseDTO
            do {
                refreshResponse = try Self.decode(RefreshResponseDTO.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }

            guard refreshResponse.success, let token = refreshResponse.token else {
                await endSession()
                throw APIError.refreshFailed(refreshResponse.error)
            }

            setAccessToken(token)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    private func endSession() async {
        clearTokens()
        if let onSessionExpired {
            await onSessionExpired()
        }
    }

    nonisolated static func jwtExpiry(_ token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }

        guard let data = Data(base64Encoded: payload),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let exp = object["exp"] as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    nonisolated private static func refreshCookie(for baseURL: URL) -> HTTPCookie? {
        HTTPCookieStorage.shared.cookies(for: baseURL)?.first {
            $0.name == "refreshToken" && !$0.value.isEmpty
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

        for cookie in cookies where !cookie.value.isEmpty {
            // An empty value is the server expiring the cookie; storing it would only fake a credential.
            if cookie.name == "authToken" {
                updatedAccessToken = cookie.value
            } else if cookie.name == "refreshToken" {
                updatedRefreshToken = cookie.value
            }
        }

        if updatedRefreshToken == nil, let jarToken = Self.refreshCookie(for: baseURL)?.value,
           jarToken != refreshToken {
            updatedRefreshToken = jarToken
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

// MARK: - Chat API

extension APIClient {
    func sendMessage(content: String, clientMessageId: String) async throws -> ChatMessageDTO {
        let request = SendMessageRequestDTO(content: content, clientMessageId: clientMessageId)
        let response: SendMessageResponseDTO = try await callRPC(.sendMessage, payload: request)
        return response.message
    }

    func getChatMessages(limit: Int, offset: Int) async throws -> [ChatMessageDTO] {
        let request = GetChatMessagesRequestDTO(limit: limit, offset: offset)
        let response: GetChatMessagesResponseDTO = try await callRPC(.getChatMessages, payload: request)
        return response.messages
    }

    func deleteMessage(id: Int) async throws -> Bool {
        let request = DeleteMessageRequestDTO(messageId: id)
        let response: DeleteMessageResponseDTO = try await callRPC(.deleteMessage, payload: request)
        return response.success
    }
}
