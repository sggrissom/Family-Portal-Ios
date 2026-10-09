import Foundation
import OSLog

// MARK: - Operation Types

nonisolated enum SyncOperationType: String, Codable, Sendable {
    case createPerson
    case updatePerson
    case setProfilePhoto
    case createGrowthData
    /// A height and a weight saved together through `AddCheckup`. Keyed on the height's local id when there is one.
    case createCheckup
    case createMilestone
    case uploadPhoto
    case addPeopleToPhoto
    case removePersonFromPhoto
    case updateGrowthData
    case updateMilestone
    case updatePhoto
    case updatePhotoTags
    case updateMilestoneTags
    case deleteGrowthData
    case deleteMilestone
    case deletePhoto

    var subjectDescription: String {
        switch self {
        case .createPerson, .updatePerson:
            return "a family member"
        case .setProfilePhoto:
            return "a profile photo"
        case .createGrowthData, .updateGrowthData, .deleteGrowthData:
            return "a measurement"
        case .createCheckup:
            return "a checkup"
        case .createMilestone, .updateMilestone, .deleteMilestone:
            return "a milestone"
        case .updatePhotoTags, .updateMilestoneTags:
            return "a set of tags"
        case .uploadPhoto, .updatePhoto, .deletePhoto, .addPeopleToPhoto, .removePersonFromPhoto:
            return "a photo"
        }
    }
}

// MARK: - Pending Operation

nonisolated struct PendingOperation: Codable, Identifiable, Sendable {
    let id: UUID
    let type: SyncOperationType
    let localId: String
    var payload: Data
    let createdAt: Date
    var retryCount: Int
    /// Sync runs this operation sat out because a dependency has not synced. Counted apart from `retryCount`, but not free, or a permanently blocked operation stays for the life of the install.
    /// `@OrZero` because operations written before the field existed lack it: the queue is one blob, and one undecodable operation would take every pending change with it.
    @OrZero var blockedCount: Int
    let dependsOnLocalId: String?

    init(
        id: UUID = UUID(),
        type: SyncOperationType,
        localId: String,
        payload: Data,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        blockedCount: Int = 0,
        dependsOnLocalId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.localId = localId
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.blockedCount = blockedCount
        self.dependsOnLocalId = dependsOnLocalId
    }

    func isReady(syncedLocalIds: Set<String>) -> Bool {
        guard let dependsOnLocalId else { return true }
        return syncedLocalIds.contains(dependsOnLocalId)
    }
}

// MARK: - Payload Structs

nonisolated struct CreatePersonPayload: Codable, Sendable {
    let name: String
    let gender: Int
    let birthdate: String
    /// True while `birthdate` is a due date rather than a birth date. This and `additionalAnchorLocalIds` are `@OrZero` because operations queued by an earlier build are still on disk at launch, and must not fail to decode over fields they never wrote.
    @OrZero var isPregnancy: Bool = false
    /// `StatedRelation`'s raw value: what the new person is to `anchorLocalId`. `0` means none was stated.
    let stated: Int
    /// The anchor as a *local* id, resolved to a server id when the operation runs, exactly as a milestone's photo ids are: an anchor added moments earlier may not be on the server yet, and parking beats sending a person with no relationship at all.
    let anchorLocalId: String?
    /// More anchors the same statement applies to, also as local ids. Unlike the primary anchor these are *dropped* when they cannot be resolved: they were a suggestion the user accepted, not the relationship they set out to state, and holding the whole create back for one of them would be worse than saving without it.
    @OrZero var additionalAnchorLocalIds: [String] = []
}

nonisolated struct UpdatePersonPayload: Codable, Sendable {
    let name: String
    let gender: Int
    let birthdate: String
    @OrZero var isPregnancy: Bool = false
}

nonisolated struct SetProfilePhotoPayload: Codable, Sendable {
    let photoLocalId: String
    let cropX: Double
    let cropY: Double
    let cropScale: Double
}

