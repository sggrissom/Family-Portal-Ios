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

/// A refusal the backend carries in the response body rather than the status code: vbeam answers `{ success: false, error: … }` with HTTP 200, and account deletion sends the same envelope with a 400. `message` is the server's own sentence, or the caller's fallback when it gave none.
nonisolated struct ServerRefusal: LocalizedError, Equatable, Sendable {
    let message: String

    static let accountDeletionFallback = "Could not delete your account."

    var errorDescription: String? { message }
}

/// A response that reports a refusal in its body. See `ServerRefusal`.
nonisolated protocol Refusable {
    var success: Bool { get }
    var error: String? { get }
}

nonisolated extension Refusable {
    /// The response when the server agreed; otherwise throws its sentence, or `fallback` when it gave none.
    func accepted(or fallback: String) throws -> Self {
        guard success else { throw ServerRefusal(message: error ?? fallback) }
        return self
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
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
            dateOnlyFormatter.timeZone = .gmt
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

    /// `decode` for a response body, with a failure reported as `APIError.decoding`.
    nonisolated static func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decode(type, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private var baseURL: URL
    private var accessToken: String?
    private var refreshToken: String?
    private let session: URLSession
    private let clientId: String

    private var onSessionExpired: (@MainActor () async -> Void)?

    private nonisolated static let defaultURL = URL(string: AppConstants.defaultServerURL)!

    /// The system default waits 60 seconds for a stalled connection. Everything this client sends is either queued for a retry or backed by local data, so a weak signal should give up and fall back well before that.
    nonisolated static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    init(baseURL: URL? = nil, session: URLSession = APIClient.defaultSession) {
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

    func uploadMultipart<T: Decodable>(path: String, formData: Data, boundary: String) async throws -> T {
        var request = try makeRequest(path, method: .post)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = formData
        let data = try await send(request, requiresAuth: true, retryOnAuthFailure: true)
        return try Self.decodeResponse(T.self, from: data)
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
        return try Self.decodeResponse(T.self, from: data)
    }

    func requestData<Body: Encodable>(
        path: String,
        method: HTTPMethod = .post,
        body: Body? = nil,
        requiresAuth: Bool = true,
        retryOnAuthFailure: Bool = true
    ) async throws -> Data {
        var request = try makeRequest(path, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            do {
                request.httpBody = try Self.sharedEncoder.encode(body)
            } catch {
                throw APIError.network(error)
            }
        }
        return try await send(request, requiresAuth: requiresAuth, retryOnAuthFailure: retryOnAuthFailure)
    }

    /// One round trip with this client's headers. A 401 on an authenticated request refreshes the token and retries once, when `retryOnAuthFailure` allows; any other status outside 2xx, or an empty body, throws.
    private func send(_ request: URLRequest, requiresAuth: Bool, retryOnAuthFailure: Bool) async throws -> Data {
        var request = request
        request.setValue(clientId, forHTTPHeaderField: "X-Client-Id")
        addAuthHeaders(to: &request, requiresAuth: requiresAuth)
        let (data, response) = try await transport(request)

        if response.statusCode == 401, requiresAuth, retryOnAuthFailure {
            try await refreshAccessToken()
            return try await send(request, requiresAuth: requiresAuth, retryOnAuthFailure: false)
        }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.server(statusCode: response.statusCode, message: String(data: data, encoding: .utf8))
        }
        guard !data.isEmpty else {
            throw APIError.invalidResponse
        }
        return data
    }

    /// The bare exchange: a transport failure is `.network`, and any tokens the response sets are kept unless `capturingTokens` is off.
    private func transport(_ request: URLRequest, capturingTokens: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if capturingTokens {
            captureTokens(from: http)
        }
        return (data, http)
    }

    private func makeRequest(_ path: String, method: HTTPMethod) throws -> URLRequest {
        guard let url = makeURL(for: path) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        return request
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

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue(clientId, forHTTPHeaderField: "X-Client-Id")

        let (data, response) = try await transport(request, capturingTokens: false)
        guard (200...299).contains(response.statusCode) else {
            throw APIError.server(statusCode: response.statusCode, message: String(data: data, encoding: .utf8))
        }
        return try Self.decodeResponse(MobileVersionPolicyDTO.self, from: data)
    }

    /// Throws a `ServerRefusal` with the server's own sentence for a wrong password or a mistyped email.
    func deleteAccount(password: String, confirmEmail: String) async throws {
        let payload = DeleteAccountRequestDTO(password: password, confirmEmail: confirmEmail)

        let data: Data
        do {
            data = try await requestData(path: "api/delete-account", method: .post, body: payload)
        } catch APIError.server(let statusCode, let message) where statusCode == 400 {
            throw ServerRefusal(message: Self.deletionRefusal(from: message))
        }

        // Belt and braces: a `success: false` returning normally would otherwise be read as a deleted account and erase the device.
        _ = try Self.decodeResponse(DeleteAccountResponseDTO.self, from: data).accepted(or: ServerRefusal.accountDeletionFallback)
    }

    private static func deletionRefusal(from message: String?) -> String {
        guard let message, let data = message.data(using: .utf8),
              let response = try? decode(DeleteAccountResponseDTO.self, from: data),
              let error = response.error, !error.isEmpty else {
            return ServerRefusal.accountDeletionFallback
        }
        return error
    }

    func ensureFreshAccessToken(margin: TimeInterval = 5 * 60) async {
        guard hasRefreshCredential else { return }

        if let accessToken, let expiry = Self.jwtExpiry(accessToken),
           expiry.timeIntervalSinceNow > margin {
            return
        }

        _ = try? await refreshAccessToken()
    }

    /// Coalesces overlapping refreshes onto one round-trip. The server rotates the refresh token on every use, so two in flight can each invalidate the other's credential.
    private var refreshTask: Task<AuthResponseDTO?, Error>?

    /// Returns the identity the server sent alongside the new token, when it sent one.
    @discardableResult
    func refreshAccessToken() async throws -> AuthResponseDTO? {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }

        return try await task.value
    }

    private func performRefresh() async throws -> AuthResponseDTO? {
        guard hasRefreshCredential else {
            throw APIError.missingRefreshToken
        }

        var request = try makeRequest("api/refresh", method: .post)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientId, forHTTPHeaderField: "X-Client-Id")
        addAuthHeaders(to: &request, requiresAuth: false)

        let (data, response) = try await transport(request)
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 {
                await endSession()
            }
            throw APIError.refreshFailed(String(data: data, encoding: .utf8))
        }

        let refresh = try Self.decodeResponse(SessionResponseDTO.self, from: data)
        guard refresh.success, let token = refresh.token else {
            await endSession()
            throw APIError.refreshFailed(refresh.error)
        }

        setAccessToken(token)
        return refresh.auth
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

// MARK: - Original photos

/// A photo exactly as it was uploaded, downloaded to a scratch folder of its own for Share or Save to Photos. Whoever holds it removes `directory` when done.
nonisolated struct DownloadedOriginal: Sendable, Identifiable {
    let fileURL: URL
    let directory: URL
    let mimeType: String?

    var id: URL { fileURL }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// The name a downloaded original is saved under: the server's (the uploaded file's own name, from `Content-Disposition`), made safe for a path, else `photo-<id>` with an extension from the type.
nonisolated enum OriginalPhotoFile {
    static func filename(suggested: String?, mimeType: String?, photoId: Int) -> String {
        let cleaned = (suggested ?? "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if !cleaned.isEmpty, !(cleaned as NSString).pathExtension.isEmpty {
            return cleaned
        }
        let ext = fileExtension(mimeType: mimeType)
        return ext.map { "photo-\(photoId).\($0)" } ?? "photo-\(photoId)"
    }

    static func fileExtension(mimeType: String?) -> String? {
        switch mimeType?.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/tiff": return "tiff"
        default: return nil
        }
    }
}

/// Reports a download's progress from the task the async API creates.
private nonisolated final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(_ report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
            report(progress.fractionCompleted)
        }
    }
}

