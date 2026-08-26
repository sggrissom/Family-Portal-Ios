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

    /// A rejected proc's own words, when the body is one.
    ///
    /// `vbeam.RespondError` writes `w.WriteHeader(400)` and then
    /// `fmt.Fprintf(w, err.Error())` — no JSON, no `success: false` — so the
    /// body of a 400 *is* the error. Activities is the first feature whose
    /// backend returns strings meant for a user rather than for a log
    /// ("That entry is not in the same season as this competition",
    /// "A rank must be 1 or greater, and no greater than the field size"), and
    /// wrapping those in `Server error (400): …` buries the only useful part of
    /// the alert behind a status code the reader can do nothing with.
    ///
    /// The guards keep this to bodies that really are a sentence. A 400 can also
    /// carry an HTML error page from something in front of the app, or a JSON
    /// envelope from a handler that is not a proc, and neither of those is worth
    /// showing verbatim — those fall back to the generic wording.
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

/// A refusal from `POST /api/delete-account`, carrying the server's wording.
///
/// Its own type rather than an `APIError` case, on the same reasoning as
/// `MembershipError`: the two refusals it represents — an incorrect password
/// and a mistyped confirmation address — are instructions to the user rather
/// than reports about the network, so the view shows the sentence inline next
/// to the field that produced it instead of raising the app-wide alert.
enum AccountDeletionError: LocalizedError, Equatable {
    case refused(String)

    /// Used when the server refuses without a sentence, which the handler does
    /// not do today — but a proxy answering 400 in its place would.
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

    // Local constants to avoid main actor isolation issues
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