nonisolated struct CreateGrowthDataPayload: Codable, Sendable {
    let personLocalId: String
    let measurementType: String
    let value: Double
    let unit: String
    let measurementDate: String
}

/// Both values of a checkup. The operation is keyed on one record's local id, so the other's travels here; each half is `nil` when that field was blank.
nonisolated struct CreateCheckupPayload: Codable, Sendable {
    let personLocalId: String
    let measurementDate: String
    let heightLocalId: String?
    let heightValue: Double?
    let heightUnit: String?
    let weightLocalId: String?
    let weightValue: Double?
    let weightUnit: String?

    var recordLocalIds: [String] {
        [heightLocalId, weightLocalId].compactMap { $0 }
    }
}

nonisolated struct CreateMilestonePayload: Codable, Sendable {
    let personLocalId: String
    let description: String
    let category: String
    let milestoneDate: String
    /// Local ids, resolved to remote ids when the operation runs. Optional so operations written by a build without this field still decode.
    let photoLocalIds: [String]?
    /// Remote ids, as in `UpdateTagsPayload`. Optional for the same reason as `photoLocalIds`; `nil` sends no tags.
    var tagRemoteIds: [Int]? = nil
    /// Optional so an operation queued by an older build still decodes, as no context.
    var context: String? = nil
}

/// The caption and date are read from the photo when the upload runs, so an edit made while it waited goes up with it. Operations queued by older builds also carry `title`, `description` and `photoDate`, which decoding ignores.
nonisolated struct UploadPhotoPayload: Codable, Sendable {
    let taggedPersonLocalIds: [String]
}

nonisolated struct AddPeopleToPhotoPayload: Codable, Sendable {
    let personLocalIds: [String]
}

nonisolated struct RemovePersonFromPhotoPayload: Codable, Sendable {
    let personLocalId: String
}

nonisolated struct UpdateGrowthDataPayload: Codable, Sendable {
    let measurementType: String
    let value: Double
    let unit: String
    let measurementDate: String
}

nonisolated struct UpdateMilestonePayload: Codable, Sendable {
    let description: String
    let category: String
    let milestoneDate: String
    /// `nil` leaves the attachments alone, an empty array detaches everything. See `CreateMilestonePayload` for why these are local ids.
    let photoLocalIds: [String]?
    /// `nil` leaves the tags alone, an empty array clears them. An operation queued by an older build decodes as `nil`.
    var tagRemoteIds: [Int]? = nil
    /// Optional so an operation queued by an older build still decodes, as no context.
    var context: String? = nil
}

nonisolated struct UpdatePhotoPayload: Codable, Sendable {
    let title: String
    let description: String
    let photoDate: String
    /// Sends `inputType: "keep"` so the server leaves the photo's date alone — what the photo batch form sends for a caption when nobody changed the date. Optional so an operation queued by an older build still decodes, as `false`.
    var keepDate: Bool? = nil
}

/// The record's complete tag set, for both `updatePhotoTags` and `updateMilestoneTags`. These are *remote* ids: iOS creates no tags, so there is nothing to resolve at execution.
nonisolated struct UpdateTagsPayload: Codable, Sendable {
    let tagRemoteIds: [Int]
}

nonisolated struct DeletePayload: Codable, Sendable {
    let remoteId: Int
}

// MARK: - SyncQueue Actor

