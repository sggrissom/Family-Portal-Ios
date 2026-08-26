import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@Suite("Tags")
struct TagDecodingTests {

    // MARK: - TagDTO

    @Test("Decodes a Tag as backend/tags.go marshals one")
    func decodesTag() throws {
        let json = try JSONSerialization.data(
            withJSONObject: Fixture.tag(id: 3, name: "Holiday", color: "#4A90D9", familyId: 7)
        )
        let dto = try APIClient.decode(TagDTO.self, from: json)

        #expect(dto.id == 3)
        #expect(dto.name == "Holiday")
        #expect(dto.color == "#4A90D9")
        #expect(dto.familyId == 7)
    }

    @Test("A Tag decodes without createdAt")
    func decodesTagWithoutCreatedAt() throws {
        let json = """
        { "id": 3, "familyId": 7, "name": "Holiday", "color": "#4A90D9" }
        """
        let dto = try APIClient.decode(TagDTO.self, from: Data(json.utf8))
        #expect(dto.name == "Holiday")
    }

    @Test("A Tag with no colour decodes rather than failing")
    func decodesTagWithoutColor() throws {
        let json = """
        { "id": 3, "familyId": 7, "name": "Holiday", "createdAt": "2025-11-02T09:00:00Z" }
        """
        let dto = try APIClient.decode(TagDTO.self, from: Data(json.utf8))
        #expect(dto.color == "")
    }

    @Test("A null tag list decodes as empty, the way a nil Go slice marshals")
    func decodesNullTagList() throws {
        let dto = try APIClient.decode(ListTagsResponseDTO.self, from: Data(#"{"tags": null}"#.utf8))
        #expect(dto.tags.isEmpty)
    }

    // MARK: - tagIds on records

    @Test("A milestone with no tags omits tagIds entirely")
    func milestoneWithoutTagIds() throws {
        let json = try JSONSerialization.data(withJSONObject: Fixture.milestone(id: 77, personId: 12))
        let dto = try APIClient.decode(MilestoneDTO.self, from: json)
        #expect(dto.tagIds.isEmpty)
    }

    @Test("A milestone's tagIds decode in the order the server sent them")
    func milestoneWithTagIds() throws {
        let json = try JSONSerialization.data(
            withJSONObject: Fixture.milestone(id: 77, personId: 12, tagIds: [9, 3])
        )
        let dto = try APIClient.decode(MilestoneDTO.self, from: json)
        #expect(dto.tagIds == [9, 3])
    }

    @Test("A photo with no tags omits tagIds entirely")
    func imageWithoutTagIds() throws {
        let json = try JSONSerialization.data(withJSONObject: Fixture.image(id: 5))
        let dto = try APIClient.decode(ImageDTO.self, from: json)
        #expect(dto.tagIds.isEmpty)
    }

    @Test("A photo's tagIds decode")
    func imageWithTagIds() throws {
        let json = try JSONSerialization.data(withJSONObject: Fixture.image(id: 5, tagIds: [3]))
        let dto = try APIClient.decode(ImageDTO.self, from: json)
        #expect(dto.tagIds == [3])
    }

    // MARK: - Mapping

    @Test("Applying a DTO copies the tag ids onto the record")
    func mappersCarryTagIds() throws {
        let milestoneJSON = try JSONSerialization.data(
            withJSONObject: Fixture.milestone(id: 77, personId: 12, tagIds: [9, 3])
        )
        let milestone = milestoneFromDTO(try APIClient.decode(MilestoneDTO.self, from: milestoneJSON))
        #expect(milestone.tagRemoteIds == [9, 3])

        let imageJSON = try JSONSerialization.data(withJSONObject: Fixture.image(id: 5, tagIds: [3]))
        let photo = photoFromDTO(try APIClient.decode(ImageDTO.self, from: imageJSON))
        #expect(photo.tagRemoteIds == [3])
    }
}

@Suite("Tag colours")
struct TagColorTests {

    @Test("A six-digit hex parses to its channels")
    func parsesSixDigitHex() throws {
        let components = try #require(TagColor.components(forHex: "#4A90D9"))
        #expect(abs(components.red - 74.0 / 255) < 0.001)
        #expect(abs(components.green - 144.0 / 255) < 0.001)
        #expect(abs(components.blue - 217.0 / 255) < 0.001)
    }

    @Test("The leading # is optional and case doesn't matter")
    func parsesWithoutHashAndInAnyCase() throws {
        let withHash = try #require(TagColor.components(forHex: "#ff8000"))
        let bare = try #require(TagColor.components(forHex: "FF8000"))
        #expect(withHash.red == bare.red)
        #expect(withHash.green == bare.green)
        #expect(withHash.blue == bare.blue)
        #expect(withHash.red == 1)
    }

    @Test("A three-digit shorthand expands by doubling each digit")
    func parsesShorthand() throws {
        let short = try #require(TagColor.components(forHex: "#4a9"))
        let long = try #require(TagColor.components(forHex: "#44aa99"))
        #expect(short.red == long.red)
        #expect(short.green == long.green)
        #expect(short.blue == long.blue)
    }

    @Test("Surrounding whitespace is tolerated")
    func parsesPaddedHex() throws {
        let padded = try #require(TagColor.components(forHex: "  #4A90D9 "))
        let bare = try #require(TagColor.components(forHex: "#4A90D9"))
        #expect(padded.red == bare.red)
        #expect(padded.green == bare.green)
        #expect(padded.blue == bare.blue)
    }

    @Test("Anything that isn't a hex colour is a miss, not a wrong colour")
    func rejectsMalformedValues() {
        #expect(TagColor.components(forHex: "") == nil)
        #expect(TagColor.components(forHex: "#") == nil)
        #expect(TagColor.components(forHex: "blue") == nil)
        #expect(TagColor.components(forHex: "rgb(74, 144, 217)") == nil)
        #expect(TagColor.components(forHex: "#12345") == nil)
        #expect(TagColor.components(forHex: "#4A90D9FF") == nil)
        #expect(TagColor.components(forHex: "#GGGGGG") == nil)
    }
}

@MainActor
@Suite("Tag sync")
struct TagSyncTests {

    private static func emptyTimeline(_ server: FakeHTTPServer) {
        server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([])))
        server.route("rpc/ListFamilyPhotos", respond: .json(Fixture.familyPhotos([])))
    }

