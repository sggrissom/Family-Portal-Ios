import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Tag editing")
struct TagEditingTests {

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    private static func routePhotoTags(_ harness: TestSync.Harness) {
        harness.server.route("rpc/UpdatePhotoTags", respond: .json([String: Any]()))
    }

    private static func routeMilestoneTags(_ harness: TestSync.Harness) {
        harness.server.route("rpc/UpdateMilestoneTags", respond: .json([String: Any]()))
    }

    @discardableResult
    private static func storeTag(_ harness: TestSync.Harness, id: Int, name: String) throws -> FamilyTag {
        let tag = FamilyTag(name: name, colorHex: "#4A90D9", familyId: 1)
        tag.remoteId = String(id)
        harness.context.insert(tag)
        try harness.context.save()
        return tag
    }

    private static func storePhoto(
        _ harness: TestSync.Harness,
        remoteId: String? = "5",
        tagRemoteIds: [Int] = []
    ) throws -> Photo {
        let photo = Photo(title: "Beach", descriptionText: "", photoDate: Date(), imageData: nil)
        photo.remoteId = remoteId
        photo.tagRemoteIds = tagRemoteIds
        harness.context.insert(photo)
        try harness.context.save()
        return photo
    }

    private static func storeMilestone(
        _ harness: TestSync.Harness,
        remoteId: String? = "40",
        tagRemoteIds: [Int] = []
    ) throws -> Milestone {
        let milestone = Milestone(descriptionText: "First steps", category: .development, date: Date())
        milestone.remoteId = remoteId
        milestone.tagRemoteIds = tagRemoteIds
        harness.context.insert(milestone)
        try harness.context.save()
        return milestone
    }

    // MARK: - Photos

    @Test("Tagging a photo sends the whole set with the photo's id")
    func photoTagsAreSent() async throws {
        let harness = try TestSync.harness(connected: false)
        try Self.storeTag(harness, id: 3, name: "Holiday")
        try Self.storeTag(harness, id: 9, name: "School")
        let photo = try Self.storePhoto(harness, tagRemoteIds: [3])
        Self.routePhotoTags(harness)

        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [3, 9])

        // The chips have to change at the tap, not at the next pull.
        #expect(photo.tagRemoteIds == [3, 9])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdatePhotoTags").first))
        #expect(body["photoId"] as? Int == 5)
        #expect(body["tagIds"] as? [Int] == [3, 9])

