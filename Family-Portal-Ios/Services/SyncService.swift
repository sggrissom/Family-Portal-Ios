import Foundation
import SwiftData

@Observable
@MainActor
final class SyncService {
    let modelContext: ModelContext
    let apiClient: APIClient
    let networkMonitor: NetworkMonitor

    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var syncError: String?

    init(modelContext: ModelContext, apiClient: APIClient, networkMonitor: NetworkMonitor) {
        self.modelContext = modelContext
        self.apiClient = apiClient
        self.networkMonitor = networkMonitor
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

    // MARK: - Push: Person

    func addPerson(_ person: Person) async throws {
        let request = AddPersonRequestDTO(
            name: person.name,
            personType: personTypeToInt(person.type),
            gender: genderToInt(person.gender),
            birthdate: dateToAPIString(person.birthday ?? Date())
        )
        let response: AddPersonResponseDTO = try await apiClient.callRPC("AddPerson", payload: request)
        applyPersonDTO(response.person, to: person)
        try modelContext.save()
    }

    // MARK: - Push: GrowthData

    func addGrowthData(_ data: GrowthData, for person: Person) async throws {
        guard let personRemoteId = person.remoteId, let personId = Int(personRemoteId) else {
            throw SyncError.missingRemoteId("Person must be synced before adding growth data")
        }
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
    }

    func updateGrowthData(_ data: GrowthData) async throws {
        guard let remoteId = data.remoteId, let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("GrowthData must be synced before updating")
        }
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
    }

    func deleteGrowthData(_ data: GrowthData) async throws {
        guard let remoteId = data.remoteId, let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("GrowthData must be synced before deleting")
        }
        let request = DeleteRequestDTO(id: id)
        let _: SuccessResponseDTO = try await apiClient.callRPC("DeleteGrowthData", payload: request)
        modelContext.delete(data)
        try modelContext.save()
    }

    // MARK: - Push: Milestones

    func addMilestone(_ milestone: Milestone, for person: Person) async throws {
        guard let personRemoteId = person.remoteId, let personId = Int(personRemoteId) else {
            throw SyncError.missingRemoteId("Person must be synced before adding milestone")
        }
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
    }

    func updateMilestone(_ milestone: Milestone) async throws {
        guard let remoteId = milestone.remoteId, let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("Milestone must be synced before updating")
        }
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
    }

    func deleteMilestone(_ milestone: Milestone) async throws {
        guard let remoteId = milestone.remoteId, let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("Milestone must be synced before deleting")
        }
        let request = DeleteRequestDTO(id: id)
        let _: SuccessResponseDTO = try await apiClient.callRPC("DeleteMilestone", payload: request)
        modelContext.delete(milestone)
        try modelContext.save()
    }

    // MARK: - Push: Photos

    func deletePhoto(_ photo: Photo) async throws {
        guard let remoteId = photo.remoteId, let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("Photo must be synced before deleting")
        }
        let request = DeleteRequestDTO(id: id)
        let _: SuccessResponseDTO = try await apiClient.callRPC("DeletePhoto", payload: request)
        modelContext.delete(photo)
        try modelContext.save()
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
