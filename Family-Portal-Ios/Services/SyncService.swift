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

    /// Set when the queue gives up on an operation for good; survives the pulls that clear `syncError`.
    private(set) var discardedChangeWarning: String?

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
            let apiClient = self.apiClient
            async let timelineCall: GetFamilyTimelineResponseDTO = apiClient.callRPC(.getFamilyTimeline, payload: EmptyRequestDTO())
            async let photosCall: ListFamilyPhotosResponseDTO = apiClient.callRPC(.listFamilyPhotos, payload: EmptyRequestDTO())
            let (timelineResponse, photoResponse) = try await (timelineCall, photosCall)

            // Read after the responses land, so a change made while they were in flight is still protected.
            let pending = await pendingLocalChanges()

            var people = RemoteRecords<Person>(modelContext)
            var growth = RemoteRecords<GrowthData>(modelContext)
            var milestones = RemoteRecords<Milestone>(modelContext)
            var photos = RemoteRecords<Photo>(modelContext)
            var relations = RemoteRecords<PersonRelation>(modelContext)

            func upsertPerson(_ dto: PersonDTO) -> Person {
                let person = people.upsert(dto.id) { Person(name: "", gender: .other) }
                if !pending.isEdited(person.id) {
                    applyPersonDTO(dto, to: person)
                }
                return person
            }

            /// `nil` for a photo deleted locally whose delete has not reached the server yet.
            func upsertPhoto(_ dto: ImageDTO) -> Photo? {
                guard !pending.deletedPhotoIds.contains(dto.id) else { return nil }
                photos.markSeen(dto.id)
                return photos.upsert(dto.id) { Photo(title: "", descriptionText: "", photoDate: Date()) }
            }

            for item in timelineResponse.people {
                let person = upsertPerson(item.person)
                people.markSeen(item.person.id)

                for dto in item.growthData {
                    guard !pending.deletedGrowthDataIds.contains(dto.id) else { continue }
                    growth.markSeen(dto.id)
                    let record = growth.upsert(dto.id) {
                        GrowthData(measurementType: .height, value: 0, unit: .centimeters, date: Date())
                    }
                    if !pending.isEdited(record.id) {
                        applyGrowthDataDTO(dto, to: record)
                    }
                    record.person = person
                }

                for dto in item.milestones {
                    guard !pending.deletedMilestoneIds.contains(dto.id) else { continue }
                    milestones.markSeen(dto.id)
                    let milestone = milestones.upsert(dto.id) { Milestone(descriptionText: "", category: .other, date: Date()) }
                    if !pending.isEdited(milestone.id) {
                        applyMilestoneDTO(dto, to: milestone)
                    }
                    milestone.person = person
                }

                for dto in item.photos {
                    if let photo = upsertPhoto(dto), !pending.isEdited(photo.id) {
                        applyPhotoDTO(dto, to: photo)
                    }
                }
            }

            for photoWithPeople in photoResponse.photos {
                guard let photo = upsertPhoto(photoWithPeople.image) else { continue }
                let taggedPeople = photoWithPeople.people.map(upsertPerson)
                guard !pending.isEdited(photo.id) else { continue }
                applyPhotoDTO(photoWithPeople.image, to: photo)
                photo.taggedPeople = taggedPeople
            }

            for dto in timelineResponse.relations {
                let relation = relations.upsert(dto.id) { PersonRelation(fromId: 0, toId: 0, kind: .parent) }
                guard applyRelationDTO(dto, to: relation) else {
                    // A kind this build cannot read is not stored at all, so it must not be counted as seen either or the sweep would keep the stale row it replaced.
                    relations.forget(dto.id)
                    modelContext.delete(relation)
                    continue
                }
                relations.markSeen(dto.id)
            }

            people.sweepUnseen()
            relations.sweepUnseen()
            growth.sweepUnseen()
            milestones.sweepUnseen()
            photos.sweepUnseen()

            await pullTags()

            try modelContext.save()
            lastSyncDate = Date()
        } catch {
            AppLog.sync.error("Pull failed: \(String(describing: error), privacy: .public)")
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    /// What the queue still owes the server. A pull is a snapshot from before those operations land, so applying it as-is would roll back an edit made offline and bring a deleted record back until the queue caught up.
    private struct PendingLocalChanges {
        var editedLocalIds = Set<String>()
        var deletedGrowthDataIds = Set<Int>()
        var deletedMilestoneIds = Set<Int>()
        var deletedPhotoIds = Set<Int>()

        func isEdited(_ localId: UUID) -> Bool {
            editedLocalIds.contains(localId.uuidString)
        }
    }

    private func pendingLocalChanges() async -> PendingLocalChanges {
        var changes = PendingLocalChanges()
        for operation in await syncQueue.allOperations() {
            switch operation.type {
            case .deleteGrowthData, .deleteMilestone, .deletePhoto:
                // The local record is already gone, so the only handle left on it is the server id the delete carries.
                guard let payload = try? JSONDecoder().decode(DeletePayload.self, from: operation.payload) else { continue }
                let remoteId = payload.remoteId
                switch operation.type {
                case .deleteGrowthData: changes.deletedGrowthDataIds.insert(remoteId)
                case .deleteMilestone: changes.deletedMilestoneIds.insert(remoteId)
                default: changes.deletedPhotoIds.insert(remoteId)
                }
            case .createCheckup:
                // One operation, two records: the one it is not keyed on needs protecting just the same, or a pull landing mid-flight would create a duplicate of it.
                changes.editedLocalIds.insert(operation.localId)
                if let payload = try? JSONDecoder().decode(CreateCheckupPayload.self, from: operation.payload) {
                    changes.editedLocalIds.formUnion(payload.recordLocalIds)
                }
            default:
                changes.editedLocalIds.insert(operation.localId)
            }
        }
        return changes
    }

    /// Takes on tags the server added to a photo outside the queue — an accepted suggestion. The vocabulary is re-pulled first, since accepting a catalog label can create the tag.
    /// A queued whole-set tag write for the photo would untag what the server just added, so the new ids (`after` minus `before`) are folded into it instead of replacing the local set.
    func adoptServerTags(before: [Int], after: [Int], for photo: Photo) async {
        await pullTags()
        let hasPendingTagWrite = await syncQueue.allOperations().contains {
            $0.type == .updatePhotoTags && $0.localId == photo.id.uuidString
        }
        do {
            if hasPendingTagWrite {
                let added = Set(after).subtracting(before)
                let merged = photo.tagRemoteIds + added.sorted().filter { !photo.tagRemoteIds.contains($0) }
                try await updatePhotoTags(photo, tagRemoteIds: merged)
            } else {
                photo.tagRemoteIds = after
                try modelContext.save()
            }
        } catch {
            AppLog.sync.error("Adopting server tags failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The Tags screen's hook after each change, so pickers and chips see the new vocabulary without waiting for a full pull.
    func refreshTags() async {
        await pullTags()
        do {
            try modelContext.save()
        } catch {
            AppLog.sync.error("Saving tags failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func pullTags() async {
        do {
            let response: ListTagsResponseDTO = try await apiClient.callRPC(.listTags, payload: EmptyRequestDTO())

            var tags = RemoteRecords<FamilyTag>(modelContext)
            for dto in response.tags {
                tags.markSeen(dto.id)
                applyTagDTO(dto, to: tags.upsert(dto.id) { FamilyTag(name: "", colorHex: "", familyId: 0) })
            }
            tags.sweepUnseen()
        } catch {
            AppLog.sync.error("Tag pull failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Queue Processing

    /// A run is in flight. `@MainActor` is not mutual exclusion: a second run entering during a suspension would re-send operations that have not been dequeued yet.
    @ObservationIgnored private var isProcessingQueue = false

    @ObservationIgnored private var queueRunRequested = false

    func processQueue() async {
        guard networkMonitor.isConnected else { return }

        if isProcessingQueue {
            queueRunRequested = true
            return
        }
        isProcessingQueue = true
        defer { isProcessingQueue = false }

        var unblockedMore = false
        repeat {
            queueRunRequested = false
            unblockedMore = await runQueueOnce()
        } while (queueRunRequested || unblockedMore) && networkMonitor.isConnected
    }

    /// - Returns: whether the run synced a record that operations it could not start on were waiting for. Those go in another run straight away rather than waiting for the next foreground or edit — a person and their measurements added offline should arrive together.
    private func runQueueOnce() async -> Bool {
        let syncedLocalIds = await fetchAllSyncedLocalIds()
        let operations = await syncQueue.readyOperations(syncedLocalIds: syncedLocalIds)
        let blockedAtStart = Set(await syncQueue.blockedOperations(syncedLocalIds: syncedLocalIds).map(\.id))
        var discarded: [PendingOperation] = []
        var accountedFor = Set<UUID>()
        var wentOffline = false

        for operation in operations {
            await syncQueue.beginExecuting(operation.id)
            do {
                try await executeOperation(operation)
                await syncQueue.dequeue(operation.id)
            } catch {
                if isNetworkError(error) {
                    await syncQueue.endExecuting()
                    wentOffline = true
                    break
                }
                if case SyncError.missingRemoteId = error {
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

        var unblocked = false
        if !wentOffline {
            let syncedNow = await fetchAllSyncedLocalIds()
            let blocked = await syncQueue.blockedOperations(syncedLocalIds: syncedNow)
            for operation in blocked where !accountedFor.contains(operation.id) {
                if let dropped = await syncQueue.markBlocked(operation.id) {
                    discarded.append(dropped)
                }
            }
            unblocked = await syncQueue.readyOperations(syncedLocalIds: syncedNow)
                .contains { blockedAtStart.contains($0.id) }
        }

        if !discarded.isEmpty {
            discardedChangeWarning = Self.discardedChangeMessage(for: discarded)
        }

        await updatePendingCount()
        return unblocked
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
        case .createCheckup:
            try await executeCreateCheckup(operation)
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
        case .updatePhotoTags:
            try await executeUpdatePhotoTags(operation)
        case .updateMilestoneTags:
            try await executeUpdateMilestoneTags(operation)
        case .deleteGrowthData:
            try await executeDelete(operation, .deleteGrowthData)
        case .deleteMilestone:
            try await executeDelete(operation, .deleteMilestone)
        case .deletePhoto:
            try await executeDelete(operation, .deletePhoto)
        }
    }

    private func executeCreatePerson(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(CreatePersonPayload.self, from: operation.payload)

        guard let person = findPerson(byLocalId: operation.localId) else {
            return
        }

        let request = AddPersonRequestDTO(
            name: payload.name,
            gender: payload.gender,
            birthdate: payload.birthdate,
            isPregnancy: payload.isPregnancy,
            stated: payload.stated,
            anchorId: try resolveRelationAnchor(payload),
            additionalAnchorIds: resolveAdditionalAnchors(payload)
        )
        let response: AddPersonResponseDTO = try await apiClient.callRPC(.addPerson, payload: request)
        dropPulledCopies(of: person, serverId: response.person.id)
        applyPersonDTO(response.person, to: person)
        try modelContext.save()
    }

    /// The anchor's server id, or 0 when there is nothing to state. An anchor the user has since deleted drops the relationship rather than blocking the person forever; one that is merely still uploading throws, so the operation is parked and retried with the relationship intact.
    private func resolveRelationAnchor(_ payload: CreatePersonPayload) throws -> Int {
        guard payload.stated != StatedRelation.none.rawValue,
              let anchorLocalId = payload.anchorLocalId else {
            return 0
        }
        guard let anchor = findPerson(byLocalId: anchorLocalId) else {
            return 0
        }
        return try serverId(of: anchor, "The related person must be synced first")
    }

    /// The co-anchors that can be named right now. One still uploading or since deleted is simply left out: the server refuses the *whole* call over an id it cannot see, and a create that never lands is a worse outcome than a second parent the user can add again.
    private func resolveAdditionalAnchors(_ payload: CreatePersonPayload) -> [Int] {
        guard payload.stated != StatedRelation.none.rawValue else { return [] }
        return payload.additionalAnchorLocalIds.compactMap { localId in
            findPerson(byLocalId: localId)?.serverId
        }
    }

    private func executeUpdatePerson(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdatePersonPayload.self, from: operation.payload)

        let (person, personId) = try synced(findPerson(byLocalId: operation.localId), "Person must be synced before updating")

        let request = UpdatePersonRequestDTO(
            id: personId,
            name: payload.name,
            gender: payload.gender,
            birthdate: payload.birthdate,
            isPregnancy: payload.isPregnancy
        )
        let response: UpdatePersonResponseDTO = try await apiClient.callRPC(.updatePerson, payload: request)
        applyPersonDTO(response.person, to: person)
        try modelContext.save()
    }

    private func executeSetProfilePhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(SetProfilePhotoPayload.self, from: operation.payload)

        guard let person = findPerson(byLocalId: operation.localId),
              let photo = findPhoto(byLocalId: payload.photoLocalId) else {
            return
        }

        let personId = try serverId(of: person, "Person must be synced before setting a profile photo")
        let photoId = try serverId(of: photo, "Photo must be uploaded before it can be a profile photo")

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

        guard let growthData = findGrowthData(byLocalId: operation.localId) else {
            return
        }

        guard let person = findPerson(byLocalId: payload.personLocalId) else {
            return
        }

        let personId = try serverId(of: person, "Person must be synced before adding measurements")

        let request = AddGrowthDataRequestDTO(
            personId: personId,
            measurementType: payload.measurementType,
            value: payload.value,
            unit: payload.unit,
            measurementDate: payload.measurementDate
        )
        let response: AddGrowthDataResponseDTO = try await apiClient.callRPC(.addGrowthData, payload: request)
        dropPulledCopies(of: growthData, serverId: response.growthData.id)
        applyGrowthDataDTO(response.growthData, to: growthData)
        try modelContext.save()
    }

    private func executeCreateCheckup(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(CreateCheckupPayload.self, from: operation.payload)

        // A half deleted locally since is left out; the other still goes.
        let height = payload.heightLocalId.flatMap { findGrowthData(byLocalId: $0) }
        let weight = payload.weightLocalId.flatMap { findGrowthData(byLocalId: $0) }
        guard height != nil || weight != nil else { return }

        guard let person = findPerson(byLocalId: payload.personLocalId) else {
            return
        }

        let personId = try serverId(of: person, "Person must be synced before adding measurements")

        func value(_ record: GrowthData?, _ value: Double?, _ unit: String?) -> CheckupValueDTO? {
            guard record != nil, let value, let unit else { return nil }
            return CheckupValueDTO(value: value, unit: unit)
        }

        let request = AddCheckupRequestDTO(
            personId: personId,
            measurementDate: payload.measurementDate,
            height: value(height, payload.heightValue, payload.heightUnit),
            weight: value(weight, payload.weightValue, payload.weightUnit)
        )
        let response: AddCheckupResponseDTO = try await apiClient.callRPC(.addCheckup, payload: request)
        for dto in response.growthData {
            if let record = intToMeasurementType(dto.measurementType) == .height ? height : weight {
                dropPulledCopies(of: record, serverId: dto.id)
            }
        }
        applyCheckupResponse(response, height: height, weight: weight)
        try modelContext.save()
    }

    private func executeCreateMilestone(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(CreateMilestonePayload.self, from: operation.payload)

        guard let milestone = findMilestone(byLocalId: operation.localId) else {
            return
        }

        guard let person = findPerson(byLocalId: payload.personLocalId) else {
            return
        }

        let personId = try serverId(of: person, "Person must be synced before adding milestones")

        let request = AddMilestoneRequestDTO(
            personId: personId,
            description: payload.description,
            category: payload.category,
            context: payload.context ?? "",
            milestoneDate: payload.milestoneDate,
            photoIds: try resolvePhotoRemoteIds(payload.photoLocalIds),
            tagIds: payload.tagRemoteIds
        )
        let response: AddMilestoneResponseDTO = try await apiClient.callRPC(.addMilestone, payload: request)
        dropPulledCopies(of: milestone, serverId: response.milestone.id)
        applyMilestoneDTO(response.milestone, to: milestone)
        try modelContext.save()
    }

    private func executeUploadPhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UploadPhotoPayload.self, from: operation.payload)

        guard let photo = findPhoto(byLocalId: operation.localId),
              let imageData = photo.imageData else {
            return
        }

        let personIds = try payload.taggedPersonLocalIds.compactMap { localId -> Int? in
            guard let person = findPerson(byLocalId: localId) else { return nil }
            return try serverId(of: person, "Tagged people must be synced before uploading photo")
        }

        let response = try await PhotoSyncService(apiClient: apiClient).uploadPhoto(
            imageData: imageData,
            title: photo.title,
            description: photo.descriptionText,
            photoDate: photo.photoDate,
            personIds: personIds
        )
        dropPulledCopies(of: photo, serverId: response.id)
        applyPhotoDTO(response, to: photo)

        photo.imageData = nil

        try modelContext.save()
    }

    private func executeAddPeopleToPhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(AddPeopleToPhotoPayload.self, from: operation.payload)

        let photoId = try serverId(of: findPhoto(byLocalId: operation.localId), "Photo must be synced before adding people")
        let personIds = try payload.personLocalIds.map {
            try serverId(of: findPerson(byLocalId: $0), "All people must be synced before adding to photo")
        }

        let request = AddPeopleToPhotoRequestDTO(photoId: photoId, personIds: personIds)
        let _: SuccessResponseDTO = try await apiClient.callRPC(.addPeopleToPhoto, payload: request)
    }

    private func executeRemovePersonFromPhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(RemovePersonFromPhotoPayload.self, from: operation.payload)

        let photoId = try serverId(of: findPhoto(byLocalId: operation.localId), "Photo must be synced before removing person")
        let personId = try serverId(of: findPerson(byLocalId: payload.personLocalId), "Person must be synced before removing from photo")

        let request = RemovePersonFromPhotoRequestDTO(photoId: photoId, personId: personId)
        let _: SuccessResponseDTO = try await apiClient.callRPC(.removePersonFromPhoto, payload: request)
    }

    private func executeUpdateGrowthData(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdateGrowthDataPayload.self, from: operation.payload)

        let (growthData, id) = try synced(findGrowthData(byLocalId: operation.localId), "GrowthData must be synced before updating")

        let request = UpdateGrowthDataRequestDTO(
            id: id,
            measurementType: payload.measurementType,
            value: payload.value,
            unit: payload.unit,
            measurementDate: payload.measurementDate
        )
        let response: UpdateGrowthDataResponseDTO = try await apiClient.callRPC(.updateGrowthData, payload: request)
        applyGrowthDataDTO(response.growthData, to: growthData)
        try modelContext.save()
    }

    private func executeUpdateMilestone(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdateMilestonePayload.self, from: operation.payload)

        let (milestone, id) = try synced(findMilestone(byLocalId: operation.localId), "Milestone must be synced before updating")

        let request = UpdateMilestoneRequestDTO(
            id: id,
            description: payload.description,
            category: payload.category,
            context: payload.context ?? "",
            milestoneDate: payload.milestoneDate,
            photoIds: try resolvePhotoRemoteIds(payload.photoLocalIds),
            tagIds: payload.tagRemoteIds
        )
        let response: UpdateMilestoneResponseDTO = try await apiClient.callRPC(.updateMilestone, payload: request)
        applyMilestoneDTO(response.milestone, to: milestone)
        try modelContext.save()
    }

    private func executeUpdatePhoto(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdatePhotoPayload.self, from: operation.payload)

        let (photo, id) = try synced(findPhoto(byLocalId: operation.localId), "Photo must be uploaded before updating")

        let keepsDate = payload.keepDate == true
        let request = UpdatePhotoRequestDTO(
            id: id,
            title: payload.title,
            description: payload.description,
            inputType: keepsDate ? "keep" : "date",
            photoDate: keepsDate ? nil : payload.photoDate
        )
        let response: UpdatePhotoResponseDTO = try await apiClient.callRPC(.updatePhoto, payload: request)
        applyPhotoDTO(response.image, to: photo)
        try modelContext.save()
    }

    private func executeUpdatePhotoTags(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdateTagsPayload.self, from: operation.payload)

        guard let photo = findPhoto(byLocalId: operation.localId) else {
            return
        }

        let id = try serverId(of: photo, "Photo must be uploaded before its tags can be saved")

        let request = UpdatePhotoTagsRequestDTO(photoId: id, tagIds: payload.tagRemoteIds)
        let _: EmptyResponseDTO = try await apiClient.callRPC(.updatePhotoTags, payload: request)
    }

    private func executeUpdateMilestoneTags(_ operation: PendingOperation) async throws {
        let payload = try JSONDecoder().decode(UpdateTagsPayload.self, from: operation.payload)

        guard let milestone = findMilestone(byLocalId: operation.localId) else {
            return
        }

        let id = try serverId(of: milestone, "Milestone must be synced before its tags can be saved")

        let request = UpdateMilestoneTagsRequestDTO(milestoneId: id, tagIds: payload.tagRemoteIds)
        let _: EmptyResponseDTO = try await apiClient.callRPC(.updateMilestoneTags, payload: request)
    }

    /// A record the server no longer has is as deleted as it is going to get, so a 404 counts as done.
    private func executeDelete(_ operation: PendingOperation, _ proc: RPCMethod) async throws {
        let payload = try JSONDecoder().decode(DeletePayload.self, from: operation.payload)
        do {
            let _: SuccessResponseDTO = try await apiClient.callRPC(proc, payload: DeleteRequestDTO(id: payload.remoteId))
        } catch APIError.server(let statusCode, _) where statusCode == 404 {
            return
        }
    }

    // MARK: - Push: Person

    /// Queues a new person, optionally stating how they relate to someone already in the roster. The stated word travels with the create rather than as a second call: it is what the server derives every other label from, and a person added offline should arrive related, not related a round trip later.
    func addPerson(
        _ person: Person,
        stated: StatedRelation = .none,
        anchor: Person? = nil,
        additionalAnchors: [Person] = []
    ) async throws {
        guard let birthday = person.birthday else {
            throw SyncError.missingBirthday
        }

        let statesRelation = stated != .none && anchor != nil
        let payload = CreatePersonPayload(
            name: person.name,
            gender: genderToInt(person.gender),
            birthdate: dateToAPIString(birthday),
            isPregnancy: person.isPregnancy,
            stated: statesRelation ? stated.rawValue : StatedRelation.none.rawValue,
            anchorLocalId: statesRelation ? anchor?.id.uuidString : nil,
            additionalAnchorLocalIds: statesRelation
                ? additionalAnchors.filter { $0.id != anchor?.id }.map(\.id.uuidString)
                : []
        )

        // The anchor is a dependency only while it is unsynced, so the create waits at the gate instead of spending a request to learn the same thing.
        let dependsOnLocalId = statesRelation && anchor?.remoteId == nil
            ? anchor?.id.uuidString
            : nil

        try await enqueueOperation(
            type: .createPerson,
            localId: person.id.uuidString,
            payload: payload,
            dependsOnLocalId: dependsOnLocalId
        )
    }

    func updatePerson(_ person: Person) async throws {
        guard let birthday = person.birthday else {
            throw SyncError.missingBirthday
        }

        let payload = UpdatePersonPayload(
            name: person.name,
            gender: genderToInt(person.gender),
            birthdate: dateToAPIString(birthday),
            isPregnancy: person.isPregnancy
        )

        try await enqueueOperation(
            type: .updatePerson,
            localId: person.id.uuidString,
            payload: payload,
            dependsOnLocalId: unsyncedId(person)
        )
    }

    /// Points a person's avatar at one of the photos they are tagged in. The server rejects a photo they are not tagged in, so refuse up front.
    func setProfilePhoto(_ photo: Photo, for person: Person) async throws {
        guard photo.taggedPeople.contains(where: { $0.id == person.id }) else {
            throw SyncError.personNotInPhoto
        }

        let photoRemoteId = photo.serverId

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

        try await enqueueOperation(
            type: .createGrowthData,
            localId: data.id.uuidString,
            payload: payload,
            dependsOnLocalId: unsyncedId(person)
        )
    }

    /// Queues the records of one checkup — one person, one day — as a single `AddCheckup`, so the server saves both or neither. A checkup with one value is an ordinary `AddGrowthData`.
    func addCheckup(_ records: [GrowthData], for person: Person) async throws {
        let height = records.first { $0.measurementType == .height }
        let weight = records.first { $0.measurementType == .weight }
        guard let height, let weight else {
            for record in records {
                try await addGrowthData(record, for: person)
            }
            return
        }

        let payload = CreateCheckupPayload(
            personLocalId: person.id.uuidString,
            measurementDate: dateToAPIString(height.date),
            heightLocalId: height.id.uuidString,
            heightValue: height.value,
            heightUnit: unitToString(height.unit),
            weightLocalId: weight.id.uuidString,
            weightValue: weight.value,
            weightUnit: unitToString(weight.unit)
        )

        try await enqueueOperation(
            type: .createCheckup,
            localId: height.id.uuidString,
            payload: payload,
            dependsOnLocalId: unsyncedId(person)
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
        try await deleteRecord(data, localId: data.id, serverId: data.serverId, as: .deleteGrowthData)
    }

    // MARK: - Push: Milestones

    /// `photos` is the milestone's complete attachment set, or `nil` to say nothing about attachments. `tagRemoteIds` travels in the same call, so the milestone never exists on the server without its tags.
    func addMilestone(_ milestone: Milestone, for person: Person, photos: [Photo]? = nil, tagRemoteIds: [Int]? = nil) async throws {
        let payload = CreateMilestonePayload(
            personLocalId: person.id.uuidString,
            description: milestone.descriptionText,
            category: milestone.category.rawValue,
            milestoneDate: dateToAPIString(milestone.date),
            photoLocalIds: photos?.map { $0.id.uuidString },
            tagRemoteIds: tagRemoteIds,
            context: milestone.context
        )

        try applyPhotosOptimistically(photos, to: milestone)
        try applyTagsOptimistically(tagRemoteIds, to: milestone)

        try await enqueueOperation(
            type: .createMilestone,
            localId: milestone.id.uuidString,
            payload: payload,
            dependsOnLocalId: unsyncedId(person)
        )
    }

    /// `tagRemoteIds` is `nil` from any editor that did not show the tag picker: `[]` would clear the tags.
    func updateMilestone(_ milestone: Milestone, photos: [Photo]? = nil, tagRemoteIds: [Int]? = nil) async throws {
        let payload = UpdateMilestonePayload(
            description: milestone.descriptionText,
            category: milestone.category.rawValue,
            milestoneDate: dateToAPIString(milestone.date),
            photoLocalIds: photos?.map { $0.id.uuidString },
            tagRemoteIds: tagRemoteIds,
            context: milestone.context
        )

        try applyPhotosOptimistically(photos, to: milestone)
        try applyTagsOptimistically(tagRemoteIds, to: milestone)

        try await enqueueOperation(
            type: .updateMilestone,
            localId: milestone.id.uuidString,
            payload: payload,
            dependsOnLocalId: nil
        )
    }

    private func applyPhotosOptimistically(_ photos: [Photo]?, to milestone: Milestone) throws {
        guard let photos else { return }
        milestone.photoRemoteIds = photos.compactMap { $0.serverId }
        try modelContext.save()
    }

    private func applyTagsOptimistically(_ tagRemoteIds: [Int]?, to milestone: Milestone) throws {
        guard let tagRemoteIds else { return }
        milestone.tagRemoteIds = tagRemoteIds
        try modelContext.save()
    }

    func deleteMilestone(_ milestone: Milestone) async throws {
        try await deleteRecord(milestone, localId: milestone.id, serverId: milestone.serverId, as: .deleteMilestone)
    }

    // MARK: - Push: Photos

    func deletePhoto(_ photo: Photo) async throws {
        try await deleteRecord(photo, localId: photo.id, serverId: photo.serverId, as: .deletePhoto)
    }

    /// `keepingDate` sends `inputType: "keep"`: the server keeps whatever date the photo has, which after an upload is the one it read from the file itself. Anything without a date control must keep it — a dated update sends only the day, and would wipe the capture time.
    /// The update replaces any queued one whole, so a date change still waiting to be sent turns this into a dated update rather than being lost to a later caption edit.
    func updatePhoto(_ photo: Photo, keepingDate: Bool) async throws {
        let keepsDate: Bool
        if keepingDate {
            keepsDate = !(await hasQueuedDateChange(for: photo))
        } else {
            keepsDate = false
        }

        let payload = UpdatePhotoPayload(
            title: photo.title,
            description: photo.descriptionText,
            photoDate: dateToAPIString(photo.photoDate),
            keepDate: keepsDate
        )

        try await enqueueOperation(
            type: .updatePhoto,
            localId: photo.id.uuidString,
            payload: payload,
            dependsOnLocalId: unsyncedId(photo)
        )
    }

    private func hasQueuedDateChange(for photo: Photo) async -> Bool {
        await syncQueue.allOperations().contains { operation in
            guard operation.type == .updatePhoto, operation.localId == photo.id.uuidString,
                  let payload = try? JSONDecoder().decode(UpdatePhotoPayload.self, from: operation.payload) else {
                return false
            }
            return payload.keepDate != true
        }
    }

    func uploadPhoto(_ photo: Photo) async throws {
        guard photo.imageData != nil else {
            throw SyncError.missingImageData
        }

        let payload = UploadPhotoPayload(taggedPersonLocalIds: photo.taggedPeople.map { $0.id.uuidString })

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

    // MARK: - Push: Tags

    /// Replaces the tags on a photo. The set is complete rather than a delta, and must include ids this device cannot resolve yet or they are silently untagged.
    func updatePhotoTags(_ photo: Photo, tagRemoteIds: [Int]) async throws {
        try await enqueueOperation(
            type: .updatePhotoTags,
            localId: photo.id.uuidString,
            payload: UpdateTagsPayload(tagRemoteIds: tagRemoteIds),
            dependsOnLocalId: unsyncedId(photo)
        )

        photo.tagRemoteIds = tagRemoteIds
        try modelContext.save()
    }

    /// The milestone half of `updatePhotoTags(_:tagRemoteIds:)`. No dependency is declared; an unsynced milestone is parked at execution instead.
    func updateMilestoneTags(_ milestone: Milestone, tagRemoteIds: [Int]) async throws {
        try await enqueueOperation(
            type: .updateMilestoneTags,
            localId: milestone.id.uuidString,
            payload: UpdateTagsPayload(tagRemoteIds: tagRemoteIds),
            dependsOnLocalId: nil
        )

        milestone.tagRemoteIds = tagRemoteIds
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
        if networkMonitor.isConnected {
            Task {
                await processQueue()
            }
        }
    }

    /// `APIClient` wraps every transport failure in `.network`, so that is the only shape going offline takes.
    private func isNetworkError(_ error: Error) -> Bool {
        if case APIError.network = error { return true }
        return false
    }

    private func updatePendingCount() async {
        pendingOperationCount = await syncQueue.count()
    }

    /// The only records an operation can wait on.
    private func fetchAllSyncedLocalIds() async -> Set<String> {
        let people = (try? modelContext.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.remoteId != nil }))) ?? []
        let photos = (try? modelContext.fetch(FetchDescriptor<Photo>(predicate: #Predicate { $0.remoteId != nil }))) ?? []
        return Set(people.map(\.id.uuidString) + photos.map(\.id.uuidString))
    }

    /// Resolves a milestone operation's photo local ids to remote ids. `nil` keeps the key off the wire, a deleted photo is dropped, and one still uploading throws `missingRemoteId`.
    private func resolvePhotoRemoteIds(_ localIds: [String]?) throws -> [Int]? {
        guard let localIds else { return nil }

        var remoteIds: [Int] = []
        for localId in localIds {
            guard let photo = findPhoto(byLocalId: localId) else { continue }
            remoteIds.append(try serverId(of: photo, "Photos must be uploaded before they can be attached to a milestone"))
        }
        return remoteIds
    }

    /// An operation can only name one dependency, so the photo goes first and the person is checked at execution.
    private func dependencyLocalIdForProfilePhoto(photo: Photo, person: Person) -> String? {
        unsyncedId(photo) ?? unsyncedId(person)
    }

    private func dependencyLocalIdForTagging(photo: Photo, people: [Person]) -> String? {
        unsyncedId(photo) ?? people.lazy.compactMap { self.unsyncedId($0) }.first
    }

    /// The record's local id while it has no server id, which is what an operation on it waits for.
    private func unsyncedId(_ record: some RemoteIdentifiable) -> String? {
        record.remoteId == nil ? record.id.uuidString : nil
    }

    /// The record's server id, or `missingRemoteId` when it is missing or not on the server yet — which parks the operation until it is.
    private func synced<Record: RemoteIdentifiable>(_ record: Record?, _ reason: String) throws -> (Record, Int) {
        guard let record, let id = record.serverId else {
            throw SyncError.missingRemoteId(reason)
        }
        return (record, id)
    }

    private func serverId(of record: (some RemoteIdentifiable)?, _ reason: String) throws -> Int {
        try synced(record, reason).1
    }

    /// Deletes locally at once. A record the server never had needs nothing more; one it has is deleted there through the queue, carrying the server id since the local record is gone.
    private func deleteRecord<Model: PersistentModel>(_ record: Model, localId: UUID, serverId: Int?, as type: SyncOperationType) async throws {
        modelContext.delete(record)
        try modelContext.save()
        guard let id = serverId else { return }
        try await enqueueOperation(type: type, localId: localId.uuidString, payload: DeletePayload(remoteId: id), dependsOnLocalId: nil)
    }

    // MARK: - Pulled copies

    // A pull can run while a create is on the wire. If the server saved the record before the pull read, and the pull's answer is applied before the create's, the pull stores its own copy under the new server id and the local record then takes the same id: two records that no later pull would ever tell apart. The create's answer is the moment to notice, and the local record — the one queued operations name — is the one kept.

    private func dropPulledCopies(of person: Person, serverId: Int) {
        let remoteId = String(serverId)
        for copy in others(of: person, #Predicate<Person> { $0.remoteId == remoteId }) {
            // Their records came with the copy from the same pull; deleting it would cascade them away until the next one.
            let records = copy.growthData
            let milestones = copy.milestones
            copy.growthData = []
            copy.milestones = []
            for record in records { record.person = person }
            for milestone in milestones { milestone.person = person }
            modelContext.delete(copy)
        }
    }

    private func dropPulledCopies(of growthData: GrowthData, serverId: Int) {
        let remoteId = String(serverId)
        for copy in others(of: growthData, #Predicate<GrowthData> { $0.remoteId == remoteId }) {
            modelContext.delete(copy)
        }
    }

    private func dropPulledCopies(of milestone: Milestone, serverId: Int) {
        let remoteId = String(serverId)
        for copy in others(of: milestone, #Predicate<Milestone> { $0.remoteId == remoteId }) {
            modelContext.delete(copy)
        }
    }

    private func dropPulledCopies(of photo: Photo, serverId: Int) {
        let remoteId = String(serverId)
        for copy in others(of: photo, #Predicate<Photo> { $0.remoteId == remoteId }) {
            modelContext.delete(copy)
        }
    }

    private func others<Model: PersistentModel & RemoteIdentifiable>(of record: Model, _ predicate: Predicate<Model>) -> [Model] {
        let matches = (try? modelContext.fetch(FetchDescriptor<Model>(predicate: predicate))) ?? []
        return matches.filter { $0 !== record }
    }

    // MARK: - Lookup Helpers

    private func first<Model: PersistentModel>(_ predicate: Predicate<Model>) -> Model? {
        var descriptor = FetchDescriptor<Model>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func findPerson(byLocalId localId: String) -> Person? {
        guard let uuid = UUID(uuidString: localId) else { return nil }
        return first(#Predicate<Person> { $0.id == uuid })
    }

    private func findGrowthData(byLocalId localId: String) -> GrowthData? {
        guard let uuid = UUID(uuidString: localId) else { return nil }
        return first(#Predicate<GrowthData> { $0.id == uuid })
    }

    private func findMilestone(byLocalId localId: String) -> Milestone? {
        guard let uuid = UUID(uuidString: localId) else { return nil }
        return first(#Predicate<Milestone> { $0.id == uuid })
    }

    private func findPhoto(byLocalId localId: String) -> Photo? {
        guard let uuid = UUID(uuidString: localId) else { return nil }
        return first(#Predicate<Photo> { $0.id == uuid })
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

private protocol RemoteIdentifiable: ServerIdentified {
    var id: UUID { get }
}

/// Every stored record of one type keyed by server id, fetched once per pull: the pull touches every record, and a predicate fetch for each one was N queries on the main actor. What the pull never marks seen is swept at the end, since the server no longer has it.
private struct RemoteRecords<Model: PersistentModel & RemoteIdentifiable> {
    private let context: ModelContext
    private var records: [Model]
    private var byServerId: [Int: Model] = [:]
    private var seen = Set<Int>()

    init(_ context: ModelContext) {
        self.context = context
        records = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        byServerId = records.byServerId()
    }

    /// The record with this server id, inserting a blank one from `make` when there is none yet. Does not mark it seen: a person met only as a photo tag is not a reason to keep them.
    mutating func upsert(_ serverId: Int, make: () -> Model) -> Model {
        if let existing = byServerId[serverId] { return existing }
        let record = make()
        record.serverId = serverId
        context.insert(record)
        records.append(record)
        byServerId[serverId] = record
        return record
    }

    mutating func markSeen(_ serverId: Int) {
        seen.insert(serverId)
    }

    /// For a record the caller has deleted itself, so the sweep does not delete it a second time.
    mutating func forget(_ serverId: Int) {
        guard let record = byServerId.removeValue(forKey: serverId) else { return }
        records.removeAll { $0 === record }
    }

    func sweepUnseen() {
        for record in records {
            if let serverId = record.serverId, !seen.contains(serverId) {
                context.delete(record)
            }
        }
    }
}

extension Person: RemoteIdentifiable {}
extension PersonRelation: RemoteIdentifiable {}
extension GrowthData: RemoteIdentifiable {}
extension Milestone: RemoteIdentifiable {}
extension Photo: RemoteIdentifiable {}
extension FamilyTag: RemoteIdentifiable {}
