import Foundation
import OSLog

nonisolated struct ActivityRead<Value: Sendable>: Sendable {
    let cached: @Sendable () async -> ActivitySnapshot<Value>?
    let live: @Sendable () async throws -> Value
}

/// Online-first with a snapshot cache, deliberately outside SwiftData and `SyncQueue`: the joins are already done server-side, every write is a whole-set replace with cross-record validation the device cannot predict, and there is no delta protocol to reconcile a queued write against.
@Observable
@MainActor
final class ActivityService {

    private let apiClient: APIClient
    private let cache: ActivitySnapshotCache

    init(apiClient: APIClient = .shared, cache: ActivitySnapshotCache = .shared) {
        self.apiClient = apiClient
        self.cache = cache
    }

    // MARK: - Reads

    func activities(familyId: Int = 0) -> ActivityRead<ListActivitiesResponseDTO> {
        read(
            .listActivities,
            payload: ListActivitiesRequestDTO(familyId: familyId),
            key: ActivitySnapshotKey(.listActivities, familyId)
        )
    }

    func seasons(activityId: Int) -> ActivityRead<ListSeasonsResponseDTO> {
        read(
            .listSeasons,
            payload: ListSeasonsRequestDTO(activityId: activityId),
            key: ActivitySnapshotKey(.listSeasons, activityId)
        )
    }

    func seasonOverview(seasonId: Int) -> ActivityRead<GetSeasonOverviewResponseDTO> {
        read(
            .getSeasonOverview,
            payload: GetSeasonOverviewRequestDTO(seasonId: seasonId),
            key: ActivitySnapshotKey(.getSeasonOverview, seasonId)
        )
    }

    func eventDetail(eventId: Int) -> ActivityRead<GetEventDetailResponseDTO> {
        read(
            .getEventDetail,
            payload: GetEventDetailRequestDTO(eventId: eventId),
            key: ActivitySnapshotKey(.getEventDetail, eventId)
        )
    }

    func entryHistory(entryId: Int) -> ActivityRead<GetEntryHistoryResponseDTO> {
        read(
            .getEntryHistory,
            payload: GetEntryHistoryRequestDTO(entryId: entryId),
            key: ActivitySnapshotKey(.getEntryHistory, entryId)
        )
    }

    func personSeason(personId: Int, seasonId: Int = 0) -> ActivityRead<GetPersonSeasonResponseDTO> {
        read(
            .getPersonSeason,
            payload: GetPersonSeasonRequestDTO(personId: personId, seasonId: seasonId),
            key: ActivitySnapshotKey(.getPersonSeason, personId, seasonId)
        )
    }

    func vocabulary(activityId: Int) -> ActivityRead<ListActivityVocabularyResponseDTO> {
        read(
            .listActivityVocabulary,
            payload: ListActivityVocabularyRequestDTO(activityId: activityId),
            key: ActivitySnapshotKey(.listActivityVocabulary, activityId)
        )
    }

    // MARK: - Writes
    // Online only, never queued: the server's cross-record refusals cannot be predicted on-device, and a queued write replayed hours later would report a success that never happened. None of these touch the snapshot cache.
    // Text is clamped here rather than at each call site — over-length text is silently truncated on write, not refused.

    func createAppearance(
        eventId: Int,
        entryId: Int,
        occurredAt: Date?,
        notes: String
    ) async throws -> AppearanceViewDTO {
        let response: AppearanceResponseDTO = try await apiClient.callRPC(
            .createAppearance,
            payload: CreateAppearanceRequestDTO(
                eventId: eventId,
                entryId: entryId,
                occurredAt: ServerDateFormat.requestString(occurredAt),
                notes: ActivityFieldLimit.notes.clamp(notes)
            )
        )
        return response.appearance
    }

    /// Only the date and the notes. `occurredAt: nil` **clears** the date rather than leaving it alone, so pass what the caller is showing.
    func updateAppearance(
        id: Int,
        occurredAt: Date?,
        notes: String
    ) async throws -> AppearanceViewDTO {
        let response: AppearanceResponseDTO = try await apiClient.callRPC(
            .updateAppearance,
            payload: UpdateAppearanceRequestDTO(
                id: id,
                occurredAt: ServerDateFormat.requestString(occurredAt),
                notes: ActivityFieldLimit.notes.clamp(notes)
            )
        )
        return response.appearance
    }

    func deleteAppearance(id: Int) async throws {
        let _: ActivityDeleteResponseDTO = try await apiClient.callRPC(
            .deleteAppearance,
            payload: AppearanceIdRequestDTO(id: id)
        )
    }

