import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("SyncService pull")
struct SyncServicePullTests {

    private static func noPhotos() -> [String: Any] {
        Fixture.familyPhotos([])
    }

    // MARK: - Upsert

    @Test("A pull stores everything the server lists")
    func pullCreatesRecords() async throws {
        let harness = try TestSync.harness()
        harness.server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([
            Fixture.timelineItem(
                person: Fixture.person(id: 12, name: "Rowan"),
                growthData: [Fixture.growthData(id: 3, personId: 12, value: 104.5)],
                milestones: [Fixture.milestone(id: 4, personId: 12, description: "First steps")],
                photos: [Fixture.image(id: 5, title: "Beach")]
            )
        ])))
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Self.noPhotos()))

        await harness.service.pullFamilyData()

        let people = try harness.context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 1)
        #expect(people.first?.name == "Rowan")
        #expect(people.first?.remoteId == "12")

        let measurements = try harness.context.fetch(FetchDescriptor<GrowthData>())
        #expect(measurements.count == 1)
        #expect(measurements.first?.value == 104.5)
        #expect(measurements.first?.person?.remoteId == "12")

        let milestones = try harness.context.fetch(FetchDescriptor<Milestone>())
        #expect(milestones.count == 1)
        #expect(milestones.first?.person?.remoteId == "12")
        #expect(milestones.first?.descriptionText == "First steps")

        #expect(try harness.context.fetch(FetchDescriptor<Photo>()).count == 1)
        #expect(harness.service.syncError == nil)
        #expect(harness.service.lastSyncDate != nil)
    }

    @Test("A second pull updates the record it already has instead of adding another")
    func pullUpdatesInPlace() async throws {
        let harness = try TestSync.harness()
        harness.server.routeSequence("rpc/GetFamilyTimeline", [
            .json(Fixture.timeline([
                Fixture.timelineItem(
                    person: Fixture.person(id: 12, name: "Rowan"),
                    growthData: [Fixture.growthData(id: 3, personId: 12, value: 104.5)]
                )
            ])),
            .json(Fixture.timeline([
                Fixture.timelineItem(
                    person: Fixture.person(id: 12, name: "Rowan Ashby"),
                    growthData: [Fixture.growthData(id: 3, personId: 12, value: 106.0)]
                )
            ]))
        ])
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Self.noPhotos()))

        await harness.service.pullFamilyData()
        await harness.service.pullFamilyData()

        let people = try harness.context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 1)
        #expect(people.first?.name == "Rowan Ashby")

        let measurements = try harness.context.fetch(FetchDescriptor<GrowthData>())
        #expect(measurements.count == 1)
        #expect(measurements.first?.value == 106.0)
    }

    @Test("Tagged people from ListFamilyPhotos are attached to the photo")
    func pullAppliesPhotoTags() async throws {
        let harness = try TestSync.harness()
        harness.server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([
            Fixture.timelineItem(person: Fixture.person(id: 12, name: "Rowan"))
        ])))
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Fixture.familyPhotos([
            (image: Fixture.image(id: 5, title: "Beach"), people: [Fixture.person(id: 12, name: "Rowan")])
        ])))

        await harness.service.pullFamilyData()

        let photos = try harness.context.fetch(FetchDescriptor<Photo>())
        #expect(photos.count == 1)
        #expect(photos.first?.taggedPeople.count == 1)
        #expect(photos.first?.taggedPeople.first?.remoteId == "12")
        #expect(try harness.context.fetch(FetchDescriptor<Person>()).count == 1)
    }

    // MARK: - Orphan removal

    @Test("Records the server has stopped listing are deleted")
    func pullRemovesOrphans() async throws {
        let harness = try TestSync.harness()
        harness.server.routeSequence("rpc/GetFamilyTimeline", [
            .json(Fixture.timeline([
                Fixture.timelineItem(
                    person: Fixture.person(id: 12, name: "Rowan"),
                    growthData: [Fixture.growthData(id: 3, personId: 12)],
                    milestones: [Fixture.milestone(id: 4, personId: 12)],
                    photos: [Fixture.image(id: 5)]
                )
            ])),
            .json(Fixture.timeline([]))
        ])
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Self.noPhotos()))

        await harness.service.pullFamilyData()
        #expect(try harness.context.fetch(FetchDescriptor<Person>()).count == 1)

        await harness.service.pullFamilyData()

        #expect(try harness.context.fetch(FetchDescriptor<Person>()).isEmpty)
        #expect(try harness.context.fetch(FetchDescriptor<GrowthData>()).isEmpty)
        #expect(try harness.context.fetch(FetchDescriptor<Milestone>()).isEmpty)
        #expect(try harness.context.fetch(FetchDescriptor<Photo>()).isEmpty)
    }

    @Test("Work that has never been pushed survives a pull that lists nothing")
    func pullKeepsUnsyncedLocalWork() async throws {
        let harness = try TestSync.harness()
        harness.server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([])))
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Self.noPhotos()))

        let person = Person(name: "Added offline", gender: .other, birthday: Date())
        let photo = Photo(title: "Not uploaded yet", descriptionText: "", photoDate: Date(), imageData: Data([0xFF, 0xD8]))
        harness.context.insert(person)
        harness.context.insert(photo)
        try harness.context.save()

        await harness.service.pullFamilyData()

        #expect(try harness.context.fetch(FetchDescriptor<Person>()).count == 1)
        #expect(try harness.context.fetch(FetchDescriptor<Photo>()).count == 1)
    }

    @Test("An uploaded photo is removed even if its local bytes are still around")
    func pullRemovesUploadedPhotoWithLocalBytes() async throws {
        let harness = try TestSync.harness()
        harness.server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([])))
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Self.noPhotos()))

        let photo = Photo(title: "Deleted on the web", descriptionText: "", photoDate: Date(), imageData: Data([0xFF, 0xD8]))
        photo.remoteId = "99"
        harness.context.insert(photo)
        try harness.context.save()

        await harness.service.pullFamilyData()

        #expect(try harness.context.fetch(FetchDescriptor<Photo>()).isEmpty)
    }

    // MARK: - Failure

    @Test("A pull that fails says so and leaves the store alone")
    func pullReportsFailure() async throws {
        let harness = try TestSync.harness()
        harness.server.route("rpc/GetFamilyTimeline", respond: .status(500, message: "database is down"))
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Self.noPhotos()))

        let person = Person(name: "Added offline", gender: .other, birthday: Date())
        harness.context.insert(person)
        try harness.context.save()

        await harness.service.pullFamilyData()

        #expect(harness.service.syncError != nil)
        #expect(harness.service.lastSyncDate == nil)
        #expect(harness.service.isSyncing == false)
        // Nothing was deleted on the strength of a response that never arrived.
        #expect(try harness.context.fetch(FetchDescriptor<Person>()).count == 1)
    }

    @Test("A pull is skipped entirely while offline")
    func pullSkippedWhenOffline() async throws {
        let harness = try TestSync.harness(connected: false)
        harness.server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([])))

        await harness.service.pullFamilyData()

        #expect(harness.server.allRequests.isEmpty)
        #expect(harness.service.lastSyncDate == nil)
    }
}
