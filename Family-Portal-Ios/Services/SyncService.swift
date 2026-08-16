import Foundation
import OSLog
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

    /// Set when the queue gives up on an operation for good. Kept apart from
    /// `syncError`, which every pull clears: a connection that came back fixes a
    /// sync error, but nothing brings back a change that was dropped, so this
    /// stays until the user acknowledges it.
    private(set) var discardedChangeWarning: String?

    /// `syncQueue` is injectable so tests can drive `processQueue` against a
    /// scratch queue instead of the shared one in `UserDefaults.standard`.
    init(
        modelContext: ModelContext,
        apiClient: APIClient,
        networkMonitor: NetworkMonitor,
        syncQueue: SyncQueue = SyncQueue()
    ) {
        self.modelContext = modelContext
        self.apiClient = apiClient
        self.networkMonitor = networkMonitor
        self.syncQueue = syncQueue

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
            let timelineResponse: GetFamilyTimelineResponseDTO = try await apiClient.callRPC(
                .getFamilyTimeline,
                payload: EmptyPayload()
            )
            let photoResponse: ListFamilyPhotosResponseDTO = try await apiClient.callRPC(
                .listFamilyPhotos,
                payload: EmptyPayload()
            )

            var seenPersonIds = Set<String>()
            var seenGrowthDataIds = Set<String>()
            var seenMilestoneIds = Set<String>()
            var seenPhotoIds = Set<String>()

            for item in timelineResponse.people {
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

            for photoWithPeople in photoResponse.photos {
                let photoRemoteId = String(photoWithPeople.image.id)
                seenPhotoIds.insert(photoRemoteId)
                let photo = findOrCreatePhoto(remoteId: photoRemoteId)
                applyPhotoDTO(photoWithPeople.image, to: photo)
                let taggedPeople = photoWithPeople.people.map { personDTO in
                    let personRemoteId = String(personDTO.id)
                    let person = findOrCreatePerson(remoteId: personRemoteId)
                    applyPersonDTO(personDTO, to: person)
                    return person
                }
                photo.taggedPeople = taggedPeople
            }

            removeOrphans(Person.self, seenIds: seenPersonIds)
            removeOrphans(GrowthData.self, seenIds: seenGrowthDataIds)
            removeOrphans(Milestone.self, seenIds: seenMilestoneIds)
            removeOrphans(Photo.self, seenIds: seenPhotoIds)

            try modelContext.save()
            lastSyncDate = Date()
        } catch {
            AppLog.sync.error("Pull failed: \(String(describing: error), privacy: .public)")
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    // MARK: - Queue Processing

    func processQueue() async {
        guard networkMonitor.isConnected else { return }

        let syncedLocalIds = await fetchAllSyncedLocalIds()
        let operations = await syncQueue.readyOperations(syncedLocalIds: syncedLocalIds)
        var discarded: [PendingOperation] = []
        var accountedFor = Set<UUID>()
        var wentOffline = false

        for operation in operations {
            do {
                try await executeOperation(operation)
                await syncQueue.dequeue(operation.id)
            } catch {
                if isNetworkError(error) {
                    wentOffline = true
                    break
                }
                if case SyncError.missingRemoteId = error {
                    // Nothing was sent, so this is not a retry — but it is a run
                    // this operation could not use, and an operation waiting on a
                    // parent whose own create was discarded would otherwise wait
                    // for the life of the install.
                    accountedFor.insert(operation.id)
                    if let dropped = await syncQueue.markBlocked(operation.id) {
                        discarded.append(dropped)
                    }
                    continue
                }
                AppLog.sync.error(
                    "\(operation.type.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                )
                accountedFor.insert(operation.id)
                if let dropped = await syncQueue.markFailed(operation.id) {
                    discarded.append(dropped)
                }
            }
        }

        // Operations the dependency gate held back never reached the loop above,
        // which is exactly why they need counting here: they are the ones that
        // can sit in the queue indefinitely without anything ever noticing. The
        // synced set is re-read because a parent that succeeded moments ago in
        // this very run unblocks its children, and the snapshot taken at the top
        // predates that. A run cut short by the network charges nobody: being
        // offline must not spend an operation's allowance.
        if !wentOffline {
            let syncedNow = await fetchAllSyncedLocalIds()
            let blocked = await syncQueue.blockedOperations(syncedLocalIds: syncedNow)
            for operation in blocked where !accountedFor.contains(operation.id) {
                if let dropped = await syncQueue.markBlocked(operation.id) {
                    discarded.append(dropped)
                }
            }
        }

        // Losing an operation is the one sync outcome the user cannot infer from
        // the pending count going down, so it gets said out loud.
        if !discarded.isEmpty {
            discardedChangeWarning = Self.discardedChangeMessage(for: discarded)
        }

        await updatePendingCount()
    }

    func acknowledgeDiscardedChanges() {
        discardedChangeWarning = nil
    }

    private static func discardedChangeMessage(for operations: [PendingOperation]) -> String {
        if operations.count == 1, let only = operations.first {
            return "A change to \(only.type.subjectDescription) couldn't be saved to the server and was dropped."
        }
        return "\(operations.count) changes couldn't be saved to the server and were dropped."
    }

    private func executeOperation(_ operation: PendingOperation) async throws {
        switch operation.type {
        case .createPerson:
            try await executeCreatePerson(operation)
        case .updatePerson:
            try await executeUpdatePerson(operation)
        case .setProfilePhoto:
            try await executeSetProfilePhoto(operation)
        case .createGrowthData:
            try await executeCreateGrowthData(operation)
        case .createMilestone:
            try await executeCreateMilestone(operation)
        case .uploadPhoto:
            try await executeUploadPhoto(operation)
        case .addPeopleToPhoto:
            try await executeAddPeopleToPhoto(operation)
        case .removePersonFromPhoto:
            try await executeRemovePersonFromPhoto(operation)
        case .updateGrowthData:
            try await executeUpdateGrowthData(operation)
        case .updateMilestone:
            try await executeUpdateMilestone(operation)
        case .updatePhoto:
            try await executeUpdatePhoto(operation)
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
        let response: AddPersonResponseDTO = try await apiClient.callRPC(.addPerson, payload: request)
        applyPersonDTO(response.person, to: person)
        try modelContext.save()
    }

    private func executeUpdatePerson(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdatePersonPayload.self, from: operation.payload)

        guard let person = findPerson(byLocalId: operation.localId),
              let remoteId = person.remoteId,
              let personId = Int(remoteId) else {
            throw SyncError.missingRemoteId("Person must be synced before updating")
        }

        let request = UpdatePersonRequestDTO(
            id: personId,
            name: payload.name,
            personType: payload.personType,
            gender: payload.gender,
            birthdate: payload.birthdate
        )
        let response: UpdatePersonResponseDTO = try await apiClient.callRPC(.updatePerson, payload: request)
        applyPersonDTO(response.person, to: person)
        try modelContext.save()
    }

    private func executeSetProfilePhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(SetProfilePhotoPayload.self, from: operation.payload)

        // Either record being gone locally makes the choice moot; either one
        // merely lacking a remote id makes it blocked — the same split as the
        // create operations.
        guard let person = findPerson(byLocalId: operation.localId),
              let photo = findPhoto(byLocalId: payload.photoLocalId) else {
            return
        }

        guard let personRemoteId = person.remoteId, let personId = Int(personRemoteId) else {
            throw SyncError.missingRemoteId("Person must be synced before setting a profile photo")
        }

        guard let photoRemoteId = photo.remoteId, let photoId = Int(photoRemoteId) else {
            throw SyncError.missingRemoteId("Photo must be uploaded before it can be a profile photo")
        }

        let request = SetProfilePhotoRequestDTO(
            personId: personId,
            photoId: photoId,
            cropX: payload.cropX,
            cropY: payload.cropY,
            cropScale: payload.cropScale
        )
        let response: SetProfilePhotoResponseDTO = try await apiClient.callRPC(.setProfilePhoto, payload: request)
        applyPersonDTO(response.person, to: person)
        try modelContext.save()
    }

    private func executeCreateGrowthData(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(CreateGrowthDataPayload.self, from: operation.payload)

        // Three outcomes that used to be one `return`. The first two are moot
        // work — the record or its person was deleted locally — and dropping the
        // operation is right. The third is not: a person who simply has not
        // synced yet needs this operation kept, because `return` dequeues it as
        // though it had succeeded and the measurement then sits on the device
        // forever with no remote id. `missingRemoteId` is retried next pass,
        // by which time the person's own create has assigned one.
        guard let growthData = findGrowthData(byLocalId: operation.localId) else {
            return
        }

        guard let person = findPerson(byLocalId: payload.personLocalId) else {
            return
        }

        guard let personRemoteId = person.remoteId,
              let personId = Int(personRemoteId) else {
            throw SyncError.missingRemoteId("Person must be synced before adding measurements")
        }

        let request = AddGrowthDataRequestDTO(
            personId: personId,
            measurementType: payload.measurementType,
            value: payload.value,
            unit: payload.unit,
            inputType: "date",
            measurementDate: payload.measurementDate
        )
        let response: AddGrowthDataResponseDTO = try await apiClient.callRPC(.addGrowthData, payload: request)
        applyGrowthDataDTO(response.growthData, to: growthData)
        try modelContext.save()
    }

    private func executeCreateMilestone(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(CreateMilestonePayload.self, from: operation.payload)

        // Same three-way split as `executeCreateGrowthData`.
        guard let milestone = findMilestone(byLocalId: operation.localId) else {
            return
        }

        guard let person = findPerson(byLocalId: payload.personLocalId) else {
            return
        }

        guard let personRemoteId = person.remoteId,
              let personId = Int(personRemoteId) else {
            throw SyncError.missingRemoteId("Person must be synced before adding milestones")
        }

        let request = AddMilestoneRequestDTO(
            personId: personId,
            description: payload.description,
            category: payload.category,
            inputType: "date",
            milestoneDate: payload.milestoneDate,
            photoIds: try resolvePhotoRemoteIds(payload.photoLocalIds)
        )
        let response: AddMilestoneResponseDTO = try await apiClient.callRPC(.addMilestone, payload: request)
        applyMilestoneDTO(response.milestone, to: milestone)
        try modelContext.save()
    }

    private func executeUploadPhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UploadPhotoPayload.self, from: operation.payload)

        // Both misses mean the work is already moot rather than blocked: the
        // photo was deleted locally, or a previous run of this operation
        // uploaded it and cleared the bytes below. Dropping the operation is
        // right in either case.
        guard let photo = findPhoto(byLocalId: operation.localId),
              let imageData = photo.imageData else {
            return
        }

        let personIds = try payload.taggedPersonLocalIds.compactMap { localId -> Int? in
            guard let person = findPerson(byLocalId: localId) else {
                return nil
            }
            guard let remoteId = person.remoteId, let id = Int(remoteId) else {
                throw SyncError.missingRemoteId("Tagged people must be synced before uploading photo")
            }
            return id
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let photoDate = formatter.date(from: payload.photoDate) ?? photo.photoDate

        let response = try await PhotoSyncService(apiClient: apiClient).uploadPhoto(
            imageData: imageData,
            title: payload.title,
            description: payload.description,
            photoDate: photoDate,
            personIds: personIds
        )
        applyPhotoDTO(response, to: photo)

        // The server holds the bytes now. Keeping the local copy stored a second
        // full-resolution image for every photo ever taken in the app, in a
        // store that never shrank, and made the photo permanently exempt from
        // `removeOrphans` — so a photo deleted elsewhere never left the device.
        // Display falls back to `RemotePhotoView` on the `remoteId` just set.
        photo.imageData = nil

        try modelContext.save()
    }

    private func executeAddPeopleToPhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(AddPeopleToPhotoPayload.self, from: operation.payload)

        guard let photo = findPhoto(byLocalId: operation.localId),
              let photoRemoteId = photo.remoteId,
              let photoId = Int(photoRemoteId) else {
            throw SyncError.missingRemoteId("Photo must be synced before adding people")
        }

        let personIds = try payload.personLocalIds.map { localId -> Int in
            guard let person = findPerson(byLocalId: localId),
                  let remoteId = person.remoteId,
                  let id = Int(remoteId) else {
                throw SyncError.missingRemoteId("All people must be synced before adding to photo")
            }
            return id
        }

        let request = AddPeopleToPhotoRequestDTO(photoId: photoId, personIds: personIds)
        let _: SuccessResponseDTO = try await apiClient.callRPC(.addPeopleToPhoto, payload: request)
        try modelContext.save()
    }

    private func executeRemovePersonFromPhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(RemovePersonFromPhotoPayload.self, from: operation.payload)

        guard let photo = findPhoto(byLocalId: operation.localId),
              let photoRemoteId = photo.remoteId,
              let photoId = Int(photoRemoteId) else {
            throw SyncError.missingRemoteId("Photo must be synced before removing person")
        }

        guard let person = findPerson(byLocalId: payload.personLocalId),
              let personRemoteId = person.remoteId,
              let personId = Int(personRemoteId) else {
            throw SyncError.missingRemoteId("Person must be synced before removing from photo")
        }

        let request = RemovePersonFromPhotoRequestDTO(photoId: photoId, personId: personId)
        let _: SuccessResponseDTO = try await apiClient.callRPC(.removePersonFromPhoto, payload: request)
        try modelContext.save()
    }

    private func executeUpdateGrowthData(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdateGrowthDataPayload.self, from: operation.payload)

        guard let growthData = findGrowthData(byLocalId: operation.localId),
              let remoteId = growthData.remoteId,
              let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("GrowthData must be synced before updating")
        }

        let request = UpdateGrowthDataRequestDTO(
            id: id,
            measurementType: payload.measurementType,
            value: payload.value,
            unit: payload.unit,
            inputType: "date",
            measurementDate: payload.measurementDate
        )
        let response: UpdateGrowthDataResponseDTO = try await apiClient.callRPC(.updateGrowthData, payload: request)
        applyGrowthDataDTO(response.growthData, to: growthData)
        try modelContext.save()
    }

    private func executeUpdateMilestone(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdateMilestonePayload.self, from: operation.payload)

        guard let milestone = findMilestone(byLocalId: operation.localId),
              let remoteId = milestone.remoteId,
              let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("Milestone must be synced before updating")
        }

        let request = UpdateMilestoneRequestDTO(
            id: id,
            description: payload.description,
            category: payload.category,
            inputType: "date",
            milestoneDate: payload.milestoneDate,
            photoIds: try resolvePhotoRemoteIds(payload.photoLocalIds)
        )
        let response: UpdateMilestoneResponseDTO = try await apiClient.callRPC(.updateMilestone, payload: request)
        applyMilestoneDTO(response.milestone, to: milestone)
        try modelContext.save()
    }

    private func executeUpdatePhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdatePhotoPayload.self, from: operation.payload)

        guard let photo = findPhoto(byLocalId: operation.localId),
              let remoteId = photo.remoteId,
              let id = Int(remoteId) else {
            throw SyncError.missingRemoteId("Photo must be uploaded before updating")
        }

        let request = UpdatePhotoRequestDTO(
            id: id,
            title: payload.title,
            description: payload.description,
            inputType: "date",
            photoDate: payload.photoDate
        )
        let response: UpdatePhotoResponseDTO = try await apiClient.callRPC(.updatePhoto, payload: request)
        applyPhotoDTO(response.image, to: photo)
        try modelContext.save()
    }

    private func executeDeleteGrowthData(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(DeletePayload.self, from: operation.payload)

        do {
            let request = DeleteRequestDTO(id: payload.remoteId)
            let _: SuccessResponseDTO = try await apiClient.callRPC(.deleteGrowthData, payload: request)
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
            let _: SuccessResponseDTO = try await apiClient.callRPC(.deleteMilestone, payload: request)
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
            let _: SuccessResponseDTO = try await apiClient.callRPC(.deletePhoto, payload: request)
        } catch let error as APIError {
            if case .server(let statusCode, _) = error, statusCode == 404 {
                return
            }
            throw error
        }
    }

    // MARK: - Push: Person

    func addPerson(_ person: Person) async throws {
        // Substituting `Date()` here recorded today as the birthday of anyone
        // added without one, and the value came straight back on the next pull
        // indistinguishable from a real date. The server requires a birthdate
        // either way (validateAddPersonRequest in backend/person.go).
        guard let birthday = person.birthday else {
            throw SyncError.missingBirthday
        }

        let payload = CreatePersonPayload(
            name: person.name,
            personType: personTypeToInt(person.type),
            gender: genderToInt(person.gender),
            birthdate: dateToAPIString(birthday)
        )

        try await enqueueOperation(
            type: .createPerson,
            localId: person.id.uuidString,
            payload: payload,
            dependsOnLocalId: nil
        )
    }

    func updatePerson(_ person: Person) async throws {
        guard let birthday = person.birthday else {
            throw SyncError.missingBirthday
        }

        let payload = UpdatePersonPayload(
            name: person.name,
            personType: personTypeToInt(person.type),
            gender: genderToInt(person.gender),
            birthdate: dateToAPIString(birthday)
        )

        let dependsOnLocalId = person.remoteId == nil ? person.id.uuidString : nil

        try await enqueueOperation(
            type: .updatePerson,
            localId: person.id.uuidString,
            payload: payload,
            dependsOnLocalId: dependsOnLocalId
        )
    }

    /// Points a person's avatar at one of the photos they are tagged in.
    ///
    /// The tag is a server-side precondition, not a UI nicety: `SetProfilePhoto`
    /// (backend/person.go) rejects a photo the person is not associated with,
    /// and a rejection here costs the operation a retry and eventually discards
    /// it. Refusing up front turns that into an error the user sees at the tap.
    func setProfilePhoto(_ photo: Photo, for person: Person) async throws {
        guard photo.taggedPeople.contains(where: { $0.id == person.id }) else {
            throw SyncError.personNotInPhoto
        }

        let photoRemoteId = photo.remoteId.flatMap(Int.init)

        // Re-picking the photo a person already uses keeps the crop chosen for
        // it — cropping is a web-only editor — instead of snapping the framing
        // back to centre. Any other photo starts centred at 1×.
        let keepsExistingCrop = photoRemoteId != nil && photoRemoteId == person.profilePhotoId
        let cropX = keepsExistingCrop ? (person.profileCropX ?? 50) : 50
        let cropY = keepsExistingCrop ? (person.profileCropY ?? 50) : 50
        let cropScale = keepsExistingCrop ? (person.profileCropScale ?? 1) : 1

        let payload = SetProfilePhotoPayload(
            photoLocalId: photo.id.uuidString,
            cropX: cropX,
            cropY: cropY,
            cropScale: cropScale
        )

        // Optimistic only once the photo has an id the avatar can load. A photo
        // still waiting to upload has none, and the avatar catches up when the
        // operation runs and applies the returned person.
        if let photoRemoteId {
            person.profilePhotoId = photoRemoteId
            person.profileCropX = cropX
            person.profileCropY = cropY
            person.profileCropScale = cropScale
            try modelContext.save()
        }

        try await enqueueOperation(
            type: .setProfilePhoto,
            localId: person.id.uuidString,
            payload: payload,
            dependsOnLocalId: dependencyLocalIdForProfilePhoto(photo: photo, person: person)
        )
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

        try await enqueueOperation(
            type: .createGrowthData,
            localId: data.id.uuidString,
            payload: payload,
            dependsOnLocalId: dependsOnLocalId
        )
    }

    func updateGrowthData(_ data: GrowthData) async throws {
        let payload = UpdateGrowthDataPayload(
            measurementType: measurementTypeToString(data.measurementType),
            value: data.value,
            unit: unitToString(data.unit),
            measurementDate: dateToAPIString(data.date)
        )

        try await enqueueOperation(
            type: .updateGrowthData,
            localId: data.id.uuidString,
            payload: payload,
            dependsOnLocalId: nil
        )
    }

    func deleteGrowthData(_ data: GrowthData) async throws {
        guard let remoteId = data.remoteId, let id = Int(remoteId) else {
            modelContext.delete(data)
            try modelContext.save()
            return
        }

        let payload = DeletePayload(remoteId: id)
        // Read the local id before the delete — afterwards the model is gone
        // from the context and its properties are no longer safe to touch.
        let localId = data.id.uuidString

        modelContext.delete(data)
        try modelContext.save()

        try await enqueueOperation(
            type: .deleteGrowthData,
            localId: localId,
            payload: payload,
            dependsOnLocalId: nil
        )
    }

    // MARK: - Push: Milestones

    /// `photos` is the milestone's complete attachment set, or `nil` to say
    /// nothing about attachments at all — see `UpdateMilestoneRequestDTO`.
    func addMilestone(_ milestone: Milestone, for person: Person, photos: [Photo]? = nil) async throws {
        let payload = CreateMilestonePayload(
            personLocalId: person.id.uuidString,
            description: milestone.descriptionText,
            category: milestone.category.rawValue,
            milestoneDate: dateToAPIString(milestone.date),
            photoLocalIds: photos?.map { $0.id.uuidString }
        )

        let dependsOnLocalId = person.remoteId == nil ? person.id.uuidString : nil

        try applyPhotosOptimistically(photos, to: milestone)

        try await enqueueOperation(
            type: .createMilestone,
            localId: milestone.id.uuidString,
            payload: payload,
            dependsOnLocalId: dependsOnLocalId
        )
    }

    func updateMilestone(_ milestone: Milestone, photos: [Photo]? = nil) async throws {
        let payload = UpdateMilestonePayload(
            description: milestone.descriptionText,
            category: milestone.category.rawValue,
            milestoneDate: dateToAPIString(milestone.date),
            photoLocalIds: photos?.map { $0.id.uuidString }
        )

        try applyPhotosOptimistically(photos, to: milestone)

        try await enqueueOperation(
            type: .updateMilestone,
            localId: milestone.id.uuidString,
            payload: payload,
            dependsOnLocalId: nil
        )
    }

    /// The attachment the user just chose, shown before the server confirms it.
    ///
    /// Only the photos that already have a remote id can appear: `photoRemoteIds`
    /// is what `MilestoneRowView` and the detail sheet render from, and there is
    /// no id to render for a photo still uploading. The operation's own response
    /// replaces this list with the server's, so a photo omitted here comes back
    /// as soon as it exists.
    private func applyPhotosOptimistically(_ photos: [Photo]?, to milestone: Milestone) throws {
        guard let photos else { return }
        milestone.photoRemoteIds = photos.compactMap { $0.remoteId.flatMap(Int.init) }
        try modelContext.save()
    }

    func deleteMilestone(_ milestone: Milestone) async throws {
        guard let remoteId = milestone.remoteId, let id = Int(remoteId) else {
            modelContext.delete(milestone)
            try modelContext.save()
            return
        }

        let payload = DeletePayload(remoteId: id)
        let localId = milestone.id.uuidString

        modelContext.delete(milestone)
        try modelContext.save()

        try await enqueueOperation(
            type: .deleteMilestone,
            localId: localId,
            payload: payload,
            dependsOnLocalId: nil
        )
    }

    // MARK: - Push: Photos

    func deletePhoto(_ photo: Photo) async throws {
        guard let remoteId = photo.remoteId, let id = Int(remoteId) else {
            modelContext.delete(photo)
            try modelContext.save()
            return
        }

        let payload = DeletePayload(remoteId: id)
        let localId = photo.id.uuidString

        modelContext.delete(photo)
        try modelContext.save()

        try await enqueueOperation(
            type: .deletePhoto,
            localId: localId,
            payload: payload,
            dependsOnLocalId: nil
        )
    }

    func updatePhoto(_ photo: Photo) async throws {
        let payload = UpdatePhotoPayload(
            title: photo.title,
            description: photo.descriptionText,
            photoDate: dateToAPIString(photo.photoDate)
        )

        // A photo edited before its upload has flushed has no remote id yet, so
        // the update has to wait for the upload operation to assign one.
        let dependsOnLocalId = photo.remoteId == nil ? photo.id.uuidString : nil

        try await enqueueOperation(
            type: .updatePhoto,
            localId: photo.id.uuidString,
            payload: payload,
            dependsOnLocalId: dependsOnLocalId
        )
    }

    func uploadPhoto(_ photo: Photo) async throws {
        guard photo.imageData != nil else {
            throw SyncError.missingImageData
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let payload = UploadPhotoPayload(
            title: photo.title,
            description: photo.descriptionText,
            photoDate: formatter.string(from: photo.photoDate),
            taggedPersonLocalIds: photo.taggedPeople.map { $0.id.uuidString }
        )

        try await enqueueOperation(
            type: .uploadPhoto,
            localId: photo.id.uuidString,
            payload: payload,
            dependsOnLocalId: nil
        )
    }

    func addPeopleToPhoto(_ photo: Photo, people: [Person]) async throws {
        let payload = AddPeopleToPhotoPayload(personLocalIds: people.map { $0.id.uuidString })
        let dependsOnLocalId = dependencyLocalIdForTagging(photo: photo, people: people)

        try await enqueueOperation(
            type: .addPeopleToPhoto,
            localId: photo.id.uuidString,
            payload: payload,
            dependsOnLocalId: dependsOnLocalId
        )
    }

    func removePersonFromPhoto(_ photo: Photo, person: Person) async throws {
        let payload = RemovePersonFromPhotoPayload(personLocalId: person.id.uuidString)
        let dependsOnLocalId = dependencyLocalIdForTagging(photo: photo, people: [person])

        try await enqueueOperation(
            type: .removePersonFromPhoto,
            localId: photo.id.uuidString,
            payload: payload,
            dependsOnLocalId: dependsOnLocalId
        )
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
        if networkMonitor.isConnected {
            Task {
                await processQueue()
            }
        }
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

        let photoDescriptor = FetchDescriptor<Photo>()
        if let photos = try? modelContext.fetch(photoDescriptor) {
            for photo in photos where photo.remoteId != nil {
                syncedIds.insert(photo.id.uuidString)
            }
        }

        return syncedIds
    }

    /// Turns the photo local ids carried by a milestone operation into the remote
    /// ids the request needs.
    ///
    /// Three cases. A `nil` list means the operation says nothing about photos,
    /// and the key has to stay off the wire entirely.
    /// A photo deleted locally is dropped from the list: the milestone should
    /// still be written, and a photo that no longer exists cannot be attached to
    /// anything. A photo that exists but has not uploaded yet throws
    /// `missingRemoteId`, which parks the operation until the upload assigns one
    /// rather than quietly attaching fewer photos than the user chose.
    private func resolvePhotoRemoteIds(_ localIds: [String]?) throws -> [Int]? {
        guard let localIds else { return nil }

        var remoteIds: [Int] = []
        for localId in localIds {
            guard let photo = findPhoto(byLocalId: localId) else { continue }
            guard let remoteId = photo.remoteId, let id = Int(remoteId) else {
                throw SyncError.missingRemoteId("Photos must be uploaded before they can be attached to a milestone")
            }
            remoteIds.append(id)
        }
        return remoteIds
    }

    /// Both records have to be synced before the server can be told about the
    /// pairing, but an operation can only name one dependency. The photo goes
    /// first because it is the one likely to be mid-upload; the person is
    /// checked on execution and throws `missingRemoteId` if it is still behind.
    private func dependencyLocalIdForProfilePhoto(photo: Photo, person: Person) -> String? {
        if photo.remoteId == nil {
            return photo.id.uuidString
        }
        if person.remoteId == nil {
            return person.id.uuidString
        }
        return nil
    }

    private func dependencyLocalIdForTagging(photo: Photo, people: [Person]) -> String? {
        if photo.remoteId == nil {
            return photo.id.uuidString
        }

        if let person = people.first(where: { $0.remoteId == nil }) {
            return person.id.uuidString
        }

        return nil
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

    private func findPhoto(byLocalId localId: String) -> Photo? {
        guard let uuid = UUID(uuidString: localId) else { return nil }
        var descriptor = FetchDescriptor<Photo>(
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

    /// Deletes records the server no longer lists. Anything still awaiting its
    /// first push has no `remoteId` and is skipped by the guard below, which is
    /// the only protection unsynced local work needs — an extra exemption for
    /// photos holding local bytes used to sit here, and because those bytes were
    /// never released after upload it silently pinned every uploaded photo on
    /// the device for good.
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
    case missingImageData
    case missingBirthday
    case personNotInPhoto

    var errorDescription: String? {
        switch self {
        case .missingRemoteId(let message):
            return message
        case .missingImageData:
            return "Photo data is missing and cannot be uploaded"
        case .missingBirthday:
            return "A birthday is required before this person can be saved"
        case .personNotInPhoto:
            return "Only someone tagged in a photo can use it as their profile photo"
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