    /// Replaces the whole results sheet; array order is where `sortOrder` comes from.
    func setAppearanceResults(
        appearanceId: Int,
        results: [ResultInputDTO]
    ) async throws -> AppearanceViewDTO {
        let response: AppearanceResponseDTO = try await apiClient.callRPC(
            .setAppearanceResults,
            payload: SetAppearanceResultsRequestDTO(appearanceId: appearanceId, results: results)
        )
        return response.appearance
    }

    /// Replaces the whole attachment set, over *remote* photo ids.
    func setAppearancePhotos(
        appearanceId: Int,
        photoIds: [Int]
    ) async throws -> AppearanceViewDTO {
        let response: AppearanceResponseDTO = try await apiClient.callRPC(
            .setAppearancePhotos,
            payload: SetAppearancePhotosRequestDTO(appearanceId: appearanceId, photoIds: photoIds)
        )
        return response.appearance
    }

    // MARK: - Structure writes

    func createActivity(familyId: Int = 0, name: String, kind: String) async throws -> ActivityDTO {
        let response: ActivityRecordResponseDTO = try await apiClient.callRPC(
            .createActivity,
            payload: CreateActivityRequestDTO(
                familyId: familyId,
                name: ActivityFieldLimit.name.clamp(name),
                kind: kind
            )
        )
        return response.activity
    }

    func updateActivity(id: Int, name: String, kind: String) async throws -> ActivityDTO {
        let response: ActivityRecordResponseDTO = try await apiClient.callRPC(
            .updateActivity,
            payload: UpdateActivityRequestDTO(
                id: id,
                name: ActivityFieldLimit.name.clamp(name),
                kind: kind
            )
        )
        return response.activity
    }

    func deleteActivity(id: Int) async throws {
        let _: ActivityDeleteResponseDTO = try await apiClient.callRPC(
            .deleteActivity,
            payload: ActivityRecordIdRequestDTO(id: id)
        )
    }

    func createSeason(
        activityId: Int,
        name: String,
        startDate: Date?,
        endDate: Date?,
        notes: String
    ) async throws -> SeasonDTO {
        let response: SeasonResponseDTO = try await apiClient.callRPC(
            .createSeason,
            payload: CreateSeasonRequestDTO(
                activityId: activityId,
                name: ActivityFieldLimit.name.clamp(name),
                startDate: ServerDateFormat.requestString(startDate),
                endDate: ServerDateFormat.requestString(endDate),
                notes: ActivityFieldLimit.notes.clamp(notes)
            )
        )
        return response.season
    }

    /// Both dates are always sent: omitting one clears it rather than leaving it alone.
    func updateSeason(
        id: Int,
        name: String,
        startDate: Date?,
        endDate: Date?,
        notes: String
    ) async throws -> SeasonDTO {
        let response: SeasonResponseDTO = try await apiClient.callRPC(
            .updateSeason,
            payload: UpdateSeasonRequestDTO(
                id: id,
                name: ActivityFieldLimit.name.clamp(name),
                startDate: ServerDateFormat.requestString(startDate),
                endDate: ServerDateFormat.requestString(endDate),
                notes: ActivityFieldLimit.notes.clamp(notes)
            )
        )
        return response.season
    }

    func deleteSeason(id: Int) async throws {
        let _: ActivityDeleteResponseDTO = try await apiClient.callRPC(
            .deleteSeason,
            payload: ActivityRecordIdRequestDTO(id: id)
        )
    }

    func createEvent(
        seasonId: Int,
        name: String,
        host: String,
        location: String,
        startDate: Date?,
        endDate: Date?,
        notes: String
    ) async throws -> ActivityEventDTO {
        let response: ActivityEventResponseDTO = try await apiClient.callRPC(
            .createEvent,
            payload: CreateActivityEventRequestDTO(
                seasonId: seasonId,
                name: ActivityFieldLimit.name.clamp(name),
                host: ActivityFieldLimit.label.clamp(host),
                location: ActivityFieldLimit.name.clamp(location),
                startDate: ServerDateFormat.requestString(startDate),
                endDate: ServerDateFormat.requestString(endDate),
                notes: ActivityFieldLimit.notes.clamp(notes)
            )
        )
        return response.event
    }

    func updateEvent(
        id: Int,
        name: String,
        host: String,
        location: String,
        startDate: Date?,
        endDate: Date?,
        notes: String
    ) async throws -> ActivityEventDTO {
        let response: ActivityEventResponseDTO = try await apiClient.callRPC(
            .updateEvent,
            payload: UpdateActivityEventRequestDTO(
                id: id,
                name: ActivityFieldLimit.name.clamp(name),
                host: ActivityFieldLimit.label.clamp(host),
                location: ActivityFieldLimit.name.clamp(location),
                startDate: ServerDateFormat.requestString(startDate),
                endDate: ServerDateFormat.requestString(endDate),
                notes: ActivityFieldLimit.notes.clamp(notes)
            )
        )
        return response.event
    }

