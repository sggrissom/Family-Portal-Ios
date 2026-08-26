import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("SyncService queue execution")
struct SyncServiceQueueTests {

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

    @Test("An operation blocked on an unsynced parent stays queued")
    func unsyncedParentKeepsOperation() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = try Self.syncedPerson(in: harness)

        let measurement = GrowthData(measurementType: .height, value: 104.5, unit: .centimeters, date: Date())
        measurement.person = person
        harness.context.insert(measurement)
        try harness.context.save()

        try await harness.service.addGrowthData(measurement, for: person)

        person.remoteId = nil
        try harness.context.save()

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/AddGrowthData").isEmpty)

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        #expect(operations.first?.retryCount == 0)
    }

    @Test("An operation held back by the dependency gate is eventually given up on")
    func gateBlockedOperationIsEventuallyDiscarded() async throws {
        let harness = try TestSync.harness(connected: false)

        let person = Person(name: "Rowan", type: .child, gender: .other, birthday: Date())
        harness.context.insert(person)
        try harness.context.save()

        let milestone = Milestone(descriptionText: "First steps", category: .development, date: Date())
        milestone.person = person
        harness.context.insert(milestone)
        try harness.context.save()

        try await harness.service.addMilestone(milestone, for: person)

        harness.monitor.isConnected = true
        for _ in 0..<19 {
            await harness.service.processQueue()
        }

        #expect(harness.server.requests(for: "rpc/AddMilestone").isEmpty)
        #expect(await harness.service.syncQueue.count() == 1)
        #expect(harness.service.discardedChangeWarning == nil)

        await harness.service.processQueue()

        #expect(await harness.service.syncQueue.count() == 0)
        #expect(harness.service.pendingOperationCount == 0)
        let warning = try #require(harness.service.discardedChangeWarning)
        #expect(warning.contains("milestone"))
    }

    @Test("A run cut short by the network costs blocked operations nothing")
    func networkFailureSpendsNoBlockedRun() async throws {
        let harness = try TestSync.harness(connected: false)
        harness.server.route("api/upload-photo", respond: .offline())

        let photo = Photo(title: "Beach", descriptionText: "", photoDate: Date(), imageData: Data([0xFF, 0xD8]))
        harness.context.insert(photo)
        try harness.context.save()

        try await harness.service.uploadPhoto(photo)
        // Waits on the upload above, which is about to fail offline.
        try await harness.service.updatePhoto(photo)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 2)
        #expect(operations.allSatisfy { $0.blockedCount == 0 && $0.retryCount == 0 })
    }

    @Test("A dependency satisfied during the run costs its children nothing")
    func dependencySatisfiedMidRunCostsNothing() async throws {
        let harness = try TestSync.harness(connected: false)
        harness.server.route("api/upload-photo", respond: .json(["image": Fixture.image(id: 77, title: "Beach")]))
        harness.server.route("rpc/UpdatePhoto", respond: .status(503, message: "unavailable"))

        let photo = Photo(title: "Beach", descriptionText: "", photoDate: Date(), imageData: Data([0xFF, 0xD8]))
        harness.context.insert(photo)
        try harness.context.save()

        try await harness.service.uploadPhoto(photo)
        try await harness.service.updatePhoto(photo)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(photo.remoteId == "77")
        #expect(harness.server.requests(for: "rpc/UpdatePhoto").isEmpty)

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        #expect(operations.first?.type == .updatePhoto)
        #expect(operations.first?.blockedCount == 0)
        #expect(operations.first?.retryCount == 0)

        // And the next run does reach it.
        await harness.service.processQueue()
        #expect(harness.server.requests(for: "rpc/UpdatePhoto").count == 1)
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
        // The server holds the bytes now.
        #expect(photo.imageData == nil)
        #expect(await harness.service.syncQueue.count() == 0)
    }

    // MARK: - Overlapping runs

    @Test("Overlapping queue runs send each operation once")
    func overlappingRunsSendEachOperationOnce() async throws {
        let harness = try TestSync.harness(connected: false)
        harness.server.route("api/upload-photo", respond: .json(["image": Fixture.image(id: 77, title: "Beach")]))

        let photo = Photo(title: "Beach", descriptionText: "", photoDate: Date(), imageData: Data([0xFF, 0xD8]))
        harness.context.insert(photo)
        try harness.context.save()

        try await harness.service.uploadPhoto(photo)

        harness.monitor.isConnected = true
        async let first: Void = harness.service.processQueue()
        async let second: Void = harness.service.processQueue()
        _ = await (first, second)

        #expect(harness.server.requests(for: "api/upload-photo").count == 1)
        #expect(await harness.service.syncQueue.count() == 0)
    }

    @Test("Work enqueued during a run is picked up by that run")
    func workEnqueuedMidRunIsPickedUp() async throws {
        let harness = try TestSync.harness(connected: false)

        let arrived = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        harness.server.route("api/upload-photo") { _ in
            arrived.signal()
            release.wait()
            return .json(["image": Fixture.image(id: 77, title: "Beach")])
        }
        harness.server.route("rpc/UpdatePhoto", respond: .json(["image": Fixture.image(id: 77, title: "Sunset")]))

        let photo = Photo(title: "Beach", descriptionText: "", photoDate: Date(), imageData: Data([0xFF, 0xD8]))
        harness.context.insert(photo)
        try harness.context.save()

        try await harness.service.uploadPhoto(photo)

        harness.monitor.isConnected = true
        async let run: Void = harness.service.processQueue()

        await Task.detached { blockUntilSignalled(arrived) }.value
        photo.title = "Sunset"
        try harness.context.save()
        try await harness.service.updatePhoto(photo)

        release.signal()
        await run

        var settled = false
        for _ in 0..<200 where !settled {
            let stillQueued = await harness.service.syncQueue.count()
            settled = stillQueued == 0 && !harness.server.requests(for: "rpc/UpdatePhoto").isEmpty
            if !settled { await Task.yield() }
        }
        #expect(settled)
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

private nonisolated func blockUntilSignalled(_ semaphore: DispatchSemaphore) {
    semaphore.wait()
}
