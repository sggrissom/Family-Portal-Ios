import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Tag suggestions")
struct TagSuggestionTests {

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    private static func group(count: Int) throws -> SuggestionGroupDTO {
        let suggestions: [[String: Any]] = (1...count).map { id in
            ["id": id, "photoId": 100 + id, "familyId": 7, "tagId": 0, "label": "Beach", "score": 0.5,
             "status": 0, "createdAt": "2026-09-01T00:00:00Z"]
        }
        let json: [String: Any] = ["key": "7/beach", "label": "Beach", "tagId": 0, "color": "#0ea5e9", "familyId": 7, "suggestions": suggestions]
        return try APIClient.decode(SuggestionGroupDTO.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - Decoding

    @Test("GetPhoto decodes place and suggestions, and a server without them")
    func getPhotoDecodes() throws {
        let full: [String: Any] = [
            "image": Fixture.image(id: 77, tagIds: [3]),
            "people": [],
            "place": ["key": "c12", "name": "Portland", "familyPlaceId": 0, "latitude": 45.5, "longitude": -122.6],
            "suggestions": [["id": 9, "label": "Beach", "color": "#0ea5e9"]]
        ]
        let response = try APIClient.decode(GetPhotoResponseDTO.self, from: JSONSerialization.data(withJSONObject: full))
        #expect(response.place?.name == "Portland")
        #expect(response.suggestions.map(\.id) == [9])

        let bare: [String: Any] = ["image": Fixture.image(id: 77), "people": NSNull()]
        let old = try APIClient.decode(GetPhotoResponseDTO.self, from: JSONSerialization.data(withJSONObject: bare))
        #expect(old.place == nil)
        #expect(old.suggestions.isEmpty)
        #expect(old.people.isEmpty)
    }

    @Test("A review with analysis off offers nothing")
    func disabledReview() throws {
        let response = try APIClient.decode(
            GetTagSuggestionsResponseDTO.self,
            from: Data(#"{"enabled":false,"groups":null,"total":0}"#.utf8)
        )
        #expect(response.groups.isEmpty)
        #expect(!response.hasSuggestions)
    }

    // MARK: - Review selection

    @Test("Only the shown photos are acted on, minus the ones left out")
    func includedIds() throws {
        let group = try Self.group(count: 30)
        let ids = TagSuggestionReview.includedIds(in: group, excluded: [2, 5], limit: 24)
        #expect(ids.count == 22)
        #expect(!ids.contains(2))
        #expect(!ids.contains(25))
    }

    // MARK: - Calls

    @Test("Accept and reject send suggestion ids")
    func acceptSendsIds() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/AcceptTagSuggestions", respond: .json(["updated": 2]))
        server.route("rpc/RejectTagSuggestions", respond: .json(["updated": 1]))
        let service = AnalysisService(apiClient: server.apiClient())

        #expect(try await service.acceptTagSuggestions([9, 10]) == 2)
        #expect(try await service.rejectTagSuggestions([11]) == 1)

        let accept = try Self.body(of: try #require(server.requests(for: "rpc/AcceptTagSuggestions").first))
        #expect(accept["ids"] as? [Int] == [9, 10])
    }

    @Test("A failed accept throws, so the user hears about it")
    func failedAcceptThrows() async {
        let server = FakeHTTPServer()
        server.route("rpc/AcceptTagSuggestions", respond: .status(400, message: "Suggestion not found"))
        let service = AnalysisService(apiClient: server.apiClient())

        await #expect(throws: (any Error).self) {
            try await service.acceptTagSuggestions([9])
        }
    }

    // MARK: - Adopting the server's tags

    @Test("An accepted tag replaces the photo's tags and re-pulls the vocabulary")
    func adoptReplacesTags() async throws {
        let harness = try TestSync.harness(connected: false)
        harness.server.route("rpc/ListTags", respond: .json(Fixture.tags([Fixture.tag(id: 3, name: "Holiday"), Fixture.tag(id: 8, name: "Beach")])))
        let photo = Photo(title: "", descriptionText: "", photoDate: Date())
        photo.remoteId = "77"
        photo.tagRemoteIds = [3]
        harness.context.insert(photo)
        try harness.context.save()

        await harness.service.adoptServerTags(before: [3], after: [3, 8], for: photo)

        #expect(photo.tagRemoteIds == [3, 8])
        let tags = try harness.context.fetch(FetchDescriptor<FamilyTag>())
        #expect(Set(tags.compactMap(\.remoteId)) == ["3", "8"])
    }

    @Test("A queued tag edit keeps its own changes and gains the accepted tag")
    func adoptMergesIntoPendingWrite() async throws {
        let harness = try TestSync.harness(connected: false)
        harness.server.route("rpc/ListTags", respond: .json(Fixture.tags([])))
        let photo = Photo(title: "", descriptionText: "", photoDate: Date())
        photo.remoteId = "77"
        photo.tagRemoteIds = [3, 4]
        harness.context.insert(photo)
        try harness.context.save()

        // Offline, the user untagged 4; the server still has it.
        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [3])
        await harness.service.adoptServerTags(before: [3, 4], after: [3, 4, 8], for: photo)

        #expect(photo.tagRemoteIds == [3, 8])
        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        let payload = try JSONDecoder().decode(UpdateTagsPayload.self, from: try #require(operations.first).payload)
        #expect(payload.tagRemoteIds == [3, 8])
    }
}