actor SyncQueue {
    private static let maxRetries = 5

    /// Deliberately much larger than `maxRetries` — a backstop against "never", not a timeout.
    private static let maxBlockedRuns = 20

    private var operations: [PendingOperation]
    private let store: SyncQueueStore

    /// The operation a sync run is sending right now. Nothing is merged into it or cancelled against it: the run dequeues it by id once the server answers, which would throw away whatever had been folded in mid-flight, and a request already on the wire cannot be taken back.
    private var executingId: UUID?

    init(store: SyncQueueStore = SyncQueueStore()) {
        self.store = store
        operations = store.load()
    }

    // MARK: - Queue Management

    func enqueue(_ operation: PendingOperation) {
        if mergeOperationIfPossible(operation) {
            saveToStorage()
            return
        }

        operations.append(operation)
        saveToStorage()
    }

    func dequeue(_ operationId: UUID) {
        finishExecuting(operationId)
        operations.removeAll { $0.id == operationId }
        saveToStorage()
    }

    /// Marks `operationId` as on the wire until it is dequeued, marked, or `endExecuting()` is called.
    func beginExecuting(_ operationId: UUID) {
        executingId = operationId
    }

    func endExecuting() {
        executingId = nil
    }

    private func finishExecuting(_ operationId: UUID) {
        if executingId == operationId {
            executingId = nil
        }
    }

    /// Whether a new operation may be merged into `operation` or cancel it out.
    private func isSettled(_ operation: PendingOperation) -> Bool {
        operation.id != executingId
    }

    func readyOperations(syncedLocalIds: Set<String>) -> [PendingOperation] {
        return operations.filter { $0.isReady(syncedLocalIds: syncedLocalIds) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func blockedOperations(syncedLocalIds: Set<String>) -> [PendingOperation] {
        return operations.filter { !$0.isReady(syncedLocalIds: syncedLocalIds) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// - Returns: the operation if this failure used up its last retry and it was dropped, which the caller has to tell the user about.
    @discardableResult
    func markFailed(_ operationId: UUID) -> PendingOperation? {
        finishExecuting(operationId)
        guard let index = operations.firstIndex(where: { $0.id == operationId }) else {
            return nil
        }

        var operation = operations[index]
        operation.retryCount += 1

        guard operation.retryCount >= Self.maxRetries else {
            operations[index] = operation
            saveToStorage()
            return nil
        }

        AppLog.queue.error(
            "Discarding \(operation.type.rawValue, privacy: .public) for \(operation.localId, privacy: .public) after \(operation.retryCount) failed attempts"
        )
        operations.remove(at: index)
        saveToStorage()
        return operation
    }

    /// Records that a sync run could not run this operation because a dependency has not synced. Not a retry, but not free either: a parent that was itself discarded blocks this one for good.
    /// - Returns: the operation if this run used up its allowance and it was dropped.
    @discardableResult
    func markBlocked(_ operationId: UUID) -> PendingOperation? {
        finishExecuting(operationId)
        guard let index = operations.firstIndex(where: { $0.id == operationId }) else {
            return nil
        }

        var operation = operations[index]
        operation.blockedCount += 1

        guard operation.blockedCount >= Self.maxBlockedRuns else {
            operations[index] = operation
            saveToStorage()
            return nil
        }

        AppLog.queue.error(
            "Discarding \(operation.type.rawValue, privacy: .public) for \(operation.localId, privacy: .public) after \(operation.blockedCount) runs blocked on unsynced dependencies"
        )
        operations.remove(at: index)
        saveToStorage()
        return operation
    }

    func allOperations() -> [PendingOperation] {
        return operations
    }

    func count() -> Int {
        return operations.count
    }

    func clearAll() {
        operations.removeAll()
        saveToStorage()
    }

    // MARK: - Persistence

    private func mergeOperationIfPossible(_ incoming: PendingOperation) -> Bool {
        switch incoming.type {
        case .updatePerson, .updateGrowthData, .updateMilestone, .updatePhoto, .setProfilePhoto,
             .updatePhotoTags, .updateMilestoneTags:
            // A person has one profile photo, and every tag toggle enqueues the whole set, so merging sends one truthful request instead of several stale ones.
            return replaceExistingOperation(of: incoming.type, localId: incoming.localId, with: incoming)
        case .addPeopleToPhoto:
            return mergeAddPeopleToPhoto(incoming)
        case .removePersonFromPhoto:
            return mergeRemovePersonFromPhoto(incoming)
        default:
            return false
        }
    }

    private func replaceExistingOperation(of type: SyncOperationType, localId: String, with incoming: PendingOperation) -> Bool {
        guard let index = operations.lastIndex(where: { $0.type == type && $0.localId == localId && isSettled($0) }) else {
            return false
        }

        var replacement = incoming
        replacement.retryCount = operations[index].retryCount
        replacement.blockedCount = operations[index].blockedCount
        operations[index] = replacement
        return true
    }

    private func mergeAddPeopleToPhoto(_ incoming: PendingOperation) -> Bool {
        guard let incomingPayload = try? JSONDecoder().decode(AddPeopleToPhotoPayload.self, from: incoming.payload) else {
            return false
        }

        var peopleToAdd = Set(incomingPayload.personLocalIds)
        operations.removeAll { operation in
            guard operation.type == .removePersonFromPhoto,
                  operation.localId == incoming.localId,
                  isSettled(operation),
                  let payload = try? JSONDecoder().decode(RemovePersonFromPhotoPayload.self, from: operation.payload)
            else {
                return false
            }

            return peopleToAdd.remove(payload.personLocalId) != nil
        }

        guard !peopleToAdd.isEmpty else {
            return true
        }

        if let existingIndex = operations.lastIndex(where: { $0.type == .addPeopleToPhoto && $0.localId == incoming.localId && isSettled($0) }),
           let existingPayload = try? JSONDecoder().decode(AddPeopleToPhotoPayload.self, from: operations[existingIndex].payload) {
            var mergedPeople = Set(existingPayload.personLocalIds)
            mergedPeople.formUnion(peopleToAdd)
            let mergedPayload = AddPeopleToPhotoPayload(personLocalIds: Array(mergedPeople).sorted())

            guard let encodedPayload = try? JSONEncoder().encode(mergedPayload) else {
                return false
            }

            operations[existingIndex].payload = encodedPayload
            return true
        }

        guard peopleToAdd.count == incomingPayload.personLocalIds.count else {
            let adjustedPayload = AddPeopleToPhotoPayload(personLocalIds: Array(peopleToAdd).sorted())
            guard let encodedPayload = try? JSONEncoder().encode(adjustedPayload) else {
                return false
            }

            var adjusted = incoming
            adjusted.payload = encodedPayload
            operations.append(adjusted)
            return true
        }

        return false
    }

    private func mergeRemovePersonFromPhoto(_ incoming: PendingOperation) -> Bool {
        guard let incomingPayload = try? JSONDecoder().decode(RemovePersonFromPhotoPayload.self, from: incoming.payload) else {
            return false
        }

        if let addIndex = operations.lastIndex(where: { $0.type == .addPeopleToPhoto && $0.localId == incoming.localId && isSettled($0) }),
           let addPayload = try? JSONDecoder().decode(AddPeopleToPhotoPayload.self, from: operations[addIndex].payload) {
            let remainingPeople = addPayload.personLocalIds.filter { $0 != incomingPayload.personLocalId }

            if remainingPeople.count != addPayload.personLocalIds.count {
                if remainingPeople.isEmpty {
                    operations.remove(at: addIndex)
                } else {
                    let updatedPayload = AddPeopleToPhotoPayload(personLocalIds: remainingPeople)
                    guard let encodedPayload = try? JSONEncoder().encode(updatedPayload) else {
                        return false
                    }
                    operations[addIndex].payload = encodedPayload
                }
                return true
            }
        }

        if let existingIndex = operations.lastIndex(where: { $0.type == .removePersonFromPhoto && $0.localId == incoming.localId && isSettled($0) }),
           let existingPayload = try? JSONDecoder().decode(RemovePersonFromPhotoPayload.self, from: operations[existingIndex].payload),
           existingPayload.personLocalId == incomingPayload.personLocalId {
            var replacement = incoming
            replacement.retryCount = operations[existingIndex].retryCount
            replacement.blockedCount = operations[existingIndex].blockedCount
            operations[existingIndex] = replacement
            return true
        }

        return false
    }

    private func saveToStorage() {
        store.save(operations)
    }
}
