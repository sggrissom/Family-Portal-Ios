import Foundation
import SwiftData

@Observable
@MainActor
final class SyncService {
    let modelContext: ModelContext
    let apiClient: APIClient
    let networkMonitor: NetworkMonitor
    let syncQueue: SyncQueue

    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var syncError: String?
    var pendingOperationCount: Int = 0

    init(modelContext: ModelContext, apiClient: APIClient, networkMonitor: NetworkMonitor) {
        self.modelContext = modelContext
        self.apiClient = apiClient
        self.networkMonitor = networkMonitor
        self.syncQueue = SyncQueue()

        Task {
            await updatePendingCount()
        }
    }

    // MARK: - Full Sync

    func performFullSync() async {
        await processQueue()
        await pullFamilyData()
    }

    // MARK: - Pull

    func pullFamilyData() async {
        guard networkMonitor.isConnected else { return }
        isSyncing = true
        syncError = nil

        do {
            struct EmptyPayload: Encodable {}
            let response: GetFamilyTimelineResponseDTO = try await apiClient.callRPC("GetFamilyTimeline", payload: EmptyPayload())

            var seenPersonIds = Set<String>()
            var seenGrowthDataIds = Set<String>()
            var seenMilestoneIds = Set<String>()
            var seenPhotoIds = Set<String>()

            for item in response.people {
                let personRemoteId = String(item.person.id)
                seenPersonIds.insert(personRemoteId)

                let person = findOrCreatePerson(remoteId: personRemoteId)
                applyPersonDTO(item.person, to: person)

                for growthDTO in item.growthData {
                    let gdRemoteId = String(growthDTO.id)
                    seenGrowthDataIds.insert(gdRemoteId)
                    let growthData = findOrCreateGrowthData(remoteId: gdRemoteId)
                    applyGrowthDataDTO(growthDTO, to: growthData)
                    growthData.person = person
                }

                for milestoneDTO in item.milestones {
                    let msRemoteId = String(milestoneDTO.id)
                    seenMilestoneIds.insert(msRemoteId)
                    let milestone = findOrCreateMilestone(remoteId: msRemoteId)
                    applyMilestoneDTO(milestoneDTO, to: milestone)
                    milestone.person = person
                }

                for imageDTO in item.photos {
                    let photoRemoteId = String(imageDTO.id)
                    seenPhotoIds.insert(photoRemoteId)
                    let photo = findOrCreatePhoto(remoteId: photoRemoteId)
                    applyPhotoDTO(imageDTO, to: photo)
                }
            }

            removeOrphans(Person.self, seenIds: seenPersonIds)
            removeOrphans(GrowthData.self, seenIds: seenGrowthDataIds)
            removeOrphans(Milestone.self, seenIds: seenMilestoneIds)
            removeOrphans(Photo.self, seenIds: seenPhotoIds)

            try modelContext.save()
            lastSyncDate = Date()
        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    // MARK: - Queue Processing

    func processQueue() async {
        guard networkMonitor.isConnected else { return }

        let syncedLocalIds = await fetchAllSyncedLocalIds()
        let operations = await syncQueue.readyOperations(syncedLocalIds: syncedLocalIds)

        for operation in operations {
            do {
                try await executeOperation(operation)
                await syncQueue.dequeue(operation.id)
            } catch {
                if isNetworkError(error) {
                    break
                }
                await syncQueue.markFailed(operation.id)
            }
        }

        await updatePendingCount()
    }

    private func executeOperation(_ operation: PendingOperation) async throws {
        switch operation.type {
        case .createPerson:
            try await executeCreatePerson(operation)
        case .createGrowthData:
            try await executeCreateGrowthData(operation)
        case .createMilestone:
            try await executeCreateMilestone(operation)
        case .uploadPhoto:
            try await executeUploadPhoto(operation)
        case .updateGrowthData:
            try await executeUpdateGrowthData(operation)
        case .updateMilestone:
            try await executeUpdateMilestone(operation)
        case .deleteGrowthData:
            try await executeDeleteGrowthData(operation)
        case .deleteMilestone:
            try await executeDeleteMilestone(operation)
        case .deletePhoto:
            try await executeDeletePhoto(operation)
        }
    }

    private func executeCreatePerson(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(CreatePersonPayload.self, from: operation.payload)

        guard let person = findPerson(byLocalId: operation.localId) else {
            return
        }

        let request = AddPersonRequestDTO(
            name: payload.name,
            personType: payload.personType,
            gender: payload.gender,
            birthdate: payload.birthdate
        )
        let response: AddPersonResponseDTO = try await apiClient.callRPC("AddPerson", payload: request)
        applyPersonDTO(response.person, to: person)
        try modelContext.save()
    }

    private func executeCreateGrowthData(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(CreateGrowthDataPayload.self, from: operation.payload)

        guard let growthData = findGrowthData(byLocalId: operation.localId),
              let person = findPerson(byLocalId: payload.personLocalId),
              let personRemoteId = person.remoteId,
              let personId = Int(personRemoteId) else {
            return
        }

        let request = AddGrowthDataRequestDTO(
            personId: personId,
            measurementType: payload.measurementType,
            value: payload.value,
            unit: payload.unit,
            inputType: "date",
            measurementDate: payload.measurementDate
        )
        let response: AddGrowthDataResponseDTO = try await apiClient.callRPC("AddGrowthData", payload: request)
        applyGrowthDataDTO(response.growthData, to: growthData)
        try modelContext.save()
    }

    private func executeCreateMilestone(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(CreateMilestonePayload.self, from: operation.payload)

        guard let milestone = findMilestone(byLocalId: operation.localId),
              let person = findPerson(byLocalId: payload.personLocalId),
              let personRemoteId = person.remoteId,
              let personId = Int(personRemoteId) else {
            return
        }

        let request = AddMilestoneRequestDTO(
            personId: personId,
            description: payload.description,
            category: payload.category,
            inputType: "date",
            milestoneDate: payload.milestoneDate
        )
        let response: AddMilestoneResponseDTO = try await apiClient.callRPC("AddMilestone", payload: request)
        applyMilestoneDTO(response.milestone, to: milestone)
        try modelContext.save()
    }

    private func executeUploadPhoto(_ operation: PendingOperation) async throws {
        // Photo upload requires image data which can't be easily queued
        // Skip for now - photos should be uploaded when online
    }

    private func executeUpdateGrowthData(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdateGrowthDataPayload.self, from: operation.payload)

        guard let growthData = findGrowthData(byLocalId: operation.localId) else {
            return
        }

        let request = UpdateGrowthDataRequestDTO(
            id: payload.remoteId,
            measurementType: payload.measurementType,
            value: payload.value,
            unit: payload.unit,
            inputType: "date",
            measurementDate: payload.measurementDate
        )
        let response: UpdateGrowthDataResponseDTO = try await apiClient.callRPC("UpdateGrowthData", payload: request)
        applyGrowthDataDTO(response.growthData, to: growthData)
        try modelContext.save()
    }

    private func executeUpdateMilestone(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdateMilestonePayload.self, from: operation.payload)

        guard let milestone = findMilestone(byLocalId: operation.localId) else {
            return
        }

        let request = UpdateMilestoneRequestDTO(
            id: payload.remoteId,
            description: payload.description,
            category: payload.category,
            inputType: "date",
            milestoneDate: payload.milestoneDate
        )
        let response: UpdateMilestoneResponseDTO = try await apiClient.callRPC("UpdateMilestone", payload: request)
        applyMilestoneDTO(response.milestone, to: milestone)
        try modelContext.save()
    }