    /// Shared entry point for every JSON body the server sends, including the
    /// WebSocket stream — its date strategy tolerates RFC3339 with fractional
    /// seconds, which is what Go's `time.Time` marshals.
    nonisolated static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try sharedDecoder.decode(type, from: data)
    }

    private var baseURL: URL
    private var accessToken: String?
    private var refreshToken: String?
    private let session: URLSession
    private let clientId: String

    /// Called when the server rejects the refresh token outright, which is the
    /// one failure the app cannot recover from without the user. Set by
    /// `AuthService` so a dead session collapses back to the sign-in screen
    /// instead of leaving every request failing.
    private var onSessionExpired: (@MainActor () async -> Void)?

    private nonisolated static let defaultURL = URL(string: AppConstants.defaultServerURL)!

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        let initialBaseURL = baseURL ?? Self.defaultURL
        self.session = session

        clientId = UUID().uuidString

        let loadedAccessToken = Self.loadToken(forKey: Self.keychainAccessToken)
        // Builds before the refresh token was kept properly dropped it from the
        // keychain at login, so an install may only have it in the cookie jar.
        // Adopting it here upgrades those sessions instead of signing them out.
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

    /// Private on purpose: callers outside the client only ever have the JWT
    /// from a response body, and passing `nil` for the refresh token here
    /// silently throws away a live session. Use `setAccessToken` instead.
    private func setTokens(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        Self.storeToken(accessToken, key: Self.keychainAccessToken)
        Self.storeToken(refreshToken, key: Self.keychainRefreshToken)
        syncCookies()
    }

    /// Banks a newly issued JWT while leaving the refresh token alone.
    ///
    /// Login, sign-up and refresh all return the JWT in their response body but
    /// the refresh token only in a `Set-Cookie` header, which `captureTokens`
    /// has already banked by the time a caller gets here. Routing those callers
    /// through `setTokens(accessToken:refreshToken: nil)` would erase the
    /// refresh token they just received and cap the session at the JWT's 24
    /// hours — which is exactly what used to happen.
    func setAccessToken(_ token: String?) {
        accessToken = token
        Self.storeToken(token, key: Self.keychainAccessToken)
        syncCookies()
    }

    /// Whether there is anything to refresh with. The cookie jar is consulted
    /// as well as the keychain because the server only ever hands the refresh
    /// token over as a cookie.
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

    /// The raw response body of a proc, for a caller that needs to both decode
    /// it and keep it. `ActivityService` writes exactly these bytes to its
    /// snapshot cache, so a field this build ignores is still there for the
    /// build that reads it — and its response types never need to be
    /// `Encodable`.
    func callRPCData<Body: Encodable>(_ proc: RPCMethod, payload: Body) async throws -> Data {
        try await requestData(path: "rpc/\(proc.rawValue)", method: .post, body: payload, requiresAuth: true)
    }

    /// For the procs a signed-out user has to reach: `CreateAccount`,
    /// `RequestPasswordReset`. No token is attached and a 401 is never retried,
    /// because there is no session to refresh.
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

    /// Everything `request` does except decode. Split out so a caller that wants
    /// the bytes and a caller that wants a type share one code path — the auth
    /// headers, the token capture, the 401 refresh-and-retry, and the error
    /// mapping are the parts that must not drift apart.
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

    /// `GET /api/mobile-version` (backend/mobile_version.go). Deliberately
    /// pre-auth and cached 300s server-side, so the app can decide whether it
    /// must update before it presents login. Rejects anything that isn't strict
    /// major.minor.patch with a 400.
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

    /// `POST /api/delete-account` (backend/account_deletion.go). Destroys the
    /// account: credentials, sessions, refresh tokens, registered devices and
    /// the user's chat messages, plus any family the deletion leaves empty and
    /// everything in it.
    ///
    /// A plain handler rather than a proc, because it has to clear the session
    /// cookies it is invalidating — but unlike `checkMobileVersion` it is
    /// authenticated, so it goes through `requestData` and inherits the auth
    /// header and the 401 refresh-and-retry rather than hand-rolling them.
    ///
    /// Throws `AccountDeletionError.refused` with the server's own sentence for
    /// a wrong password or a mistyped email. Those are the two things the user
    /// can fix by typing again, so they must not arrive wrapped in a status
    /// code — and `APIError.procSentence` declines to unwrap them, because the
    /// body of this refusal is a JSON envelope rather than a bare sentence.
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

        // The handler answers a refusal with 400, so this is belt and braces —
        // but a `success: false` that returned normally would otherwise be read
        // as a deleted account and erase the device.
        guard response.success else {
            throw AccountDeletionError.refused(response.error ?? AccountDeletionError.fallbackMessage)
        }
    }

    /// The `error` out of a `DeleteAccountResponse`, for the 400 path where the
    /// envelope arrives as an error body rather than a decoded response.
    private static func deletionRefusal(from message: String?) -> String {
        guard let message, let data = message.data(using: .utf8),
              let response = try? decode(DeleteAccountResponseDTO.self, from: data),
              let error = response.error, !error.isEmpty else {
            return AccountDeletionError.fallbackMessage
        }
        return error
    }

    /// Refreshes the JWT if it is missing, expired, or about to expire.
    ///
    /// The 401 retry in `request` covers most of this, but the WebSocket and
    /// the photo loader take `getAccessToken()` and use it directly, so they
    /// need a token that is already good. An app resumed after more than a day
    /// in the background has an expired one.
    func ensureFreshAccessToken(margin: TimeInterval = 5 * 60) async {
        guard hasRefreshCredential else { return }

        if let accessToken, let expiry = Self.jwtExpiry(accessToken),
           expiry.timeIntervalSinceNow > margin {
            return
        }

        try? await refreshAccessToken()
    }

    /// Coalesces overlapping refreshes onto one network round-trip.
    ///
    /// The server rotates the refresh token on every use, so two refreshes in
    /// flight at once can each invalidate the other's credential and end a live
    /// session. Actor isolation alone does not prevent that: `refreshAccessToken`
    /// suspends on its request, letting the next caller straight through the
    /// freshness check. A photo grid mounting twenty `RemotePhotoView`s at once
    /// is exactly that shape.
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
                // A 401 here is the server saying the refresh token is expired,
                // unknown, or revoked — the session is over. Any other status is
                // a server-side problem the stored token may well outlive, so
                // it must not cost the user their sign-in.
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

            // `captureTokens` has already stored the rotated refresh token that
            // came back with this response; only the JWT is left to bank.
            setAccessToken(token)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error)
        }
    }

    /// Drops the local session and lets `AuthService` return to the sign-in
    /// screen. Only called when the server has rejected the refresh token.
    private func endSession() async {
        clearTokens()
        if let onSessionExpired {
            await onSessionExpired()
        }
    }

    /// Reads the `exp` claim without verifying the signature — the server does
    /// that. This only decides when to ask for a new token.
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

        for cookie in cookies where !cookie.value.isEmpty {
            // An empty value is the server expiring the cookie (logout, or a
            // rejected refresh). Those paths call `clearTokens` themselves;
            // storing the empty string here would only fake a credential.
            if cookie.name == "authToken" {
                updatedAccessToken = cookie.value
            } else if cookie.name == "refreshToken" {
                updatedRefreshToken = cookie.value
            }
        }

        // The server rotates the refresh token on every refresh, and losing a
        // rotation ends the session — so fall back to the jar URLSession has
        // already filled in rather than trusting this parse of the combined
        // `Set-Cookie` header. Absence is ignored: only `clearTokens` forgets.
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

    /// No defaults: the page size is `ChatService.pageSize` and the offset is the
    /// paging cursor, so a default here would be a second copy of a number that
    /// has to agree with the one the caller keeps.
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