    private static func sortedTagNames(_ context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<FamilyTag>()).map(\.name).sorted()
    }

    @Test("A pull stores the family's tags")
    func pullStoresTags() async throws {
        let harness = try TestSync.harness()
        Self.emptyTimeline(harness.server)
        harness.server.route("rpc/ListTags", respond: .json(Fixture.tags([
            Fixture.tag(id: 3, name: "Holiday", color: "#4A90D9"),
            Fixture.tag(id: 9, name: "School", color: "#E8B04B")
        ])))

        await harness.service.pullFamilyData()

        let tags = try harness.context.fetch(FetchDescriptor<FamilyTag>()).sorted { $0.name < $1.name }
        #expect(tags.count == 2)
        #expect(tags.first?.name == "Holiday")
        #expect(tags.first?.remoteId == "3")
        #expect(tags.first?.colorHex == "#4A90D9")
        #expect(tags.last?.name == "School")

        let requests = harness.server.requests(for: "rpc/ListTags")
        #expect(requests.count == 1)
        #expect(String(data: requests.first?.body ?? Data(), encoding: .utf8) == "{}")
    }

    @Test("A renamed or recoloured tag is updated in place")
    func pullUpdatesTagInPlace() async throws {
        let harness = try TestSync.harness()
        Self.emptyTimeline(harness.server)
        harness.server.routeSequence("rpc/ListTags", [
            .json(Fixture.tags([Fixture.tag(id: 3, name: "Holiday", color: "#4A90D9")])),
            .json(Fixture.tags([Fixture.tag(id: 3, name: "Holidays", color: "#E8B04B")]))
        ])

        await harness.service.pullFamilyData()
        await harness.service.pullFamilyData()

        let tags = try harness.context.fetch(FetchDescriptor<FamilyTag>())
        #expect(tags.count == 1)
        #expect(tags.first?.name == "Holidays")
        #expect(tags.first?.colorHex == "#E8B04B")
    }

    @Test("A tag deleted on the web is deleted here")
    func pullRemovesDeletedTags() async throws {
        let harness = try TestSync.harness()
        Self.emptyTimeline(harness.server)
        harness.server.routeSequence("rpc/ListTags", [
            .json(Fixture.tags([Fixture.tag(id: 3, name: "Holiday"), Fixture.tag(id: 9, name: "School")])),
            .json(Fixture.tags([Fixture.tag(id: 3, name: "Holiday")]))
        ])

        await harness.service.pullFamilyData()
        #expect(try Self.sortedTagNames(harness.context) == ["Holiday", "School"])

        await harness.service.pullFamilyData()
        #expect(try Self.sortedTagNames(harness.context) == ["Holiday"])
    }

    @Test("Tag ids on photos and milestones are stored alongside the records")
    func pullStoresTagIdsOnRecords() async throws {
        let harness = try TestSync.harness()
        harness.server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([
            Fixture.timelineItem(
                person: Fixture.person(id: 12),
                milestones: [Fixture.milestone(id: 4, personId: 12, tagIds: [9, 3])],
                photos: [Fixture.image(id: 5, tagIds: [3])]
            )
        ])))
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Fixture.familyPhotos([])))
        harness.server.route("rpc/ListTags", respond: .json(Fixture.tags([
            Fixture.tag(id: 3, name: "Holiday"),
            Fixture.tag(id: 9, name: "School")
        ])))

        await harness.service.pullFamilyData()

        let milestones = try harness.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.first?.tagRemoteIds == [9, 3])

        let photos = try harness.context.fetch(FetchDescriptor<Photo>())
        #expect(photos.first?.tagRemoteIds == [3])
    }

    @Test("A failing tag list doesn't fail the pull")
    func pullSurvivesTagFailure() async throws {
        let harness = try TestSync.harness()
        harness.server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([
            Fixture.timelineItem(person: Fixture.person(id: 12, name: "Rowan"))
        ])))
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Fixture.familyPhotos([])))
        harness.server.route("rpc/ListTags", respond: .status(500, message: "tags are down"))

        await harness.service.pullFamilyData()

        #expect(try harness.context.fetch(FetchDescriptor<Person>()).count == 1)
        #expect(harness.service.syncError == nil)
        #expect(harness.service.lastSyncDate != nil)
    }

    @Test("A failing tag list leaves the tags already stored alone")
    func pullKeepsTagsWhenListFails() async throws {
        let harness = try TestSync.harness()
        Self.emptyTimeline(harness.server)
        harness.server.routeSequence("rpc/ListTags", [
            .json(Fixture.tags([Fixture.tag(id: 3, name: "Holiday")])),
            .status(500, message: "tags are down")
        ])

        await harness.service.pullFamilyData()
        await harness.service.pullFamilyData()

        #expect(try Self.sortedTagNames(harness.context) == ["Holiday"])
    }
}
