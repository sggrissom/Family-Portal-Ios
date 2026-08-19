import Foundation
import Testing
@testable import Family_Portal_Ios

/// Activities is the first iOS feature whose backend answers with error strings
/// meant for a user rather than for a log.
///
/// `vbeam.RespondError` writes `w.WriteHeader(400)` then
/// `fmt.Fprintf(w, err.Error())` — no JSON, no `success: false` — so the body of
/// a 400 *is* the sentence to show. Rendering it as `Server error (400): …`
/// buries the only useful part of the alert behind a status code the reader can
/// do nothing with.
@Suite("Activity proc errors")
struct ActivityErrorTests {

    /// The exact sentence `CreateAppearance` answers with when the entry and the
    /// event disagree about their season (`ErrEntryNotInSeason`).
    private static let entryNotInSeason = "That entry is not in the same season as this competition"

    @Test("A proc's 400 body is presented as written")
    func procSentenceIsPresentedVerbatim() {
        let error = APIError.server(statusCode: 400, message: Self.entryNotInSeason)

        #expect(error.localizedDescription == Self.entryNotInSeason)
        #expect(error.localizedDescription.contains("400") == false)
    }

    @Test("Every activities refusal reaches the user as its own sentence")
    func everyRefusalSurvives() {
        // Read off backend/activity_procs.go, activity_results.go and
        // activity_photos.go.
        let refusals = [
            "A name is required",
            "That entry is not in the same season as this competition",
            "A placement needs a rank",
            "A rank must be 1 or greater, and no greater than the field size",
            "A result can only name someone on this entry's roster",
            "That is more results than one performance can hold",
            "Dates must be in YYYY-MM-DD format"
        ]

        for refusal in refusals {
            #expect(APIError.server(statusCode: 400, message: refusal).localizedDescription == refusal)
        }
    }

    @Test("Whitespace around the body is trimmed")
    func bodyIsTrimmed() {
        let error = APIError.server(statusCode: 400, message: "\n\(Self.entryNotInSeason)\n")
        #expect(error.localizedDescription == Self.entryNotInSeason)
    }

    // MARK: - What the unwrap must not swallow

    /// A 400 can also carry an HTML error page from something sitting in front
    /// of the app, or a JSON envelope from a handler that is not a proc. Neither
    /// is a sentence, and showing one verbatim is worse than the generic
    /// wording.
    @Test("A body that is not a sentence falls back to the generic wording")
    func nonSentenceBodiesFallBack() {
        let html = APIError.server(statusCode: 400, message: "<html><body>Bad Request</body></html>")
        let json = APIError.server(statusCode: 400, message: "{\"error\":\"bad request\"}")
        let list = APIError.server(statusCode: 400, message: "[\"bad request\"]")
        let multiline = APIError.server(statusCode: 400, message: "Bad Request\nsomething else")
        let novel = APIError.server(statusCode: 400, message: String(repeating: "a", count: 201))

        for error in [html, json, list, multiline, novel] {
            #expect(error.localizedDescription.hasPrefix("Server error (400)"))
        }
    }

    @Test("An empty body still says something")
    func emptyBodyFallsBack() {
        #expect(APIError.server(statusCode: 400, message: "").localizedDescription == "Server error (400).")
        #expect(APIError.server(statusCode: 400, message: nil).localizedDescription == "Server error (400).")
        #expect(APIError.server(statusCode: 400, message: "   ").localizedDescription.hasPrefix("Server error (400)"))
    }

    /// Only a 400 is a proc refusal. A 500's body is a Go panic or a proxy's
    /// page, and neither belongs in an alert.
    @Test("Other statuses keep the generic wording")
    func onlyBadRequestUnwraps() {
        #expect(APIError.server(statusCode: 500, message: "boom").localizedDescription.hasPrefix("Server error (500)"))
        #expect(APIError.server(statusCode: 404, message: "not found").localizedDescription.hasPrefix("Server error (404)"))
    }

    // MARK: - End to end

    /// A proc-level auth failure is also a 400 rather than a 401, so it does not
    /// trip `retryOnAuthFailure` — `ensureFreshAccessToken` is what keeps that
    /// from mattering. What matters here is that the body survives the whole
    /// path from `URLSession` to `localizedDescription`.
    @Test("A refused proc call carries its sentence out of APIClient")
    func refusalSurvivesTheClient() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/CreateAppearance", respond: .status(400, message: Self.entryNotInSeason))
        let client = server.apiClient()

        do {
            let _: AppearanceStub = try await client.callRPC(
                .createAppearance,
                payload: ["eventId": 5, "entryId": 11]
            )
            Issue.record("Expected the call to be refused")
        } catch {
            #expect(error.localizedDescription == Self.entryNotInSeason)
        }
    }

    /// Phase 1 ships no writes, so there is no response type for
    /// `CreateAppearance` yet — this only has to be something `callRPC` can be
    /// asked to decode into.
    private struct AppearanceStub: Decodable {}
}
