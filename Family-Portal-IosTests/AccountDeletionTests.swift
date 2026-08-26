import Foundation
import Testing
@testable import Family_Portal_Ios

/// `POST /api/delete-account` is the one call in the app that cannot be undone
/// and cannot be retried afterwards, so the two things worth pinning are that a
/// refusal is reported as a refusal — in the server's words, next to the field
/// that caused it — and that nothing but a genuine success is ever read as one.
///
/// The refusal path is the fiddly half. `vbeam.RespondError` writes bare
/// sentences, which `APIError.procSentence` unwraps; this handler is not a proc
/// and answers with a JSON envelope instead, which `procSentence` explicitly
/// declines to unwrap. Without `deleteAccount` decoding that envelope itself,
/// "Current password is incorrect" would reach the user as
/// `Server error (400): {"success":false,"error":"…"}`.
@Suite("Account deletion")
struct AccountDeletionTests {

    private static let confirmEmailMismatch = "Type your account's email address exactly to confirm"
    private static let incorrectPassword = "Current password is incorrect"

    private static func refusal(_ message: String) -> FakeHTTPServer.Response {
        .json(["success": false, "error": message], status: 400)
    }

    // MARK: - The request

    @Test("Sends the keys backend/account_deletion.go decodes")
    func sendsExpectedPayload() async throws {
        let server = FakeHTTPServer()
        server.route("api/delete-account", respond: .json(["success": true]))

        try await server.apiClient().deleteAccount(
            password: "hunter2",
            confirmEmail: "ada@example.com"
        )

        let request = try #require(server.requests(for: "api/delete-account").first)
        let decoded = try JSONSerialization.jsonObject(with: request.body)
        let body = try #require(decoded as? [String: Any])

        // `DeleteAccountRequest` names these fields exactly; the app's default
        // encoder does not transform key names, and this is the assertion that
        // notices if that ever changes.
        #expect(body["password"] as? String == "hunter2")
        #expect(body["confirmEmail"] as? String == "ada@example.com")
        #expect(body.count == 2)
    }

    // MARK: - Refusals

    @Test("A mistyped confirmation address reports the server's sentence")
    func mistypedEmailIsReported() async throws {
        let server = FakeHTTPServer()
        server.route("api/delete-account", respond: Self.refusal(Self.confirmEmailMismatch))

        await #expect(throws: AccountDeletionError.refused(Self.confirmEmailMismatch)) {
            try await server.apiClient().deleteAccount(
                password: "hunter2",
                confirmEmail: "typo@example.com"
            )
        }
    }

    @Test("A wrong password reports the server's sentence, not a status code")
    func wrongPasswordIsReported() async throws {
        let server = FakeHTTPServer()
        server.route("api/delete-account", respond: Self.refusal(Self.incorrectPassword))

        let error = await #expect(throws: AccountDeletionError.self) {
            try await server.apiClient().deleteAccount(
                password: "wrong",
                confirmEmail: "ada@example.com"
            )
        }

        // What the user actually reads. The status code and the JSON envelope
        // are the two things that must not appear in it.
        let sentence = try #require(error?.localizedDescription)
        #expect(sentence == Self.incorrectPassword)
        #expect(!sentence.contains("400"))
        #expect(!sentence.contains("{"))
    }

    @Test("A 400 whose body is not the expected envelope still says something usable")
    func unparseableRefusalFallsBack() async throws {
        let server = FakeHTTPServer()
        // What a proxy in front of the app answers with, rather than the handler.
        server.route("api/delete-account", respond: .status(400, message: "<html>Bad Request</html>"))

        await #expect(throws: AccountDeletionError.refused(AccountDeletionError.fallbackMessage)) {
            try await server.apiClient().deleteAccount(
                password: "hunter2",
                confirmEmail: "ada@example.com"
            )
        }
    }

    /// The handler answers refusals with 400, so this shape should never arrive.
    /// It is pinned because the cost of reading it as a success is erasing a
    /// device whose account still exists.
    @Test("A 200 carrying success: false is a refusal, not a deletion")
    func unsuccessfulTwoHundredIsARefusal() async throws {
        let server = FakeHTTPServer()
        server.route(
            "api/delete-account",
            respond: .json(["success": false, "error": Self.incorrectPassword])
        )

        await #expect(throws: AccountDeletionError.refused(Self.incorrectPassword)) {
            try await server.apiClient().deleteAccount(
                password: "wrong",
                confirmEmail: "ada@example.com"
            )
        }
    }

    @Test("Being offline is a network error, not a refusal")
    func offlineIsNotARefusal() async throws {
        let server = FakeHTTPServer()
        server.route("api/delete-account", respond: .offline())

        // The distinction matters: a refusal tells the user to correct a field,
        // while this one tells them to try again later. Reading one as the other
        // would have them retyping a password that was never wrong.
        await #expect(throws: APIError.self) {
            try await server.apiClient().deleteAccount(
                password: "hunter2",
                confirmEmail: "ada@example.com"
            )
        }
    }

    // MARK: - Success

    @Test("A successful deletion returns without throwing")
    func successReturns() async throws {
        let server = FakeHTTPServer()
        server.route("api/delete-account", respond: .json(["success": true]))

        try await server.apiClient().deleteAccount(
            password: "hunter2",
            confirmEmail: "ada@example.com"
        )
    }

    // MARK: - The envelope

    @Test("Decodes DeleteAccountResponse as the backend marshals it")
    func decodesResponse() throws {
        // `Error` carries `omitempty`, so a success omits the key entirely.
        let success = try APIClient.decode(
            DeleteAccountResponseDTO.self,
            from: Data(#"{"success":true}"#.utf8)
        )
        #expect(success.success)
        #expect(success.error == nil)

        let refused = try APIClient.decode(
            DeleteAccountResponseDTO.self,
            from: Data(#"{"success":false,"error":"Current password is incorrect"}"#.utf8)
        )
        #expect(!refused.success)
        #expect(refused.error == Self.incorrectPassword)
    }
}