extension APIClient {
    /// `GET api/photo/{id}/original?download=1` — the bytes as uploaded, never a resized variant. Fetched like a photo, with the token and one refresh-and-retry on a 401, and written to disk rather than held in memory, since an original can be large.
    func downloadOriginal(photoId: Int, progress: (@Sendable (Double) -> Void)? = nil) async throws -> DownloadedOriginal {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("api/photo/\(photoId)/original"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "download", value: "1")]
        guard let url = components.url else { throw APIError.invalidURL }

        await ensureFreshAccessToken()
        var (fileURL, response) = try await downloadFile(url, progress: progress)
        if response.statusCode == 401 {
            try? FileManager.default.removeItem(at: fileURL)
            _ = try await refreshAccessToken()
            (fileURL, response) = try await downloadFile(url, progress: progress)
        }
        guard (200...299).contains(response.statusCode) else {
            try? FileManager.default.removeItem(at: fileURL)
            if response.statusCode == 401 { throw APIError.unauthorized }
            throw APIError.server(statusCode: response.statusCode, message: nil)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("originals", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = OriginalPhotoFile.filename(suggested: response.suggestedFilename, mimeType: response.mimeType, photoId: photoId)
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.moveItem(at: fileURL, to: destination)
            return DownloadedOriginal(fileURL: destination, directory: directory, mimeType: response.mimeType)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func downloadFile(_ url: URL, progress: (@Sendable (Double) -> Void)?) async throws -> (URL, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue(clientId, forHTTPHeaderField: "X-Client-Id")
        addAuthHeaders(to: &request, requiresAuth: true)
        let fileURL: URL
        let response: URLResponse
        do {
            (fileURL, response) = try await session.download(for: request, delegate: progress.map(DownloadProgressDelegate.init))
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: fileURL)
            throw APIError.invalidResponse
        }
        captureTokens(from: http)
        return (fileURL, http)
    }
}
