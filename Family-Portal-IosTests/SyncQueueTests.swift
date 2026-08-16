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
}