    private func executeDeleteGrowthData(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(DeletePayload.self, from: operation.payload)

        do {
            let request = DeleteRequestDTO(id: payload.remoteId)
            let _: SuccessResponseDTO = try await apiClient.callRPC("DeleteGrowthData", payload: request)
        } catch let error as APIError {
            if case .server(let statusCode, _) = error, statusCode == 404 {
                return
            }
            throw error
        }
    }

    private func executeDeleteMilestone(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(DeletePayload.self, from: operation.payload)

        do {
            let request = DeleteRequestDTO(id: payload.remoteId)
            let _: SuccessResponseDTO = try await apiClient.callRPC("DeleteMilestone", payload: request)
        } catch let error as APIError {
            if case .server(let statusCode, _) = error, statusCode == 404 {
                return
            }
            throw error
        }
    }

    private func executeDeletePhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(DeletePayload.self, from: operation.payload)

        do {
            let request = DeleteRequestDTO(id: payload.remoteId)
            let _: SuccessResponseDTO = try await apiClient.callRPC("DeletePhoto", payload: request)
        } catch let error as APIError {
            if case .server(let statusCode, _) = error, statusCode == 404 {
                return
            }
            throw error
        }
    }

    // MARK: - Push: Person

    func addPerson(_ person: Person) async throws {
        let payload = CreatePersonPayload(
            name: person.name,
            personType: personTypeToInt(person.type),
            gender: genderToInt(person.gender),
            birthdate: dateToAPIString(person.birthday ?? Date())
        )

        guard networkMonitor.isConnected else {
            try await enqueueOperation(
                type: .createPerson,
                localId: person.id.uuidString,
                payload: payload,
                dependsOnLocalId: nil
            )
            return
        }

        do {
            let request = AddPersonRequestDTO(
                name: person.name,
                personType: personTypeToInt(person.type),
                gender: genderToInt(person.gender),
                birthdate: dateToAPIString(person.birthday ?? Date())
            )
            let response: AddPersonResponseDTO = try await apiClient.callRPC("AddPerson", payload: request)
            applyPersonDTO(response.person, to: person)
            try modelContext.save()
        } catch {
            if isNetworkError(error) {
                try await enqueueOperation(
                    type: .createPerson,
                    localId: person.id.uuidString,
                    payload: payload,
                    dependsOnLocalId: nil
                )
            } else {
                throw error
            }
        }
    }

    // MARK: - Push: GrowthData

    func addGrowthData(_ data: GrowthData, for person: Person) async throws {
        let payload = CreateGrowthDataPayload(
            personLocalId: person.id.uuidString,
            measurementType: measurementTypeToString(data.measurementType),
            value: data.value,
            unit: unitToString(data.unit),
            measurementDate: dateToAPIString(data.date)
        )

        let dependsOnLocalId = person.remoteId == nil ? person.id.uuidString : nil

        guard networkMonitor.isConnected else {
            try await enqueueOperation(
                type: .createGrowthData,
                localId: data.id.uuidString,
                payload: payload,
                dependsOnLocalId: dependsOnLocalId
            )
            return
        }

        guard let personRemoteId = person.remoteId, let personId = Int(personRemoteId) else {
            try await enqueueOperation(
                type: .createGrowthData,
                localId: data.id.uuidString,
                payload: payload,
                dependsOnLocalId: person.id.uuidString
            )
            return
        }

        do {
            let request = AddGrowthDataRequestDTO(
                personId: personId,
                measurementType: measurementTypeToString(data.measurementType),
                value: data.value,
                unit: unitToString(data.unit),
                inputType: "date",
                measurementDate: dateToAPIString(data.date)
            )
            let response: AddGrowthDataResponseDTO = try await apiClient.callRPC("AddGrowthData", payload: request)
            applyGrowthDataDTO(response.growthData, to: data)
            try modelContext.save()
        } catch {
            if isNetworkError(error) {
                try await enqueueOperation(
                    type: .createGrowthData,
                    localId: data.id.uuidString,
                    payload: payload,
                    dependsOnLocalId: dependsOnLocalId
                )
            } else {
                throw error
            }
        }
    }

    func updateGrowthData(_ data: GrowthData) async throws {
        guard let remoteId = data.remoteId, let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("GrowthData must be synced before updating")
        }

        let payload = UpdateGrowthDataPayload(
            remoteId: id,
            measurementType: measurementTypeToString(data.measurementType),
            value: data.value,
            unit: unitToString(data.unit),
            measurementDate: dateToAPIString(data.date)
        )

        guard networkMonitor.isConnected else {
            try await enqueueOperation(
                type: .updateGrowthData,
                localId: data.id.uuidString,
                payload: payload,
                dependsOnLocalId: nil
            )
            return
        }

        do {
            let request = UpdateGrowthDataRequestDTO(
                id: id,
                measurementType: measurementTypeToString(data.measurementType),
                value: data.value,
                unit: unitToString(data.unit),
                inputType: "date",
                measurementDate: dateToAPIString(data.date)
            )
            let response: UpdateGrowthDataResponseDTO = try await apiClient.callRPC("UpdateGrowthData", payload: request)
            applyGrowthDataDTO(response.growthData, to: data)
            try modelContext.save()
        } catch {
            if isNetworkError(error) {
                try await enqueueOperation(
                    type: .updateGrowthData,
                    localId: data.id.uuidString,
                    payload: payload,
                    dependsOnLocalId: nil
                )
            } else {
                throw error
            }
        }
    }

    func deleteGrowthData(_ data: GrowthData) async throws {
        guard let remoteId = data.remoteId, let id = Int(remoteId) else {
            modelContext.delete(data)
            try modelContext.save()
            return
        }

        let payload = DeletePayload(remoteId: id)

        modelContext.delete(data)
        try modelContext.save()

        guard networkMonitor.isConnected else {
            try await enqueueOperation(
                type: .deleteGrowthData,
                localId: data.id.uuidString,
                payload: payload,
                dependsOnLocalId: nil
            )
            return
        }

        do {
            let request = DeleteRequestDTO(id: id)
            let _: SuccessResponseDTO = try await apiClient.callRPC("DeleteGrowthData", payload: request)
        } catch {
            if isNetworkError(error) {
                try await enqueueOperation(
                    type: .deleteGrowthData,
                    localId: data.id.uuidString,
                    payload: payload,
                    dependsOnLocalId: nil
                )
            } else {
                throw error
            }
        }
    }

    // MARK: - Push: Milestones

    func addMilestone(_ milestone: Milestone, for person: Person) async throws {
        let payload = CreateMilestonePayload(
            personLocalId: person.id.uuidString,
            description: milestone.descriptionText,
            category: milestone.category.rawValue,
            milestoneDate: dateToAPIString(milestone.date)
        )

        let dependsOnLocalId = person.remoteId == nil ? person.id.uuidString : nil

        guard networkMonitor.isConnected else {
            try await enqueueOperation(
                type: .createMilestone,
                localId: milestone.id.uuidString,
                payload: payload,
                dependsOnLocalId: dependsOnLocalId
            )
            return
        }

        guard let personRemoteId = person.remoteId, let personId = Int(personRemoteId) else {
            try await enqueueOperation(
                type: .createMilestone,
                localId: milestone.id.uuidString,
                payload: payload,
                dependsOnLocalId: person.id.uuidString
            )
            return
        }

        do {
            let request = AddMilestoneRequestDTO(
                personId: personId,
                description: milestone.descriptionText,
                category: milestone.category.rawValue,
                inputType: "date",
                milestoneDate: dateToAPIString(milestone.date)
            )
            let response: AddMilestoneResponseDTO = try await apiClient.callRPC("AddMilestone", payload: request)
            applyMilestoneDTO(response.milestone, to: milestone)
            try modelContext.save()
        } catch {
            if isNetworkError(error) {
                try await enqueueOperation(
                    type: .createMilestone,
                    localId: milestone.id.uuidString,
                    payload: payload,
                    dependsOnLocalId: dependsOnLocalId
                )
            } else {
                throw error
            }
        }
    }

    func updateMilestone(_ milestone: Milestone) async throws {
        guard let remoteId = milestone.remoteId, let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("Milestone must be synced before updating")
        }

        let payload = UpdateMilestonePayload(
            remoteId: id,
            description: milestone.descriptionText,
            category: milestone.category.rawValue,
            milestoneDate: dateToAPIString(milestone.date)
        )

        guard networkMonitor.isConnected else {
            try await enqueueOperation(
                type: .updateMilestone,
                localId: milestone.id.uuidString,
                payload: payload,
                dependsOnLocalId: nil
            )
            return
        }

        do {
            let request = UpdateMilestoneRequestDTO(
                id: id,
                description: milestone.descriptionText,
                category: milestone.category.rawValue,
                inputType: "date",
                milestoneDate: dateToAPIString(milestone.date)
            )
            let response: UpdateMilestoneResponseDTO = try await apiClient.callRPC("UpdateMilestone", payload: request)
            applyMilestoneDTO(response.milestone, to: milestone)
            try modelContext.save()
        } catch {
            if isNetworkError(error) {
                try await enqueueOperation(
                    type: .updateMilestone,
                    localId: milestone.id.uuidString,
                    payload: payload,
                    dependsOnLocalId: nil
                )
            } else {
                throw error
            }
        }
    }

    func deleteMilestone(_ milestone: Milestone) async throws {
        guard let remoteId = milestone.remoteId, let id = Int(remoteId) else {
            modelContext.delete(milestone)
            try modelContext.save()
            return
        }

        let payload = DeletePayload(remoteId: id)

        modelContext.delete(milestone)
        try modelContext.save()

        guard networkMonitor.isConnected else {
            try await enqueueOperation(
                type: .deleteMilestone,
                localId: milestone.id.uuidString,
                payload: payload,
                dependsOnLocalId: nil
            )
            return
        }

        do {
            let request = DeleteRequestDTO(id: id)
            let _: SuccessResponseDTO = try await apiClient.callRPC("DeleteMilestone", payload: request)
        } catch {
            if isNetworkError(error) {
                try await enqueueOperation(
                    type: .deleteMilestone,
                    localId: milestone.id.uuidString,
                    payload: payload,
                    dependsOnLocalId: nil
                )
            } else {
                throw error
            }
        }
    }

    // MARK: - Push: Photos

    func deletePhoto(_ photo: Photo) async throws {
        guard let remoteId = photo.remoteId, let id = Int(remoteId) else {
            modelContext.delete(photo)
            try modelContext.save()
            return
        }

        let payload = DeletePayload(remoteId: id)

        modelContext.delete(photo)
        try modelContext.save()

        guard networkMonitor.isConnected else {
            try await enqueueOperation(
                type: .deletePhoto,
                localId: photo.id.uuidString,
                payload: payload,
                dependsOnLocalId: nil
            )
            return
        }

        do {
            let request = DeleteRequestDTO(id: id)
            let _: SuccessResponseDTO = try await apiClient.callRPC("DeletePhoto", payload: request)
        } catch {
            if isNetworkError(error) {
                try await enqueueOperation(
                    type: .deletePhoto,
                    localId: photo.id.uuidString,
                    payload: payload,
                    dependsOnLocalId: nil
                )
            } else {
                throw error
            }
        }
    }

    func addPeopleToPhoto(_ photo: Photo, people: [Person]) async throws {
        guard let photoRemoteId = photo.remoteId, let photoId = Int(photoRemoteId) else {
            throw SyncError.missingRemoteId("Photo must be synced before adding people")
        }
        let personIds: [Int] = try people.map { person in
            guard let rid = person.remoteId, let id = Int(rid) else {
                throw SyncError.missingRemoteId("All people must be synced before adding to photo")
            }
            return id
        }
        let request = AddPeopleToPhotoRequestDTO(photoId: photoId, personIds: personIds)
        let _: SuccessResponseDTO = try await apiClient.callRPC("AddPeopleToPhoto", payload: request)
        try modelContext.save()
    }

    func removePersonFromPhoto(_ photo: Photo, person: Person) async throws {
        guard let photoRemoteId = photo.remoteId, let photoId = Int(photoRemoteId) else {
            throw SyncError.missingRemoteId("Photo must be synced before removing person")
        }
        guard let personRemoteId = person.remoteId, let personId = Int(personRemoteId) else {
            throw SyncError.missingRemoteId("Person must be synced before removing from photo")
        }
        let request = RemovePersonFromPhotoRequestDTO(photoId: photoId, personId: personId)
        let _: SuccessResponseDTO = try await apiClient.callRPC("RemovePersonFromPhoto", payload: request)
        try modelContext.save()
    }

    // MARK: - Queue Helpers

    private func enqueueOperation<T: Encodable>(
        type: SyncOperationType,
        localId: String,
        payload: T,
        dependsOnLocalId: String?
    ) async throws {
        let payloadData = try JSONEncoder().encode(payload)
        let operation = PendingOperation(
            type: type,
            localId: localId,
            payload: payloadData,
            dependsOnLocalId: dependsOnLocalId
        )
        await syncQueue.enqueue(operation)
        await updatePendingCount()
    }

    private func isNetworkError(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .network:
                return true
            default:
                return false
            }
        }

        let nsError = error as NSError
        let networkErrorCodes = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost
        ]
        return networkErrorCodes.contains(nsError.code)
    }

    private func updatePendingCount() async {
        pendingOperationCount = await syncQueue.count()
    }

    private func fetchAllSyncedLocalIds() async -> Set<String> {
        var syncedIds = Set<String>()

        let personDescriptor = FetchDescriptor<Person>()
        if let persons = try? modelContext.fetch(personDescriptor) {
            for person in persons where person.remoteId != nil {
                syncedIds.insert(person.id.uuidString)
            }
        }

        return syncedIds
    }

    // MARK: - Lookup Helpers

    private func findPerson(byLocalId localId: String) -> Person? {
        guard let uuid = UUID(uuidString: localId) else { return nil }
        var descriptor = FetchDescriptor<Person>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findGrowthData(byLocalId localId: String) -> GrowthData? {
        guard let uuid = UUID(uuidString: localId) else { return nil }
        var descriptor = FetchDescriptor<GrowthData>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findMilestone(byLocalId localId: String) -> Milestone? {
        guard let uuid = UUID(uuidString: localId) else { return nil }
        var descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Upsert Helpers

    private func findOrCreatePerson(remoteId: String) -> Person {
        var descriptor = FetchDescriptor<Person>(
            predicate: #Predicate { $0.remoteId == remoteId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let person = Person(name: "", type: .child, gender: .other)
        person.remoteId = remoteId
        modelContext.insert(person)
        return person
    }

    private func findOrCreateGrowthData(remoteId: String) -> GrowthData {
        var descriptor = FetchDescriptor<GrowthData>(
            predicate: #Predicate { $0.remoteId == remoteId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let data = GrowthData(measurementType: .height, value: 0, unit: .centimeters, date: Date())
        data.remoteId = remoteId
        modelContext.insert(data)
        return data
    }

    private func findOrCreateMilestone(remoteId: String) -> Milestone {
        var descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.remoteId == remoteId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let milestone = Milestone(descriptionText: "", category: .other, date: Date())
        milestone.remoteId = remoteId
        modelContext.insert(milestone)
        return milestone
    }

    private func findOrCreatePhoto(remoteId: String) -> Photo {
        var descriptor = FetchDescriptor<Photo>(
            predicate: #Predicate { $0.remoteId == remoteId }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let photo = Photo(title: "", descriptionText: "", photoDate: Date())
        photo.remoteId = remoteId
        modelContext.insert(photo)
        return photo
    }

    // MARK: - Orphan Removal

    private func removeOrphans<T: PersistentModel>(_ type: T.Type, seenIds: Set<String>) {
        let descriptor = FetchDescriptor<T>()
        guard let allModels = try? modelContext.fetch(descriptor) else { return }
        for model in allModels {
            guard let remoteId = (model as? RemoteIdentifiable)?.remoteId else { continue }
            if !seenIds.contains(remoteId) {
                modelContext.delete(model)
            }
        }
    }
}

// MARK: - Supporting Types

enum SyncError: LocalizedError {
    case missingRemoteId(String)

    var errorDescription: String? {
        switch self {
        case .missingRemoteId(let message):
            return message
        }
    }
}

private protocol RemoteIdentifiable {
    var remoteId: String? { get }
}

extension Person: RemoteIdentifiable {}
extension GrowthData: RemoteIdentifiable {}
extension Milestone: RemoteIdentifiable {}
extension Photo: RemoteIdentifiable {}
