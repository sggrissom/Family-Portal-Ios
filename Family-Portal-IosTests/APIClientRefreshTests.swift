import Foundation
import Testing
@testable import Family_Portal_Ios

/// Everything the app does with an expiring session runs through
/// `refreshAccessToken`: the 401 retry inside `request`, the proactive refresh
/// the WebSocket and `RemotePhotoView` depend on, and the single decision that
/// ends a session. It is also the one path where a mistake signs a user out for
/// good, so it is worth pinning.
///
/// Serialized because the client's token storage (keychain and the shared cookie
/// jar) is process-wide; parallel cases would clear each other's credentials.
@MainActor
@Suite("APIClient refresh and retry", .serialized)
struct APIClientRefreshTests {

    private struct EmptyPayload: Encodable {}

    /// The refresh token only ever arrives as a cookie, so this is how a session
    /// with something to refresh is set up.
    private nonisolated static func seedRefreshCookie(host: String, value: String = "refresh-token") {
        let cookie = HTTPCookie(properties: [
            .domain: host,
            .path: "/",
            .name: "refreshToken",
            .value: value,
            .expires: Date().addingTimeInterval(3600)
        ])!
        HTTPCookieStorage.shared.setCookie(cookie)
    }

    private nonisolated static func familyInfo() -> [String: Any] {
        ["id": 7, "name": "Ashby", "inviteCode": "ABC123", "families": [[String: Any]]()]
    }

    private nonisolated static func refreshSuccess(token: String = "fresh-jwt") -> FakeHTTPServer.Response {
        .json(
            ["success": true, "token": token],
            headers: ["Set-Cookie": "refreshToken=rotated-token; Path=/"]
        )
    }

    /// Records whether the client declared the session over.
    @MainActor
    private final class SessionFlag {
        var expired = false
    }

    // MARK: - 401 retry

    @Test("A 401 refreshes the token and replays the request once")
    func retriesAfterRefresh() async throws {
        let server = FakeHTTPServer()
        server.routeSequence("rpc/GetFamilyInfo", [
            .status(401, message: "token expired"),
            .json(Self.familyInfo())
        ])
        server.route("api/refresh", respond: Self.refreshSuccess())
        Self.seedRefreshCookie(host: server.host)

        let client = server.apiClient()
        await client.setAccessToken("stale-jwt")

        let response: FamilyInfoResponseDTO = try await client.callRPC(.getFamilyInfo, payload: EmptyPayload())

        #expect(response.name == "Ashby")
        #expect(server.requests(for: "api/refresh").count == 1)
        #expect(server.requests(for: "rpc/GetFamilyInfo").count == 2)
        #expect(await client.getAccessToken() == "fresh-jwt")

        // The replay carries the new token, not the one that was just rejected.
        let replay = server.requests(for: "rpc/GetFamilyInfo").last
        #expect(replay?.headers["Authorization"] == "Bearer fresh-jwt")
    }

    @Test("A second 401 is not retried again")
    func retriesOnlyOnce() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetFamilyInfo", respond: .status(401, message: "token expired"))
        server.route("api/refresh", respond: Self.refreshSuccess())
        Self.seedRefreshCookie(host: server.host)

        let client = server.apiClient()
        await client.setAccessToken("stale-jwt")

