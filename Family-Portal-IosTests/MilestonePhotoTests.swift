import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Milestone photos")
struct MilestonePhotoTests {

    private struct Scene {
        let person: Person
        let milestone: Milestone
        let photos: [Photo]
    }

    private static func scene(
        in harness: TestSync.Harness,
        photoRemoteIds: [String?] = ["77", "78"],
        milestoneRemoteId: String? = nil
    ) throws -> Scene {
        let person = Person(name: "Rowan", type: .child, gender: .other, birthday: Date())
        person.remoteId = "12"
        harness.context.insert(person)

        let photos = photoRemoteIds.enumerated().map { index, remoteId -> Photo in
            let photo = Photo(
                title: "Photo \(index)",
                descriptionText: "",
                photoDate: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 - index * 86_400)),
                imageData: nil
            )
            photo.remoteId = remoteId
            photo.taggedPeople = [person]
            harness.context.insert(photo)
            return photo
        }

        let milestone = Milestone(descriptionText: "First steps", category: .development, date: Date())
        milestone.person = person
        milestone.remoteId = milestoneRemoteId
        harness.context.insert(milestone)

        try harness.context.save()
        return Scene(person: person, milestone: milestone, photos: photos)
    }

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    private static func routeAdd(_ harness: TestSync.Harness, photoIds: [Int]) {
        harness.server.route("rpc/AddMilestone", respond: .json([
            "milestone": Fixture.milestone(id: 40, personId: 12, photoIds: photoIds)
        ]))
    }

    private static func routeUpdate(_ harness: TestSync.Harness, photoIds: [Int]) {
        harness.server.route("rpc/UpdateMilestone", respond: .json([
            "milestone": Fixture.milestone(id: 40, personId: 12, photoIds: photoIds)
        ]))
    }

    // MARK: - Create

    @Test("Creating a milestone sends the photos it was given")
    func createSendsPhotoIds() async throws {
        let harness = try TestSync.harness(connected: false)
        let scene = try Self.scene(in: harness)
        Self.routeAdd(harness, photoIds: [77, 78])

        try await harness.service.addMilestone(scene.milestone, for: scene.person, photos: scene.photos)

        // The badge on the row has to appear at save, not at the next pull.
        #expect(scene.milestone.photoRemoteIds == [77, 78])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddMilestone").first))
        #expect(body["photoIds"] as? [Int] == [77, 78])
        #expect(await harness.service.syncQueue.count() == 0)
    }

    @Test("Creating a milestone without photos omits the field entirely")
    func createWithoutPhotosOmitsTheField() async throws {
        let harness = try TestSync.harness(connected: false)
        let scene = try Self.scene(in: harness)
        Self.routeAdd(harness, photoIds: [])

        try await harness.service.addMilestone(scene.milestone, for: scene.person)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddMilestone").first))
        #expect(body["photoIds"] == nil)
    }

    @Test("The server's photo list replaces the optimistic one")
    func responsePhotoIdsAreApplied() async throws {
        let harness = try TestSync.harness(connected: false)
        let scene = try Self.scene(in: harness)
        Self.routeAdd(harness, photoIds: [77])

        try await harness.service.addMilestone(scene.milestone, for: scene.person, photos: scene.photos)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(scene.milestone.remoteId == "40")
        #expect(scene.milestone.photoRemoteIds == [77])
    }

    // MARK: - Update

    @Test("Clearing the selection sends an empty list, not an absent one")
    func updateWithNoPhotosSendsAnEmptyList() async throws {
        let harness = try TestSync.harness(connected: false)
        let scene = try Self.scene(in: harness, milestoneRemoteId: "40")
        scene.milestone.photoRemoteIds = [77, 78]
        try harness.context.save()
        Self.routeUpdate(harness, photoIds: [])

        try await harness.service.updateMilestone(scene.milestone, photos: [])

        #expect(scene.milestone.photoRemoteIds.isEmpty)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdateMilestone").first))
        let photoIds = try #require(body["photoIds"] as? [Int])
        #expect(photoIds.isEmpty)
    }

    @Test("An edit that says nothing about photos leaves them attached")
    func updateWithoutPhotosOmitsTheField() async throws {
        let harness = try TestSync.harness(connected: false)
        let scene = try Self.scene(in: harness, milestoneRemoteId: "40")
        scene.milestone.photoRemoteIds = [77, 78]
        try harness.context.save()
        Self.routeUpdate(harness, photoIds: [77, 78])

        try await harness.service.updateMilestone(scene.milestone)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdateMilestone").first))
        #expect(body["photoIds"] == nil)
        #expect(scene.milestone.photoRemoteIds == [77, 78])
    }

    @Test("Changing the selection sends the new set")
    func updateSendsTheNewSelection() async throws {
        let harness = try TestSync.harness(connected: false)
        let scene = try Self.scene(in: harness, milestoneRemoteId: "40")
        scene.milestone.photoRemoteIds = [77, 78]
        try harness.context.save()
        Self.routeUpdate(harness, photoIds: [78])

        try await harness.service.updateMilestone(scene.milestone, photos: [scene.photos[1]])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdateMilestone").first))
        #expect(body["photoIds"] as? [Int] == [78])
    }

    // MARK: - Photos that aren't ready

    @Test("A photo still uploading parks the milestone instead of dropping it")
    func unsyncedPhotoBlocksTheOperation() async throws {
        let harness = try TestSync.harness(connected: false)
        let scene = try Self.scene(in: harness, photoRemoteIds: ["77", nil])
        Self.routeAdd(harness, photoIds: [77])

        try await harness.service.addMilestone(scene.milestone, for: scene.person, photos: scene.photos)

        // Only the photo that has an id can be shown yet.
        #expect(scene.milestone.photoRemoteIds == [77])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/AddMilestone").isEmpty)

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        // Blocked, not failed: five passes would otherwise discard the milestone.
        #expect(operations.first?.retryCount == 0)
    }

    @Test("A photo deleted before the operation runs drops out of the list")
    func deletedPhotoIsSkipped() async throws {
        let harness = try TestSync.harness(connected: false)
        let scene = try Self.scene(in: harness)
        Self.routeAdd(harness, photoIds: [78])

        try await harness.service.addMilestone(scene.milestone, for: scene.person, photos: scene.photos)

        harness.context.delete(scene.photos[0])
        try harness.context.save()

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        // The milestone is still worth writing; the photo is not there to attach.
        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/AddMilestone").first))
        #expect(body["photoIds"] as? [Int] == [78])
        #expect(scene.milestone.remoteId == "40")
    }

    // MARK: - Queue durability

    @Test("An operation queued by an older build decodes as no opinion on photos")
    func legacyPayloadDecodes() throws {
        let create = try #require("""
        {"personLocalId":"abc","description":"First steps","category":"development","milestoneDate":"2026-01-05"}
        """.data(using: .utf8))
        let decodedCreate = try JSONDecoder().decode(CreateMilestonePayload.self, from: create)
        #expect(decodedCreate.photoLocalIds == nil)

        let update = try #require("""
        {"description":"First steps","category":"development","milestoneDate":"2026-01-05"}
        """.data(using: .utf8))
        let decodedUpdate = try JSONDecoder().decode(UpdateMilestonePayload.self, from: update)
        #expect(decodedUpdate.photoLocalIds == nil)
    }
}
