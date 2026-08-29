import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Activity proc errors")
struct ActivityErrorTests {

    private static let entryNotInSeason = "That entry is not in the same season as this competition"

    @Test("A proc's 400 body is presented as written")
    func procSentenceIsPresentedVerbatim() {
        let error = APIError.server(statusCode: 400, message: Self.entryNotInSeason)

        #expect(error.localizedDescription == Self.entryNotInSeason)
        #expect(error.localizedDescription.contains("400") == false)
    }

    @Test("Every activities refusal reaches the user as its own sentence")
    func everyRefusalSurvives() {
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

    @Test("Other statuses keep the generic wording")
    func onlyBadRequestUnwraps() {
        #expect(APIError.server(statusCode: 500, message: "boom").localizedDescription.hasPrefix("Server error (500)"))
        #expect(APIError.server(statusCode: 404, message: "not found").localizedDescription.hasPrefix("Server error (404)"))
    }

    // MARK: - End to end

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

    private struct AppearanceStub: Decodable {}
}
