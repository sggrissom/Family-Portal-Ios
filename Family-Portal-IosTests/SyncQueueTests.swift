import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("SyncQueue merge and retry")
struct SyncQueueTests {

    /// A throwaway UserDefaults suite so tests never touch the app's real queue
    /// and never see each other's writes.
    static func scratchQueue() -> (SyncQueue, UserDefaults) {
        let name = "SyncQueueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (SyncQueue(defaults: defaults), defaults)
    }

    static func operation(
        _ type: SyncOperationType,
        localId: String,
        payload: some Encodable,
        createdAt: Date = Date(),
        dependsOnLocalId: String? = nil
    ) throws -> PendingOperation {
        PendingOperation(
            type: type,
            localId: localId,
            payload: try JSONEncoder().encode(payload),
            createdAt: createdAt,
            dependsOnLocalId: dependsOnLocalId
        )
    }

    // MARK: - Update coalescing

    @Test(
        "A second update to the same record replaces the first",
        arguments: [SyncOperationType.updatePerson, .updateGrowthData, .updateMilestone, .updatePhoto]
    )
    func updatesCoalesce(type: SyncOperationType) async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(type, localId: "A", payload: ["v": 1]))
        await queue.enqueue(try Self.operation(type, localId: "A", payload: ["v": 2]))

        let operations = await queue.allOperations()
        #expect(operations.count == 1)

        let payload = try JSONDecoder().decode([String: Int].self, from: operations[0].payload)
        #expect(payload["v"] == 2)
    }

    @Test("Updates to different records stay separate")
    func updatesToDifferentRecordsDoNotMerge() async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(.updatePerson, localId: "A", payload: ["v": 1]))
        await queue.enqueue(try Self.operation(.updatePerson, localId: "B", payload: ["v": 1]))

        #expect(await queue.count() == 2)
    }

    @Test("Coalescing preserves the retry count already accrued")
    func coalescingKeepsRetryCount() async throws {
        let (queue, _) = Self.scratchQueue()

        let first = try Self.operation(.updatePerson, localId: "A", payload: ["v": 1])
        await queue.enqueue(first)
        await queue.markFailed(first.id)
        await queue.markFailed(first.id)

        await queue.enqueue(try Self.operation(.updatePerson, localId: "A", payload: ["v": 2]))

        let operations = await queue.allOperations()
        #expect(operations.count == 1)
        // Otherwise a record edited repeatedly while offline could retry forever.
        #expect(operations[0].retryCount == 2)
    }

    // MARK: - Photo tagging add/remove cancellation

    @Test("Tagging then untagging the same person cancels out entirely")
    func addThenRemoveCancels() async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(
            .addPeopleToPhoto, localId: "photo", payload: AddPeopleToPhotoPayload(personLocalIds: ["p1"])
        ))
        await queue.enqueue(try Self.operation(
            .removePersonFromPhoto, localId: "photo", payload: RemovePersonFromPhotoPayload(personLocalId: "p1")
        ))

        #expect(await queue.count() == 0)
    }

    @Test("Untagging one of several tagged people leaves the rest queued")
    func removeTrimsPendingAdd() async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(
            .addPeopleToPhoto, localId: "photo",
            payload: AddPeopleToPhotoPayload(personLocalIds: ["p1", "p2"])
        ))
        await queue.enqueue(try Self.operation(
            .removePersonFromPhoto, localId: "photo", payload: RemovePersonFromPhotoPayload(personLocalId: "p1")
        ))

        let operations = await queue.allOperations()
        #expect(operations.count == 1)
        #expect(operations[0].type == .addPeopleToPhoto)

        let payload = try JSONDecoder().decode(AddPeopleToPhotoPayload.self, from: operations[0].payload)
        #expect(payload.personLocalIds == ["p2"])
    }

    @Test("Untagging then re-tagging the same person cancels the removal")
    func addCancelsPendingRemove() async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(
            .removePersonFromPhoto, localId: "photo", payload: RemovePersonFromPhotoPayload(personLocalId: "p1")
        ))
        await queue.enqueue(try Self.operation(
            .addPeopleToPhoto, localId: "photo", payload: AddPeopleToPhotoPayload(personLocalIds: ["p1"])
        ))

        #expect(await queue.count() == 0)
    }

    @Test("Successive tag operations on one photo merge into a single add")
    func addsMergeIntoOneOperation() async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(
            .addPeopleToPhoto, localId: "photo", payload: AddPeopleToPhotoPayload(personLocalIds: ["p1"])
        ))
        await queue.enqueue(try Self.operation(
            .addPeopleToPhoto, localId: "photo", payload: AddPeopleToPhotoPayload(personLocalIds: ["p2"])
        ))

        let operations = await queue.allOperations()
        #expect(operations.count == 1)

        let payload = try JSONDecoder().decode(AddPeopleToPhotoPayload.self, from: operations[0].payload)
        #expect(payload.personLocalIds == ["p1", "p2"])
    }

    @Test("Tag operations on different photos stay separate")
    func addsOnDifferentPhotosDoNotMerge() async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(
            .addPeopleToPhoto, localId: "photoA", payload: AddPeopleToPhotoPayload(personLocalIds: ["p1"])
        ))
        await queue.enqueue(try Self.operation(
            .addPeopleToPhoto, localId: "photoB", payload: AddPeopleToPhotoPayload(personLocalIds: ["p1"])
        ))

        #expect(await queue.count() == 2)
    }

    // MARK: - Creates and deletes never merge

    @Test("Repeated creates are never collapsed")
    func createsNeverMerge() async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(.createMilestone, localId: "A", payload: ["v": 1]))
        await queue.enqueue(try Self.operation(.createMilestone, localId: "A", payload: ["v": 2]))

        #expect(await queue.count() == 2)
    }

    // MARK: - Retry cap

    @Test("An operation is discarded after the retry cap")
    func retryCapDiscards() async throws {
        let (queue, _) = Self.scratchQueue()

        let operation = try Self.operation(.createMilestone, localId: "A", payload: ["v": 1])
        await queue.enqueue(operation)

        for _ in 0..<4 {
            // Nothing is returned while the operation is still retryable.
            #expect(await queue.markFailed(operation.id) == nil)
        }
        #expect(await queue.count() == 1)

        // The last failure hands the operation back, which is how the user gets
        // told a change was thrown away rather than merely delayed.
        let discarded = await queue.markFailed(operation.id)
        #expect(discarded?.id == operation.id)
        #expect(await queue.count() == 0)
    }

    // MARK: - Blocked cap

    /// The other end of the retry cap. A blocked run means nothing was sent, so
    /// it must not spend a retry — but "never spends anything" is how an
    /// operation waiting on a parent that was itself discarded stays in the queue
    /// for the life of the install.
    @Test("A blocked operation is discarded eventually, without spending retries")
    func blockedCapDiscards() async throws {
        let (queue, _) = Self.scratchQueue()

        let operation = try Self.operation(
            .createMilestone, localId: "A", payload: ["v": 1], dependsOnLocalId: "person"
        )
        await queue.enqueue(operation)

        for _ in 0..<19 {
            #expect(await queue.markBlocked(operation.id) == nil)
        }
        #expect(await queue.count() == 1)

        let stillQueued = try #require(await queue.allOperations().first)
        #expect(stillQueued.blockedCount == 19)
        // The server was never asked, so it never said no.
        #expect(stillQueued.retryCount == 0)

        let discarded = await queue.markBlocked(operation.id)
        #expect(discarded?.id == operation.id)
        #expect(await queue.count() == 0)
    }

    @Test("Coalescing preserves the blocked count already accrued")
    func coalescingKeepsBlockedCount() async throws {
        let (queue, _) = Self.scratchQueue()

        let first = try Self.operation(.updatePhoto, localId: "A", payload: ["v": 1], dependsOnLocalId: "A")
        await queue.enqueue(first)
        await queue.markBlocked(first.id)
        await queue.markBlocked(first.id)

        await queue.enqueue(try Self.operation(
            .updatePhoto, localId: "A", payload: ["v": 2], dependsOnLocalId: "A"
        ))

        let operations = await queue.allOperations()
        #expect(operations.count == 1)
        // Otherwise editing a blocked record resets the clock, and a photo that
        // is never going to upload keeps its edits queued forever.
        #expect(operations[0].blockedCount == 2)
    }

    // MARK: - Dependency gating

    @Test("An operation waits until the record it depends on has synced")
    func dependenciesGateReadiness() async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(
            .updatePhoto, localId: "photo", payload: ["v": 1], dependsOnLocalId: "photo"
        ))

        #expect(await queue.readyOperations(syncedLocalIds: []).isEmpty)
        #expect(await queue.readyOperations(syncedLocalIds: ["photo"]).count == 1)
    }

    /// `blockedOperations` has to be the exact complement of `readyOperations`:
    /// an operation in neither list is one nothing will ever account for.
    @Test("Blocked operations are everything the ready set leaves out")
    func blockedOperationsComplementReady() async throws {
        let (queue, _) = Self.scratchQueue()

        await queue.enqueue(try Self.operation(
            .updatePhoto, localId: "waiting", payload: ["v": 1], dependsOnLocalId: "photo"
        ))
        await queue.enqueue(try Self.operation(.createMilestone, localId: "free", payload: ["v": 1]))

        #expect(await queue.blockedOperations(syncedLocalIds: []).map(\.localId) == ["waiting"])
        #expect(await queue.readyOperations(syncedLocalIds: []).map(\.localId) == ["free"])
        #expect(await queue.blockedOperations(syncedLocalIds: ["photo"]).isEmpty)
    }

    @Test("Ready operations come back oldest first")
    func readyOperationsAreOrdered() async throws {
        let (queue, _) = Self.scratchQueue()
        let now = Date()

        await queue.enqueue(try Self.operation(
            .createMilestone, localId: "B", payload: ["v": 2], createdAt: now
        ))
        await queue.enqueue(try Self.operation(
            .createMilestone, localId: "A", payload: ["v": 1], createdAt: now.addingTimeInterval(-60)
        ))

        let ready = await queue.readyOperations(syncedLocalIds: [])
        #expect(ready.map(\.localId) == ["A", "B"])
    }

    // MARK: - Persistence

    @Test("A queue reloads what the previous instance persisted")
    func persistsAcrossInstances() async throws {
        let name = "SyncQueueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let first = SyncQueue(defaults: defaults)
        await first.enqueue(try Self.operation(.createMilestone, localId: "A", payload: ["v": 1]))

        let second = SyncQueue(defaults: defaults)
        #expect(await second.count() == 1)
    }

    /// The whole queue is persisted as one array, so an operation written before
    /// `blockedCount` existed must not merely be skipped — a decode failure takes
    /// every other pending change on the device with it.
    @Test("A queue written by a build without blockedCount still loads")
    func loadsOperationsFromBeforeBlockedCount() async throws {
        let name = "SyncQueueTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let stored = [
            try Self.operation(.createMilestone, localId: "old", payload: ["v": 1]),
            try Self.operation(.updatePhoto, localId: "alsoOld", payload: ["v": 2])
        ]
        // Round-trip through JSON and strip the key, rather than hand-writing the
        // encoding: `Data` and `Date` have representations the encoder chooses.
        let encoded = try JSONEncoder().encode(stored)
        let decoded = try JSONSerialization.jsonObject(with: encoded)
        var raw = try #require(decoded as? [[String: Any]])
        for index in raw.indices {
            raw[index].removeValue(forKey: "blockedCount")
        }
        #expect(raw.count == 2)
        defaults.set(try JSONSerialization.data(withJSONObject: raw), forKey: "com.familyrecord.syncQueue")

        let queue = SyncQueue(defaults: defaults)
        let loaded = await queue.allOperations()
        #expect(loaded.map(\.localId) == ["old", "alsoOld"])
        #expect(loaded.allSatisfy { $0.blockedCount == 0 })
    }
}