        // An empty `{}` body is a success, not a decoding failure to retry.
        #expect(await harness.service.syncQueue.count() == 0)
    }

    @Test("Removing every tag sends an empty list")
    func clearingTagsSendsAnEmptyList() async throws {
        let harness = try TestSync.harness(connected: false)
        try Self.storeTag(harness, id: 3, name: "Holiday")
        let photo = try Self.storePhoto(harness, tagRemoteIds: [3])
        Self.routePhotoTags(harness)

        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [])

        #expect(photo.tagRemoteIds.isEmpty)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdatePhotoTags").first))
        let tagIds = try #require(body["tagIds"] as? [Int])
        #expect(tagIds.isEmpty)
    }

    @Test("A tag id this device can't resolve is still sent back")
    func unresolvedTagIdsSurvive() async throws {
        let harness = try TestSync.harness(connected: false)
        try Self.storeTag(harness, id: 3, name: "Holiday")
        let photo = try Self.storePhoto(harness, tagRemoteIds: [3, 999])
        Self.routePhotoTags(harness)

        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [3, 999])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdatePhotoTags").first))
        #expect(body["tagIds"] as? [Int] == [3, 999])
    }

    @Test("Repeated edits while offline collapse into one request")
    func repeatedEditsMerge() async throws {
        let harness = try TestSync.harness(connected: false)
        let photo = try Self.storePhoto(harness)
        Self.routePhotoTags(harness)

        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [3])
        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [3, 9])
        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [9])

        #expect(await harness.service.syncQueue.count() == 1)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let requests = harness.server.requests(for: "rpc/UpdatePhotoTags")
        #expect(requests.count == 1)
        let body = try Self.body(of: try #require(requests.first))
        #expect(body["tagIds"] as? [Int] == [9])
    }

    @Test("Tags chosen for a photo that is still uploading wait for it")
    func unsyncedPhotoParksTheWrite() async throws {
        let harness = try TestSync.harness(connected: false)
        let photo = try Self.storePhoto(harness, remoteId: nil)
        Self.routePhotoTags(harness)

        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [3])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/UpdatePhotoTags").isEmpty)

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        #expect(operations.first?.retryCount == 0)
        #expect(operations.first?.blockedCount == 1)
    }

    @Test("Tags for a photo deleted before the operation runs are dropped, not retried")
    func deletedPhotoDropsTheWrite() async throws {
        let harness = try TestSync.harness(connected: false)
        let photo = try Self.storePhoto(harness)
        Self.routePhotoTags(harness)

        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [3])

        harness.context.delete(photo)
        try harness.context.save()

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/UpdatePhotoTags").isEmpty)
        #expect(await harness.service.syncQueue.count() == 0)
    }

    // MARK: - Milestones

    @Test("Tagging a milestone sends the whole set with the milestone's id")
    func milestoneTagsAreSent() async throws {
        let harness = try TestSync.harness(connected: false)
        try Self.storeTag(harness, id: 3, name: "Holiday")
        let milestone = try Self.storeMilestone(harness)
        Self.routeMilestoneTags(harness)

        try await harness.service.updateMilestoneTags(milestone, tagRemoteIds: [3])

        #expect(milestone.tagRemoteIds == [3])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdateMilestoneTags").first))
        #expect(body["milestoneId"] as? Int == 40)
        #expect(body["tagIds"] as? [Int] == [3])
        #expect(await harness.service.syncQueue.count() == 0)
    }

    @Test("Tags on a milestone that hasn't synced wait for its create")
    func unsyncedMilestoneParksThenSends() async throws {
        let harness = try TestSync.harness(connected: false)
        let milestone = try Self.storeMilestone(harness, remoteId: nil)
        Self.routeMilestoneTags(harness)

        try await harness.service.updateMilestoneTags(milestone, tagRemoteIds: [3])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/UpdateMilestoneTags").isEmpty)
        let parked = await harness.service.syncQueue.allOperations()
        #expect(parked.first?.retryCount == 0)
        #expect(parked.first?.blockedCount == 1)

        milestone.remoteId = "40"
        try harness.context.save()
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/UpdateMilestoneTags").count == 1)
        #expect(await harness.service.syncQueue.count() == 0)
    }

    @Test("Tags for a milestone deleted before the operation runs are dropped")
    func deletedMilestoneDropsTheWrite() async throws {
        let harness = try TestSync.harness(connected: false)
        let milestone = try Self.storeMilestone(harness)
        Self.routeMilestoneTags(harness)

        try await harness.service.updateMilestoneTags(milestone, tagRemoteIds: [3])

        harness.context.delete(milestone)
        try harness.context.save()

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/UpdateMilestoneTags").isEmpty)
        #expect(await harness.service.syncQueue.count() == 0)
    }

    // MARK: - Queue plumbing

    @Test("A photo's tags and a milestone's tags are separate operations")
    func photoAndMilestoneWritesDoNotMerge() async throws {
        let harness = try TestSync.harness(connected: false)
        let photo = try Self.storePhoto(harness)
        let milestone = try Self.storeMilestone(harness)
        Self.routePhotoTags(harness)
        Self.routeMilestoneTags(harness)

        try await harness.service.updatePhotoTags(photo, tagRemoteIds: [3])
        try await harness.service.updateMilestoneTags(milestone, tagRemoteIds: [9])

        #expect(await harness.service.syncQueue.count() == 2)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let photoBody = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdatePhotoTags").first))
        #expect(photoBody["tagIds"] as? [Int] == [3])

        let milestoneBody = try Self.body(of: try #require(harness.server.requests(for: "rpc/UpdateMilestoneTags").first))
        #expect(milestoneBody["tagIds"] as? [Int] == [9])
    }
}