        await #expect(throws: APIError.self) {
            let _: FamilyInfoResponseDTO = try await client.callRPC(.getFamilyInfo, payload: EmptyPayload())
        }
        #expect(server.requests(for: "rpc/GetFamilyInfo").count == 2)
        #expect(server.requests(for: "api/refresh").count == 1)
    }

    // MARK: - Ending the session

    @Test("A rejected refresh token ends the session")
    func rejectedRefreshEndsSession() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetFamilyInfo", respond: .status(401, message: "token expired"))
        server.route("api/refresh", respond: .status(401, message: "refresh token revoked"))
        Self.seedRefreshCookie(host: server.host)

        let client = server.apiClient()
        await client.setAccessToken("stale-jwt")

        let flag = SessionFlag()
        await client.setSessionExpiredHandler { flag.expired = true }

        await #expect(throws: APIError.self) {
            let _: FamilyInfoResponseDTO = try await client.callRPC(.getFamilyInfo, payload: EmptyPayload())
        }

        #expect(flag.expired)
        #expect(await client.hasRefreshCredential == false)
        #expect(await client.getAccessToken() == nil)
    }

    /// A 500 from `api/refresh` says nothing about the stored credential, and
    /// treating it as a rejection would sign people out every time the server
    /// had a bad minute.
    @Test("A server-side refresh failure leaves the session intact")
    func serverErrorKeepsSession() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetFamilyInfo", respond: .status(401, message: "token expired"))
        server.route("api/refresh", respond: .status(500, message: "database is down"))
        Self.seedRefreshCookie(host: server.host)

        let client = server.apiClient()
        await client.setAccessToken("stale-jwt")

        let flag = SessionFlag()
        await client.setSessionExpiredHandler { flag.expired = true }

        await #expect(throws: APIError.self) {
            let _: FamilyInfoResponseDTO = try await client.callRPC(.getFamilyInfo, payload: EmptyPayload())
        }

        #expect(flag.expired == false)
        #expect(await client.hasRefreshCredential)
    }

    @Test("A refresh with no credential to spend never reaches the network")
    func refreshWithoutCredentialFails() async throws {
        let server = FakeHTTPServer()
        server.route("api/refresh", respond: Self.refreshSuccess())

        let client = server.apiClient()
        await client.clearTokens()

        await #expect(throws: APIError.self) {
            try await client.refreshAccessToken()
        }
        #expect(server.requests(for: "api/refresh").isEmpty)
    }

    // MARK: - Single flight

    /// The server rotates the refresh token on every use, so two refreshes in
    /// flight can each invalidate the other's credential and end a live session.
    /// A photo grid mounting twenty `RemotePhotoView`s at once is exactly that
    /// shape, which is why they all have to share one round trip.
    @Test("Overlapping refreshes share a single round trip")
    func concurrentRefreshesCoalesce() async throws {
        let server = FakeHTTPServer()
        server.route("api/refresh") { _ in
            // Long enough that every caller below is waiting on this one call.
            Thread.sleep(forTimeInterval: 0.3)
            return Self.refreshSuccess()
        }
        Self.seedRefreshCookie(host: server.host)

        let client = server.apiClient()
        await client.setAccessToken("stale-jwt")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = try? await client.refreshAccessToken()
                }
            }
        }

        #expect(server.requests(for: "api/refresh").count == 1)
        #expect(await client.getAccessToken() == "fresh-jwt")
    }

    // MARK: - Proactive refresh

    @Test("A token that is still good is left alone")
    func freshTokenIsNotRefreshed() async throws {
        let server = FakeHTTPServer()
        server.route("api/refresh", respond: Self.refreshSuccess())
        Self.seedRefreshCookie(host: server.host)

        let client = server.apiClient()
        await client.setAccessToken(Self.jwt(expiringIn: 60 * 60))

        await client.ensureFreshAccessToken()

        #expect(server.requests(for: "api/refresh").isEmpty)
    }

    @Test("A token inside the expiry margin is refreshed before it is used")
    func expiringTokenIsRefreshed() async throws {
        let server = FakeHTTPServer()
        server.route("api/refresh", respond: Self.refreshSuccess())
        Self.seedRefreshCookie(host: server.host)

        let client = server.apiClient()
        await client.setAccessToken(Self.jwt(expiringIn: 60))

        await client.ensureFreshAccessToken()

        #expect(server.requests(for: "api/refresh").count == 1)
        #expect(await client.getAccessToken() == "fresh-jwt")
    }

    /// An unsigned token: only the `exp` claim in the payload is ever read.
    private nonisolated static func jwt(expiringIn interval: TimeInterval) -> String {
        let claims: [String: Any] = ["exp": Date().addingTimeInterval(interval).timeIntervalSince1970]
        let payload = (try? JSONSerialization.data(withJSONObject: claims)) ?? Data()
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }
}
