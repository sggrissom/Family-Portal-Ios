import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Photo search")
struct PhotoSearchTests {

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    private static func page(_ ids: [Int], next: String, matched: [Int] = [], mode: String = "semantic") -> [String: Any] {
        [
            "photos": ids.map { ["image": Fixture.image(id: $0), "people": []] },
            "nextCursor": next,
            "matchedPersonIds": matched,
            "searchMode": mode
        ]
    }

    @Test("The sync pull's answer, which has none of the search keys, still decodes")
    func plainListingDecodes() throws {
        let json: [String: Any] = ["photos": [["image": Fixture.image(id: 1), "people": []]]]
        let response = try APIClient.decode(ListFamilyPhotosResponseDTO.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(response.photos.count == 1)
        #expect(response.nextCursor.isEmpty)
        #expect(response.matchedPersonIds.isEmpty)
        #expect(response.searchMode.isEmpty)
    }

    @Test("Pages append in the server's order without repeats")
    func pagesAppend() throws {
        var results = PhotoSearchResults(query: "beach", request: PhotoSearchRequest(filter: PhotoFilter(), people: []))
        results.append(try APIClient.decode(ListFamilyPhotosResponseDTO.self, from: JSONSerialization.data(withJSONObject: Self.page([9, 3], next: "s60", matched: [5]))))
        #expect(results.hasMore)
        results.append(try APIClient.decode(ListFamilyPhotosResponseDTO.self, from: JSONSerialization.data(withJSONObject: Self.page([3, 7], next: "", matched: []))))

        #expect(results.photoIds == [9, 3, 7])
        #expect(results.matchedPersonIds == [5])
        #expect(!results.hasMore)
        #expect(!results.isTextOnly)
    }

    @Test("Text mode is noticed")
    func textMode() throws {
        var results = PhotoSearchResults(query: "beach", request: PhotoSearchRequest(filter: PhotoFilter(), people: []))
        results.append(try APIClient.decode(ListFamilyPhotosResponseDTO.self, from: JSONSerialization.data(withJSONObject: Self.page([1], next: "", mode: "text"))))
        #expect(results.isTextOnly)
    }

    @Test("Panel filters go to the server by server id, leaving out people still uploading")
    func requestFromFilter() {
        let synced = Person(name: "Clara", gender: .female)
        synced.remoteId = "5"
        let unsynced = Person(name: "New", gender: .other)
        var filter = PhotoFilter()
        filter.personLocalIds = [synced.id, unsynced.id]
        filter.tagRemoteIds = [8, 3]

        let request = PhotoSearchRequest(filter: filter, people: [synced, unsynced])
        #expect(request.personIds == [5])
        #expect(request.tagIds == [3, 8])

        let dto = PhotoSearchRequest(filter: PhotoFilter(), people: []).dto(query: "beach", cursor: nil)
        #expect(dto.personIds == nil)
        #expect(dto.tagIds == nil)
        #expect(dto.limit == PhotoSearchResults.pageSize)
    }

    @Test("A search sends the query, the page size, and the cursor when paging")
    func searchRequest() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/ListFamilyPhotos", respond: .json(Self.page([1], next: "")))
        let service = AnalysisService(apiClient: server.apiClient())
        let request = PhotoSearchRequest(filter: PhotoFilter(), people: [])

        _ = try await service.searchPhotos(query: "beach day", request: request)
        _ = try await service.searchPhotos(query: "beach day", request: request, cursor: "s60")

        let bodies = try server.requests(for: "rpc/ListFamilyPhotos").map(Self.body(of:))
        #expect(bodies.count == 2)
        #expect(bodies[0]["query"] as? String == "beach day")
        #expect(bodies[0]["limit"] as? Int == 60)
        #expect(bodies[0]["cursor"] == nil)
        #expect(bodies[0]["personIds"] == nil)
        #expect(bodies[1]["cursor"] as? String == "s60")
    }

    @Test("Best-matches wording names the people the query matched")
    func wording() {
        #expect(Copy.photoSearch.bestMatches("beach", with: "") == "Best matches for \u{201C}beach\u{201D}")
        #expect(Copy.photoSearch.bestMatches("beach", with: "Clara and Mia") == "Best matches for \u{201C}beach\u{201D} with Clara and Mia")
    }
}
