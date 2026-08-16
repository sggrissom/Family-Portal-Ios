import Foundation
import OSLog

// MARK: - Operation Types

nonisolated enum SyncOperationType: String, Codable, Sendable {
    case createPerson
    case updatePerson
    case setProfilePhoto
    case createGrowthData
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

    /// What the record is called in the app's own language, for the one message
    /// the user sees when an operation is dropped.
    var subjectDescription: String {
        switch self {
        case .createPerson, .updatePerson:
            return "a family member"
        case .setProfilePhoto:
            return "a profile photo"
        case .createGrowthData, .updateGrowthData, .deleteGrowthData:
            return "a measurement"
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
    let payload: Data
    let createdAt: Date
    var retryCount: Int
    /// Sync runs this operation sat out because something it needs has not synced
    /// yet. Counted separately from `retryCount`, which means "the server was
    /// asked and said no" — nothing was sent here, so these must not spend a
    /// retry, but they cannot be free either or a permanently blocked operation
    /// stays in the queue for the life of the install.
    var blockedCount: Int
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

    private enum CodingKeys: String, CodingKey {
        case id, type, localId, payload, createdAt, retryCount, blockedCount, dependsOnLocalId
    }

    /// Decoded by hand only so a missing `blockedCount` defaults instead of
    /// throwing. The whole queue is one `[PendingOperation]` blob, so a single
    /// operation written by an older build failing to decode would take every
    /// pending change on the device down with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(SyncOperationType.self, forKey: .type)
        localId = try container.decode(String.self, forKey: .localId)
        payload = try container.decode(Data.self, forKey: .payload)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        retryCount = try container.decode(Int.self, forKey: .retryCount)
        blockedCount = try container.decodeIfPresent(Int.self, forKey: .blockedCount) ?? 0
        dependsOnLocalId = try container.decodeIfPresent(String.self, forKey: .dependsOnLocalId)
    }

    func isReady(syncedLocalIds: Set<String>) -> Bool {
        guard let dependsOnLocalId else { return true }
        return syncedLocalIds.contains(dependsOnLocalId)
    }
}

// MARK: - Payload Structs

nonisolated struct CreatePersonPayload: Codable, Sendable {
    let name: String
    let personType: Int
    let gender: Int
    let birthdate: String
}

nonisolated struct UpdatePersonPayload: Codable, Sendable {
    let name: String
    let personType: Int
    let gender: Int
    let birthdate: String
}

/// Keyed by the *person's* local id, like the operation itself; the photo is
/// carried here because it is the thing being chosen.
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

nonisolated struct CreateMilestonePayload: Codable, Sendable {
    let personLocalId: String
    let description: String
    let category: String
    let milestoneDate: String
    /// Local ids, resolved to remote ids when the operation runs: a photo picked
    /// while it is still uploading has no remote id yet at enqueue time. Optional
    /// so operations written by a build without this field still decode off disk
    /// after an upgrade.
    let photoLocalIds: [String]?
}

nonisolated struct UploadPhotoPayload: Codable, Sendable {
    let title: String
    let description: String
    let photoDate: String
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
    /// `nil` leaves the attachments alone, an empty array detaches everything —
    /// the same distinction the request DTO carries. See `CreateMilestonePayload`
    /// for why these are local ids.
    let photoLocalIds: [String]?
}

nonisolated struct UpdatePhotoPayload: Codable, Sendable {
    let title: String
    let description: String
    let photoDate: String
}

/// The record's complete tag set, for both `updatePhotoTags` and
/// `updateMilestoneTags` — the operation's own type says which record it belongs
/// to, and the request body is the same shape either way.
///
/// These are *remote* ids, unlike the photo ids a milestone operation carries.
/// A tag exists only because a pull produced it: iOS creates none, so there is
/// no id here that the server has yet to assign, and nothing to resolve at
/// execution.
nonisolated struct UpdateTagsPayload: Codable, Sendable {
    let tagRemoteIds: [Int]
}

nonisolated struct DeletePayload: Codable, Sendable {
    let remoteId: Int
}

// MARK: - SyncQueue Actor

actor SyncQueue {
    private static let storageKey = "com.familyrecord.syncQueue"
    private static let maxRetries = 5

    /// Deliberately much larger than `maxRetries`: a blocked run costs the user
    /// nothing and the parent it is waiting on gets five tries of its own, so the
    /// allowance has to outlast that by a wide margin. It is a backstop against
    /// "never", not a timeout.
    private static let maxBlockedRuns = 20

    private var operations: [PendingOperation]
    private let defaults: UserDefaults

    /// `defaults` is injectable so tests can exercise the merge/cancel logic
    /// against a scratch suite instead of the app's real queue.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        operations = Self.loadOperationsFromStorage(defaults: defaults)
    }

    nonisolated private static func loadOperationsFromStorage(defaults: UserDefaults) -> [PendingOperation] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([PendingOperation].self, from: data)
        } catch {
            AppLog.queue.error("Failed to load queue from storage: \(String(describing: error), privacy: .public)")
            return []
        }
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
        operations.removeAll { $0.id == operationId }
        saveToStorage()
    }

    func readyOperations(syncedLocalIds: Set<String>) -> [PendingOperation] {
        return operations.filter { $0.isReady(syncedLocalIds: syncedLocalIds) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The other half of `readyOperations`: everything the dependency gate held
    /// back this run. These are never handed to `executeOperation`, so without
    /// asking for them explicitly a caller has no way to notice that one of them
    /// is waiting on a parent that is never going to arrive.
    func blockedOperations(syncedLocalIds: Set<String>) -> [PendingOperation] {
        return operations.filter { !$0.isReady(syncedLocalIds: syncedLocalIds) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// - Returns: the operation if this failure used up its last retry and it was
    ///   dropped. Discarding is the one queue event the user has to hear about —
    ///   it is the moment a local change stops being "not synced yet" and becomes
    ///   "never syncing" — so the caller needs to know it happened.
    @discardableResult
    func markFailed(_ operationId: UUID) -> PendingOperation? {
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

    /// Record that a sync run could not run this operation because something it
    /// depends on has not synced. Nothing was sent, so this is not a retry — but
    /// an operation whose parent was itself discarded is blocked for good, and
    /// left alone it would be re-examined on every sync forever while its record
    /// sits on the device looking merely "not synced yet".
    ///
    /// - Returns: the operation if this run used up its allowance and it was
    ///   dropped, on the same terms as `markFailed`.
    @discardableResult
    func markBlocked(_ operationId: UUID) -> PendingOperation? {
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
            // A person has one profile photo, so picking a third while the first
            // two are still queued should send one request, not three. Tag sets
            // merge for a stronger reason: each toggle in the picker enqueues the
            // whole set, so a user choosing four tags offline would otherwise
            // queue four requests of which only the last says anything true.
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
        guard let index = operations.lastIndex(where: { $0.type == type && $0.localId == localId }) else {
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

        // Cancel out queued removals for the same people on this photo.
        var peopleToAdd = Set(incomingPayload.personLocalIds)
        operations.removeAll { operation in
            guard operation.type == .removePersonFromPhoto,
                  operation.localId == incoming.localId,
                  let payload = try? JSONDecoder().decode(RemovePersonFromPhotoPayload.self, from: operation.payload)
            else {
                return false
            }

            return peopleToAdd.remove(payload.personLocalId) != nil
        }

        guard !peopleToAdd.isEmpty else {
            return true
        }

        if let existingIndex = operations.lastIndex(where: { $0.type == .addPeopleToPhoto && $0.localId == incoming.localId }),
           let existingPayload = try? JSONDecoder().decode(AddPeopleToPhotoPayload.self, from: operations[existingIndex].payload) {
            var mergedPeople = Set(existingPayload.personLocalIds)
            mergedPeople.formUnion(peopleToAdd)
            let mergedPayload = AddPeopleToPhotoPayload(personLocalIds: Array(mergedPeople).sorted())

            guard let encodedPayload = try? JSONEncoder().encode(mergedPayload) else {
                return false
            }

            var mergedOperation = operations[existingIndex]
            mergedOperation = PendingOperation(
                id: mergedOperation.id,
                type: mergedOperation.type,
                localId: mergedOperation.localId,
                payload: encodedPayload,
                createdAt: mergedOperation.createdAt,
                retryCount: mergedOperation.retryCount,
                blockedCount: mergedOperation.blockedCount,
                dependsOnLocalId: mergedOperation.dependsOnLocalId
            )
            operations[existingIndex] = mergedOperation
            return true
        }

        guard peopleToAdd.count == incomingPayload.personLocalIds.count else {
            let adjustedPayload = AddPeopleToPhotoPayload(personLocalIds: Array(peopleToAdd).sorted())
            guard let encodedPayload = try? JSONEncoder().encode(adjustedPayload) else {
                return false
            }

            let adjustedOperation = PendingOperation(
                id: incoming.id,
                type: incoming.type,
                localId: incoming.localId,
                payload: encodedPayload,
                createdAt: incoming.createdAt,
                retryCount: incoming.retryCount,
                blockedCount: incoming.blockedCount,
                dependsOnLocalId: incoming.dependsOnLocalId
            )
            operations.append(adjustedOperation)
            return true
        }

        return false
    }

    private func mergeRemovePersonFromPhoto(_ incoming: PendingOperation) -> Bool {
        guard let incomingPayload = try? JSONDecoder().decode(RemovePersonFromPhotoPayload.self, from: incoming.payload) else {
            return false
        }

        // If a matching add is still queued, remove it and drop this operation.
        if let addIndex = operations.lastIndex(where: { $0.type == .addPeopleToPhoto && $0.localId == incoming.localId }),
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
                    let previous = operations[addIndex]
                    operations[addIndex] = PendingOperation(
                        id: previous.id,
                        type: previous.type,
                        localId: previous.localId,
                        payload: encodedPayload,
                        createdAt: previous.createdAt,
                        retryCount: previous.retryCount,
                        blockedCount: previous.blockedCount,
                        dependsOnLocalId: previous.dependsOnLocalId
                    )
                }
                return true
            }
        }

        // Replace any existing removal for the same person on the same photo.
        if let existingIndex = operations.lastIndex(where: { $0.type == .removePersonFromPhoto && $0.localId == incoming.localId }),
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
        do {
            let data = try JSONEncoder().encode(operations)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            AppLog.queue.error("Failed to save queue to storage: \(String(describing: error), privacy: .public)")
        }
    }
}
