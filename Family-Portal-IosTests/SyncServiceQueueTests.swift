import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// The push half of sync: what `processQueue` does with an operation it cannot
/// complete. Getting this wrong is invisible — the queue drains, the pending
/// count reaches zero, and the change is simply gone — which is exactly how the
/// dropped-operation bug survived for so long.
///
/// Every case enqueues while "offline" and only then brings the network up:
/// `enqueueOperation` starts a background `processQueue` the moment it is
/// connected, and that run would race the one the test is asserting on.
@MainActor
@Suite("SyncService queue execution")
struct SyncServiceQueueTests {

    /// A person the server already knows about, so operations that hang off one
    /// are queued without a dependency.
    private static func syncedPerson(in harness: TestSync.Harness, remoteId: String = "12") throws -> Person {
        let person = Person(name: "Rowan", type: .child, gender: .other, birthday: Date())
        person.remoteId = remoteId
        harness.context.insert(person)
        try harness.context.save()
        return person
    }

    // MARK: - Moot work is dropped

    @Test("An operation whose record was deleted locally is dropped without a request")
    func deletedRecordDropsOperation() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.syncedPerson(in: harness)

        let measurement = GrowthData(measurementType: .height, value: 104.5, unit: .centimeters, date: Date())
        measurement.person = person
        harness.context.insert(measurement)
        try harness.context.save()

        try await harness.service.addGrowthData(measurement, for: person)

        harness.context.delete(measurement)
        try harness.context.save()

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/AddGrowthData").isEmpty)
        #expect(await harness.service.syncQueue.count() == 0)
        #expect(harness.service.pendingOperationCount == 0)
    }

    // MARK: - Work that is merely blocked is kept

    /// The three-way split in `executeCreateGrowthData`: a *missing* record is
    /// moot, but a record whose person has no remote id yet is only blocked. This
    /// used to `return`, which dequeued it as a success and stranded the
    /// measurement on the device with no remote id, forever.
    @Test("An operation blocked on an unsynced parent stays queued")
    func unsyncedParentKeepsOperation() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.syncedPerson(in: harness)

        let measurement = GrowthData(measurementType: .height, value: 104.5, unit: .centimeters, date: Date())
        measurement.person = person
        harness.context.insert(measurement)
        try harness.context.save()

        try await harness.service.addGrowthData(measurement, for: person)

        // The person's own create was discarded after this was queued, so it is
        // back to having no remote id.
        person.remoteId = nil
        try harness.context.save()

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/AddGrowthData").isEmpty)

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        // Blocked is not failed: burning a retry here would discard the
        // measurement after five passes through the queue.
        #expect(operations.first?.retryCount == 0)
    }

    // MARK: - Photo upload

    @Test("A confirmed upload adopts the remote id and releases the local bytes")
    func uploadClearsLocalBytes() async throws {
        let harness = try TestSync.harness(connected: false)
        harness.server.route("api/upload-photo", respond: .json(["image": Fixture.image(id: 77, title: "Beach")]))

        let photo = Photo(
            title: "Beach",
            descriptionText: "",
            photoDate: Date(),
            imageData: Data([0xFF, 0xD8, 0x01, 0x02])
        )
        harness.context.insert(photo)
        try harness.context.save()

        try await harness.service.uploadPhoto(photo)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "api/upload-photo").count == 1)
        #expect(photo.remoteId == "77")
        // The server holds the bytes now. Keeping them stored every photo twice,
        // and made the photo permanently exempt from orphan removal.
        #expect(photo.imageData == nil)
        #expect(await harness.service.syncQueue.count() == 0)
    }

    // MARK: - Discarding

    @Test("An operation that keeps failing is discarded, and the loss is reported")
    func repeatedFailureIsReported() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.syncedPerson(in: harness)
        harness.server.route("rpc/AddMilestone", respond: .status(500, message: "rejected"))

        let milestone = Milestone(descriptionText: "First steps", category: .development, date: Date())
        milestone.person = person
        harness.context.insert(milestone)
        try harness.context.save()

        try await harness.service.addMilestone(milestone, for: person)

        harness.monitor.isConnected = true
        for _ in 0..<5 {
            await harness.service.processQueue()
        }

        #expect(harness.server.requests(for: "rpc/AddMilestone").count == 5)
        #expect(await harness.service.syncQueue.count() == 0)
        #expect(harness.service.pendingOperationCount == 0)

        // A drained queue and a zero pending count look identical whether the
        // work succeeded or was thrown away, so the difference has to be said.
        let warning = try #require(harness.service.discardedChangeWarning)
        #expect(warning.contains("milestone"))

        harness.service.acknowledgeDiscardedChanges()
        #expect(harness.service.discardedChangeWarning == nil)
    }

    @Test("A rejection from the server costs the operation one retry")
    func serverRejectionSpendsOneRetry() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.syncedPerson(in: harness)
        harness.server.route("rpc/AddMilestone", respond: .status(503, message: "unavailable"))

        let milestone = Milestone(descriptionText: "First steps", category: .development, date: Date())
        milestone.person = person
        harness.context.insert(milestone)
        try harness.context.save()

        try await harness.service.addMilestone(milestone, for: person)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        #expect(operations.first?.retryCount == 1)
        #expect(harness.service.discardedChangeWarning == nil)
    }

    /// Losing the connection halfway through a queue run must not count against
    /// anything: five sync attempts on a train would otherwise discard work that
    /// the server never even saw.
    @Test("Losing the connection pauses the queue without spending a retry")
    func networkFailureSpendsNoRetry() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.syncedPerson(in: harness)
        harness.server.route("rpc/AddMilestone", respond: .offline())

        let milestone = Milestone(descriptionText: "First steps", category: .development, date: Date())
        milestone.person = person
        harness.context.insert(milestone)
        try harness.context.save()

        try await harness.service.addMilestone(milestone, for: person)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        #expect(operations.first?.retryCount == 0)
    }

    // MARK: - Preconditions

    /// A person with no birthday cannot exist server-side, so the push refuses
    /// rather than substituting today's date — which used to come straight back
    /// on the next pull, indistinguishable from a real birthday.
    @Test("Pushing a person with no birthday fails instead of inventing one")
    func missingBirthdayIsRefused() async throws {
        let harness = try TestSync.harness(connected: false)

        let person = Person(name: "No birthday", type: .child, gender: .other)
        harness.context.insert(person)
        try harness.context.save()

        await #expect(throws: SyncError.self) {
            try await harness.service.addPerson(person)
        }
        #expect(await harness.service.syncQueue.count() == 0)
    }

    @Test("Deleting a record that never synced is purely local")
    func deletingUnsyncedRecordSkipsTheQueue() async throws {
        let harness = try TestSync.harness(connected: false)

        let photo = Photo(title: "Never uploaded", descriptionText: "", photoDate: Date(), imageData: Data([0xFF, 0xD8]))
        harness.context.insert(photo)
        try harness.context.save()

        try await harness.service.deletePhoto(photo)

        #expect(try harness.context.fetch(FetchDescriptor<Photo>()).isEmpty)
        #expect(await harness.service.syncQueue.count() == 0)
    }
}
