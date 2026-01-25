import Foundation

// MARK: - Operation Types

enum SyncOperationType: String, Codable {
    case createPerson
    case createGrowthData
    case createMilestone
    case uploadPhoto
    case updateGrowthData
    case updateMilestone
    case deleteGrowthData
    case deleteMilestone
    case deletePhoto
}

// MARK: - Pending Operation

struct PendingOperation: Codable, Identifiable {
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

struct CreatePersonPayload: Codable {
    let name: String
    let personType: Int
    let gender: Int
    let birthdate: String
}

struct CreateGrowthDataPayload: Codable {
    let personLocalId: String
    let measurementType: String
    let value: Double
    let unit: String
    let measurementDate: String
}

struct CreateMilestonePayload: Codable {
    let personLocalId: String
    let description: String
    let category: String
    let milestoneDate: String
}

struct UploadPhotoPayload: Codable {
    let title: String
    let description: String
    let photoDate: String
    let taggedPersonLocalIds: [String]
}

struct UpdateGrowthDataPayload: Codable {
    let remoteId: Int
    let measurementType: String
    let value: Double
    let unit: String
    let measurementDate: String
}

struct UpdateMilestonePayload: Codable {
    let remoteId: Int
    let description: String
    let category: String
    let milestoneDate: String
}

struct DeletePayload: Codable {
    let remoteId: Int
}

// MARK: - SyncQueue Actor

actor SyncQueue {
    private static let storageKey = "com.familyportal.syncQueue"
    private static let maxRetries = 5

    private var operations: [PendingOperation] = []

    init() {
        loadFromStorage()
    }

    // MARK: - Queue Management

    func enqueue(_ operation: PendingOperation) {
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

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else {
            return
        }

        do {
            operations = try JSONDecoder().decode([PendingOperation].self, from: data)
        } catch {
            print("[SyncQueue] Failed to load from storage: \(error)")
            operations = []
        }
    }

    private func saveToStorage() {
        do {
            let data = try JSONEncoder().encode(operations)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            print("[SyncQueue] Failed to save to storage: \(error)")
        }
    }
}
