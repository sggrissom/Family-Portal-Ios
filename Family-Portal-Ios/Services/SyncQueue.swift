import Foundation

// MARK: - Operation Types

nonisolated enum SyncOperationType: String, Codable, Sendable {
    case createPerson
    case updatePerson
    case createGrowthData
    case createMilestone
    case uploadPhoto
    case addPeopleToPhoto
    case removePersonFromPhoto
    case updateGrowthData
    case updateMilestone
    case updatePhoto
    case deleteGrowthData
    case deleteMilestone
    case deletePhoto
}

// MARK: - Pending Operation

nonisolated struct PendingOperation: Codable, Identifiable, Sendable {
    let id: UUID
    let type: SyncOperationType
    let localId: String
    let payload: Data
    let createdAt: Date
    var retryCount: Int
    let dependsOnLocalId: String?

    init(
        id: UUID = UUID(),
        type: SyncOperationType,
        localId: String,
        payload: Data,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        dependsOnLocalId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.localId = localId
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.dependsOnLocalId = dependsOnLocalId
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
    /// Optional so operations queued before milestone photos existed still
    /// decode. nil and [] mean the same thing on create.
    let photoIds: [Int]?
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
    /// Optional both for queue compatibility and because the backend reads nil
    /// as "leave the existing links alone", while [] clears them.
    let photoIds: [Int]?
}

nonisolated struct UpdatePhotoPayload: Codable, Sendable {
    let title: String
    let description: String
    let photoDate: String
}

nonisolated struct DeletePayload: Codable, Sendable {
    let remoteId: Int
}

// MARK: - SyncQueue Actor

actor SyncQueue {
    private static let storageKey = "com.familyrecord.syncQueue"
    private static let maxRetries = 5

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
            print("[SyncQueue] Failed to load from storage: \(error)")
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
        return operations.filter { op in
            guard let dependsOn = op.dependsOnLocalId else {
                return true
            }
            return syncedLocalIds.contains(dependsOn)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func markFailed(_ operationId: UUID) {
        guard let index = operations.firstIndex(where: { $0.id == operationId }) else {
            return
        }

        var operation = operations[index]
        operation.retryCount += 1

        if operation.retryCount >= Self.maxRetries {
            print("[SyncQueue] Operation \(operationId) exceeded max retries, discarding")
            operations.remove(at: index)
        } else {
            operations[index] = operation
        }

        saveToStorage()
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
        case .updatePerson, .updateGrowthData, .updateMilestone, .updatePhoto:
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
            print("[SyncQueue] Failed to save to storage: \(error)")
        }
    }
}
