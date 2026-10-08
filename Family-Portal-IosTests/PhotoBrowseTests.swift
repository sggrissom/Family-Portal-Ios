import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// Payloads shaped on `ListFamilyPhotos` (backend/photos.go, photo_index.go) and `ListPhotoPlaces` (backend/places.go).
@MainActor
@Suite("Photo browsing")
struct PhotoBrowseTests {

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    /// A listing page; `similar` maps a cover to the rest of its group.
    private static func page(_ ids: [Int], similar: [Int: [Int]] = [:], next: String = "") -> [String: Any] {
        [
            "photos": ids.map { id -> [String: Any] in
                var item: [String: Any] = ["image": Fixture.image(id: id), "people": []]
                if let others = similar[id] { item["similar"] = others }
                return item
            },
            "nextCursor": next,
        ]
    }

    private static func groups(_ similar: [Int: [Int]]) throws -> SimilarGroups {
        let response = try APIClient.decode(ListFamilyPhotosResponseDTO.self, from: Fixture.data(page(Array(similar.keys), similar: similar)))
        var groups = SimilarGroups()
        groups.add(response.photos)
        return groups
    }

    // MARK: - Grouping

    @Test("A group shows once, as its cover, badged with the rest of the group")
    func collapsesToCover() throws {
        let groups = try Self.groups([10: [11, 12]])
        let cells = groups.collapse([12, 10, 11, 5]) { $0 }
        #expect(cells.map(\.item) == [10, 5])
        #expect(cells[0].groupCover == 10)
        #expect(cells[0].similarCount == 2)
        #expect(cells[1].groupCover == nil)
        #expect(groups.members(ofCover: 10) == [10, 11, 12])
    }

    @Test("A filter that hides the cover still finds the group, through its first member shown")
    func coverFilteredOut() throws {
        let groups = try Self.groups([10: [11, 12]])
        let cells = groups.collapse([12, 11, 5]) { $0 }
        #expect(cells.map(\.item) == [12, 5])
        #expect(cells[0].groupCover == 10)
        #expect(cells[0].similarCount == 2)
    }

    @Test("A photo not uploaded yet is in no group")
    func pendingUploadUngrouped() throws {
        let groups = try Self.groups([10: [11]])
        let cells = groups.collapse([Int?.none, 10, 11]) { $0 }
        #expect(cells.count == 2)
        #expect(cells[0].groupCover == nil)
    }

    @Test("Items without similar photos make no groups")
    func noSimilar() throws {
        let response = try APIClient.decode(ListFamilyPhotosResponseDTO.self, from: Fixture.data(Self.page([1, 2])))
        var groups = SimilarGroups()
        groups.add(response.photos)
        #expect(groups.isEmpty)
    }

    // MARK: - Places in the filter

    private func photo(_ remoteId: String?, in context: ModelContext) -> Photo {
        let photo = Photo(title: "", descriptionText: "", photoDate: Date(), imageData: nil)
        photo.remoteId = remoteId
        context.insert(photo)
        return photo
    }

    @Test("A place keeps only the photos the server says are there")
    func placeFilters() throws {
        let context = try TestStore.makeContext()
        let photos = [photo("1", in: context), photo("2", in: context), photo(nil, in: context)]
        var filter = PhotoFilter()
        filter.placeKey = "f3"
        filter.placeName = "Grandma's"

        #expect(filter.apply(to: photos, placePhotoIds: [2]).map(\.remoteId) == ["2"])
        // No answer yet: the device can't tell where anything was taken.
        #expect(filter.apply(to: photos).isEmpty)
        #expect(filter.hasPanelFilters)
        #expect(filter.summary { _ in nil } == "Grandma's")
    }

    @Test("Clearing filters clears the place but keeps how similar photos are shown")
    func clearKeepsSimilarChoice() {
        var filter = PhotoFilter()
        filter.placeKey = "c9"
        filter.showsSimilarSeparately = true
        filter.clearPanelFilters()
        #expect(filter.placeKey == nil)
        #expect(filter.showsSimilarSeparately)
        #expect(!filter.hasPanelFilters)
    }

    @Test("A place travels with search and with the place listing, which is never collapsed")
    func placeRequests() throws {
        var filter = PhotoFilter()
        filter.placeKey = "c9"
        let request = PhotoSearchRequest(filter: filter, people: [])
        #expect(request.dto(query: "beach", cursor: nil).placeKey == "c9")
        let listing = request.listingDTO()
        #expect(listing.placeKey == "c9")
        #expect(listing.collapseSimilar == nil)
        #expect(listing.query == nil)
    }

    @Test("Places decode with their counts")
    func placesDecode() throws {
        let response = try APIClient.decode(ListPhotoPlacesResponseDTO.self, from: Fixture.data([
            "places": [["key": "f3", "name": "Grandma's", "count": 12], ["key": "c9", "name": "Austin, TX", "count": 40]],
        ]))
        #expect(response.places.map(\.key) == ["f3", "c9"])
        #expect(response.places[0].isFamilyPlace)
        #expect(!response.places[1].isFamilyPlace)
    }

    // MARK: - Service

    @Test("Groups are read across every page of a collapsed listing")
    func loadsGroupsAcrossPages() async throws {
        let server = FakeHTTPServer()
        server.routeSequence("rpc/ListFamilyPhotos", [
            .json(Self.page([10, 5], similar: [10: [11]], next: "c1")),
            .json(Self.page([20], similar: [20: [21, 22]])),
        ])
        let service = PhotoBrowseService(apiClient: server.apiClient())

        await service.loadGroups(isConnected: true)

        let requests = server.requests(for: "rpc/ListFamilyPhotos")
        #expect(requests.count == 2)
        let first = try Self.body(of: requests[0])
        #expect(first["collapseSimilar"] as? Bool == true)
        #expect(first["limit"] as? Int == PhotoBrowseService.pageSize)
        #expect(try Self.body(of: requests[1])["cursor"] as? String == "c1")
        #expect(service.groups?.members(ofCover: 20) == [20, 21, 22])
        #expect(service.groups?.coverOf[11] == 10)
    }

    @Test("Offline, groups are not asked for and photos show ungrouped")
    func groupsOffline() async {
        let server = FakeHTTPServer()
        let service = PhotoBrowseService(apiClient: server.apiClient())
        await service.loadGroups(isConnected: false)
        #expect(service.groups == nil)
        #expect(server.allRequests.isEmpty)
    }

    @Test("A place's photos are fetched once per question, in the server's order")
    func placePhotosCached() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/ListFamilyPhotos", respond: .json(Self.page([9, 4])))
        let service = PhotoBrowseService(apiClient: server.apiClient())
        var filter = PhotoFilter()
        filter.placeKey = "f3"
        let request = PhotoSearchRequest(filter: filter, people: [])

        #expect(try await service.loadPlacePhotos(request) == [9, 4])
        #expect(try await service.loadPlacePhotos(request) == [9, 4])
        #expect(service.cachedPlacePhotos(request) == [9, 4])
        #expect(server.requests(for: "rpc/ListFamilyPhotos").count == 1)
        #expect(try Self.body(of: server.requests(for: "rpc/ListFamilyPhotos")[0])["placeKey"] as? String == "f3")
    }
}
