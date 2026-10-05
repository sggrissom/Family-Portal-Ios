import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Milestone suggestions and matches")
struct MilestoneAnalysisTests {

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    // MARK: - Decoding

    @Test("An empty category decodes as no suggestion")
    func emptyCategoryIsNoSuggestion() throws {
        let response = try APIClient.decode(SuggestMilestoneCategoryResponseDTO.self, from: Data(#"{"category":""}"#.utf8))
        #expect(response.category.isEmpty)
        #expect(MilestoneCategory(rawValue: response.category) == nil)
    }

    @Test("Null lists decode as empty")
    func nullListsDecode() throws {
        let photos = try APIClient.decode(SuggestMilestonePhotosResponseDTO.self, from: Data(#"{"photoIds":null,"ranked":false}"#.utf8))
        #expect(photos.photoIds.isEmpty)
        let matches = try APIClient.decode(GetMilestoneMatchesResponseDTO.self, from: Data(#"{"ageMonths":14,"matches":null}"#.utf8))
        #expect(matches.ageMonths == 14)
        #expect(matches.matches.isEmpty)
    }

    @Test("A match decodes its person, milestone and age")
    func decodesMatch() throws {
        let json: [String: Any] = [
            "ageMonths": 13,
            "matches": [[
                "person": Fixture.person(id: 5, name: "Clara Grissom"),
                "milestone": Fixture.milestone(id: 41, personId: 5, description: "Took five steps"),
                "ageMonths": 14
            ]]
        ]
        let response = try APIClient.decode(GetMilestoneMatchesResponseDTO.self, from: JSONSerialization.data(withJSONObject: json))
        let match = try #require(response.matches.first)
        #expect(match.person.name == "Clara Grissom")
        #expect(match.milestone.id == 41)
        #expect(match.ageMonths == 14)
    }

    // MARK: - Service

    @Test("A category suggestion sends the trimmed text and the person")
    func categorySuggestionRequest() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SuggestMilestoneCategory", respond: .json(["category": "health"]))
        let service = AnalysisService(apiClient: server.apiClient())

        let category = await service.suggestMilestoneCategory(description: "  First tooth  ", personId: 12)

        #expect(category == .health)
        let body = try Self.body(of: try #require(server.requests(for: "rpc/SuggestMilestoneCategory").first))
        #expect(body["description"] as? String == "First tooth")
        #expect(body["personId"] as? Int == 12)
    }

    @Test("Text too short to compare is never sent")
    func shortTextIsNotSent() async {
        let server = FakeHTTPServer()
        let service = AnalysisService(apiClient: server.apiClient())

        #expect(await service.suggestMilestoneCategory(description: "hi", personId: nil) == nil)
        #expect(server.requests(for: "rpc/SuggestMilestoneCategory").isEmpty)
    }

    @Test("A failed photo suggestion is simply no suggestions")
    func failedPhotoSuggestionIsEmpty() async {
        let server = FakeHTTPServer()
        server.route("rpc/SuggestMilestonePhotos", respond: .status(500, message: "no daemon"))
        let service = AnalysisService(apiClient: server.apiClient())

        let ids = await service.suggestMilestonePhotos(personId: 12, description: "First steps", date: Date())
        #expect(ids.isEmpty)
    }

    @Test("Photo suggestions ask by date and pass the server's order through")
    func photoSuggestionRequest() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SuggestMilestonePhotos", respond: .json(["photoIds": [9, 3, 7], "ranked": true]))
        let service = AnalysisService(apiClient: server.apiClient())

        let ids = await service.suggestMilestonePhotos(personId: 12, description: "First steps", date: Date())

        #expect(ids == [9, 3, 7])
        let body = try Self.body(of: try #require(server.requests(for: "rpc/SuggestMilestonePhotos").first))
        #expect(body["inputType"] as? String == "date")
        #expect(body["milestoneDate"] as? String == dateToAPIString(Date().localRecordDay()))
        #expect(body["excludeIds"] as? [Int] == [])
    }

    @Test("Matches are fetched once per session, and not at all offline")
    func matchesAreCached() async {
        let server = FakeHTTPServer()
        server.route("rpc/GetMilestoneMatches", respond: .json(["ageMonths": 13, "matches": []]))
        let service = AnalysisService(apiClient: server.apiClient())

        #expect(await service.milestoneMatches(milestoneId: 40, isConnected: false) == nil)
        #expect(server.requests(for: "rpc/GetMilestoneMatches").isEmpty)

        _ = await service.milestoneMatches(milestoneId: 40, isConnected: true)
        _ = await service.milestoneMatches(milestoneId: 40, isConnected: false)
        #expect(server.requests(for: "rpc/GetMilestoneMatches").count == 1)
    }

    // MARK: - Resolution and wording

    @Test("Suggested ids resolve to local photos in the server's order, dropping unknown ones")
    func resolvesInServerOrder() {
        let photos = [3, 7, 9].map { id -> Photo in
            let photo = Photo(title: "", descriptionText: "", photoDate: Date())
            photo.remoteId = String(id)
            return photo
        }
        let resolved = RemotePhotoResolution.resolve([9, 42, 3], in: photos)
        #expect(resolved.map(\.remoteId) == ["9", "3"])
    }

    @Test("A match reads as a first name at an age")
    func matchWording() {
        #expect(Copy.milestoneDetail.match(name: "Clara Grissom", ageMonths: 14) == "Clara at 1 year 2 months")
        #expect(Copy.milestoneDetail.match(name: "Clara", ageMonths: 0) == "Clara at birth")
        #expect(Copy.milestoneDetail.match(name: "Clara", ageMonths: -1) == "Clara")
    }
}
