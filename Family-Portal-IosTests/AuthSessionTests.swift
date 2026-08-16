import Foundation
import Testing
@testable import Family_Portal_Ios

/// The JWT the backend issues lives 24 hours (backend/auth.go
/// `setAuthJwtCookie`), while a login is meant to last 30 days on the refresh
/// token. `ensureFreshAccessToken` is what bridges the two on resume, and it can
/// only do that if the `exp` claim reads correctly.
@Suite("Access token expiry")
struct AuthSessionTests {

    /// Builds an unsigned token with the given claims. Only the payload segment
    /// is ever read — the signature is the server's business.
    private func makeToken(claims: [String: Any]) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: claims)
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    @Test("Reads the exp claim from a base64url payload")
    func readsExpiry() throws {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let token = try makeToken(claims: [
            "username": "ada@example.com",
            "exp": expiry.timeIntervalSince1970
        ])

        let parsed = try #require(APIClient.jwtExpiry(token))
        #expect(abs(parsed.timeIntervalSince(expiry)) < 1)
    }

    /// Padding is stripped from real JWTs, so every payload length has to decode
    /// — a payload that failed to parse would look like an expired token and
    /// trigger a refresh on every resume.
    @Test("Decodes payloads of any length", arguments: 1...8)
    func decodesUnpaddedPayloads(nameLength: Int) throws {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let token = try makeToken(claims: [
            "username": String(repeating: "a", count: nameLength),
            "exp": expiry.timeIntervalSince1970
        ])

        let parsed = try #require(APIClient.jwtExpiry(token))
        #expect(abs(parsed.timeIntervalSince(expiry)) < 1)
    }

    @Test("Returns nil rather than a date for tokens it cannot read", arguments: [
        "",
        "not-a-jwt",
        "header.payload",
        "header.!!!not-base64!!!.signature"
    ])
    func rejectsMalformedTokens(token: String) {
        #expect(APIClient.jwtExpiry(token) == nil)
    }

    @Test("Returns nil when the payload carries no exp claim")
    func rejectsTokenWithoutExpiry() throws {
        let token = try makeToken(claims: ["username": "ada@example.com"])
        #expect(APIClient.jwtExpiry(token) == nil)
    }
}