    func deleteEvent(id: Int) async throws {
        let _: ActivityDeleteResponseDTO = try await apiClient.callRPC(
            .deleteEvent,
            payload: ActivityRecordIdRequestDTO(id: id)
        )
    }

    func createEntry(
        seasonId: Int,
        name: String,
        format: String,
        style: String,
        division: String,
        level: String,
        notes: String,
        personIds: [Int]
    ) async throws -> EntryViewDTO {
        let response: ActivityEntryResponseDTO = try await apiClient.callRPC(
            .createEntry,
            payload: CreateActivityEntryRequestDTO(
                seasonId: seasonId,
                name: ActivityFieldLimit.name.clamp(name),
                format: ActivityFieldLimit.label.clamp(format),
                style: ActivityFieldLimit.label.clamp(style),
                division: ActivityFieldLimit.label.clamp(division),
                level: ActivityFieldLimit.label.clamp(level),
                notes: ActivityFieldLimit.notes.clamp(notes),
                personIds: personIds
            )
        )
        return response.entry
    }

    func updateEntry(
        id: Int,
        name: String,
        format: String,
        style: String,
        division: String,
        level: String,
        notes: String
    ) async throws -> EntryViewDTO {
        let response: ActivityEntryResponseDTO = try await apiClient.callRPC(
            .updateEntry,
            payload: UpdateActivityEntryRequestDTO(
                id: id,
                name: ActivityFieldLimit.name.clamp(name),
                format: ActivityFieldLimit.label.clamp(format),
                style: ActivityFieldLimit.label.clamp(style),
                division: ActivityFieldLimit.label.clamp(division),
                level: ActivityFieldLimit.label.clamp(level),
                notes: ActivityFieldLimit.notes.clamp(notes)
            )
        )
        return response.entry
    }

    /// Replaces the whole roster. Every person must already be on the owning family's roster.
    func setEntryRoster(entryId: Int, personIds: [Int]) async throws -> EntryViewDTO {
        let response: ActivityEntryResponseDTO = try await apiClient.callRPC(
            .setEntryRoster,
            payload: SetEntryRosterRequestDTO(entryId: entryId, personIds: personIds)
        )
        return response.entry
    }

    func deleteEntry(id: Int) async throws {
        let _: ActivityDeleteResponseDTO = try await apiClient.callRPC(
            .deleteEntry,
            payload: ActivityRecordIdRequestDTO(id: id)
        )
    }

    func setEventPhotos(eventId: Int, photoIds: [Int]) async throws -> [Int] {
        let response: SetEventPhotosResponseDTO = try await apiClient.callRPC(
            .setEventPhotos,
            payload: SetEventPhotosRequestDTO(eventId: eventId, photoIds: photoIds)
        )
        return response.photoIds
    }

    // MARK: - Internals

    /// Decode before caching, never after: caching a payload this build cannot read would make the failure permanent.
    private func read<Response: Decodable & Sendable, Request: Encodable & Sendable>(
        _ proc: RPCMethod,
        payload: Request,
        key: ActivitySnapshotKey
    ) -> ActivityRead<Response> {
        let apiClient = self.apiClient
        let cache = self.cache

        return ActivityRead(
            cached: { await cache.load(Response.self, key: key) },
            live: {
                let data = try await apiClient.callRPCData(proc, payload: payload)
                let value: Response
                do {
                    value = try APIClient.decode(Response.self, from: data)
                } catch {
                    throw APIError.decoding(error)
                }
                await cache.store(data, key: key)
                return value
            }
        )
    }
}

@Observable
@MainActor
final class ActivityScreenState<Value: Sendable> {

    private(set) var value: Value?
    private(set) var isLoading = false
    private(set) var isShowingCached = false
    private(set) var fetchedAt: Date?
    /// Set only when there is nothing at all to show; a failed refresh over a cached payload is reported by `isShowingCached`.
    private(set) var error: String?

    private var read: ActivityRead<Value>?

    func load(_ read: ActivityRead<Value>) async {
        self.read = read
        await refresh(read, consultingCache: true)
    }

    func reload() async {
        guard let read else { return }
        await refresh(read, consultingCache: false)
    }

    private func refresh(_ read: ActivityRead<Value>, consultingCache: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if consultingCache, value == nil, let snapshot = await read.cached() {
            value = snapshot.value
            fetchedAt = snapshot.fetchedAt
            isShowingCached = true
        }

        do {
            value = try await read.live()
            fetchedAt = Date()
            isShowingCached = false
            error = nil
        } catch {
            AppLog.activities.error(
                "Activities read failed: \(String(describing: error), privacy: .public)"
            )
            if value == nil {
                self.error = error.localizedDescription
            } else {
                isShowingCached = true
            }
        }
    }
}
