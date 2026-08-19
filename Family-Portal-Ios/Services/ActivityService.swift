import Foundation

/// One activities read, in the two halves a screen needs it in: what is already
/// on disk, and what the server says now.
///
/// A value rather than a pair of service methods so a view can hand the whole
/// read to `ActivityScreenState` and have the cache-then-live sequence run
/// itself — the alternative is every screen spelling out the same six lines and
/// one of them eventually getting the order wrong.
nonisolated struct ActivityRead<Value: Sendable>: Sendable {
    let cached: @Sendable () async -> ActivitySnapshot<Value>?
    let live: @Sendable () async throws -> Value
}

/// Reads the competitive-activities feature (backend/activity*.go).
///
/// Online-first with a snapshot cache, deliberately outside SwiftData and
/// `SyncQueue`:
///
/// - **The joins are already done.** `GetSeasonOverview` returns activity,
///   season, events, entries-with-rosters and appearances-with-results in one
///   payload. Modelling nine `@Model` classes and rebuilding those joins with
///   `@Query` is rewriting work the server does in one index walk, and it buys a
///   migration on `DataStore.container` for the trouble.
/// - **Every write is a whole-set replace with server-side cross-record
///   validation.** `CreateAppearance` refuses an entry from a different season
///   than the event, a result naming someone off the roster, a placement whose
///   rank exceeds its field. Those are exactly the refusals a device cannot
///   predict — the same reason `FamilyMembershipService` is not queued: a queued
///   write replayed hours later reports a success that never happened.
/// - **There is no delta protocol.** `GetFamilyTimeline` does not carry
///   activities, so a queued activity write would have nothing to reconcile
///   against on the next pull.
///
/// The cache exists because the venue has no signal, and reading stale data is
/// safe in a way that replaying stale writes is not.
@Observable
@MainActor
final class ActivityService {

    private let apiClient: APIClient
    private let cache: ActivitySnapshotCache

    /// Both injectable, the way `PhotoSyncService` and `FamilyMembershipService`
    /// take their client, so a test drives a fake backend and a scratch cache
    /// directory.
    init(apiClient: APIClient = .shared, cache: ActivitySnapshotCache = .shared) {
        self.apiClient = apiClient
        self.cache = cache
    }

    // MARK: - Reads

    /// The family's programs. `familyId: 0` means the caller's primary family.
    func activities(familyId: Int = 0) -> ActivityRead<ListActivitiesResponseDTO> {
        read(
            .listActivities,
            payload: ListActivitiesRequestDTO(familyId: familyId),
            key: ActivitySnapshotKey(.listActivities, familyId)
        )
    }

    /// One program's seasons, newest first. There is no proc that lists seasons
    /// across activities, which is why the root screen is 1 + N calls — and N is
    /// about 1.
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

    /// The headline read: a kid's routines, their results, their photos.
    ///
    /// `seasonId: 0` is every season the person has been in. This is also the
    /// one activities proc that is always safe to call for any person the app
    /// can see — it resolves through the roster rather than through the family,
    /// so a linked household reaches exactly the routines its shared child is
    /// in.
    func personSeason(personId: Int, seasonId: Int = 0) -> ActivityRead<GetPersonSeasonResponseDTO> {
        read(
            .getPersonSeason,
            payload: GetPersonSeasonRequestDTO(personId: personId, seasonId: seasonId),
            key: ActivitySnapshotKey(.getPersonSeason, personId, seasonId)
        )
    }

    /// What this family has already typed into each free-text field, for
    /// autocomplete. Cached with the rest, since a form opened at a venue needs
    /// it as much as a screen does.
    func vocabulary(activityId: Int) -> ActivityRead<ListActivityVocabularyResponseDTO> {
        read(
            .listActivityVocabulary,
            payload: ListActivityVocabularyRequestDTO(activityId: activityId),
            key: ActivitySnapshotKey(.listActivityVocabulary, activityId)
        )
    }

    // MARK: - Writes
    //
    // Online only, and never queued. `CreateAppearance` refuses an entry from a
    // different season than the event; `SetAppearanceResults` refuses a result
    // naming someone off the roster, a placement whose rank exceeds its field,
    // and a set larger than the appearance can hold. Those are refusals the
    // device cannot predict, and a queued write replayed hours later would
    // report a success that never happened.
    //
    // None of these touch the snapshot cache. The screen that wrote reloads
    // itself, which rewrites its own entry; other screens keep the payload they
    // last saw until they refresh. That is the deliberate trade: dropping their
    // caches would leave a phone at a venue with *nothing* on the routine screen
    // rather than something slightly behind, and the stale note already says
    // which it is.

    // Text is clamped here rather than at each call site. Over-length text is
    // silently *truncated* on write, not refused, so what a caller sends and
    // what the record ends up holding have to be the same thing — and a rule
    // enforced in one place is one a new form cannot forget.

    /// Files a routine at a competition. Both parents are checked against each
    /// other server-side — an entry from another season is `ErrEntryNotInSeason`
    /// — and two appearances of the same entry at the same event are allowed on
    /// purpose: a routine that dances its category and again in the overall
    /// round is two performances with two sets of results.
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

    /// Only the date and the notes. Which routine performed at which competition
    /// is the record's identity, not a field on it.
    ///
    /// `occurredAt: nil` **clears** the date rather than leaving it alone, so
    /// the caller must pass what it is currently showing.
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

    /// Takes the performance's results and photo attachments with it.
    func deleteAppearance(id: Int) async throws {
        let _: ActivityDeleteResponseDTO = try await apiClient.callRPC(
            .deleteAppearance,
            payload: AppearanceIdRequestDTO(id: id)
        )
    }

    /// Replaces the whole results sheet. `results` must be every row the
    /// appearance should end up with — the server deletes what it holds and
    /// writes these in array order, which is where `sortOrder` comes from.
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
    //
    // The annual setup half: creating the program, naming the season, entering
    // the routines and their rosters in September. Deliberately last and
    // deliberately plain — this is keyboard work that happens once a year, and
    // the phone only has to be able to do it, not be good at it.
    //
    // Names are required and trimmed to 200; every other text field is free by
    // design, because competitions do not agree on what a division or a level is
    // called and normalizing here would lose the distinction.

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

    /// Cascades through every season under the activity, and each of those
    /// through its competitions, routines, performances and results.
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

    /// Both dates are always sent. `UpdateSeason` assigns whatever
    /// `parseActivityDate` returns unconditionally, so omitting one does not
    /// leave it alone — it clears it.
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

    /// Cascades through every competition, routine, performance and result in
    /// the season.
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

    /// Cascades through every performance at the competition, and its own
    /// photos.
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

    /// The roster is not on this call — `setEntryRoster` owns it, and sending
    /// half a roster by accident is exactly what splitting them prevents.
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

    /// Replaces the whole roster. Every person must already be on the owning
    /// family's roster: a routine can hold children from two households, but
    /// only because the other household shared them in — this proc is not a
    /// second way to reach a person.
    func setEntryRoster(entryId: Int, personIds: [Int]) async throws -> EntryViewDTO {
        let response: ActivityEntryResponseDTO = try await apiClient.callRPC(
            .setEntryRoster,
            payload: SetEntryRosterRequestDTO(entryId: entryId, personIds: personIds)
        )
        return response.entry
    }

    /// Cascades through every performance of the routine.
    func deleteEntry(id: Int) async throws {
        let _: ActivityDeleteResponseDTO = try await apiClient.callRPC(
            .deleteEntry,
            payload: ActivityRecordIdRequestDTO(id: id)
        )
    }

    /// The competition's own photos, as a whole set over remote ids.
    func setEventPhotos(eventId: Int, photoIds: [Int]) async throws -> [Int] {
        let response: SetEventPhotosResponseDTO = try await apiClient.callRPC(
            .setEventPhotos,
            payload: SetEventPhotosRequestDTO(eventId: eventId, photoIds: photoIds)
        )
        return response.photoIds
    }

    // MARK: - Internals

    /// Decode before caching, never after: a payload this build cannot read is
    /// not worth keeping, and caching it would make the failure permanent until
    /// the next successful call.
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

/// What one activities screen is showing, and why.
///
/// The sequence is the same everywhere: render whatever the cache holds so the
/// screen is not blank, fire the live call, replace. A failure leaves the cached
/// payload in place and raises `isShowingCached` so the screen can say it is
/// showing what it last saw, rather than throwing an error over data the user
/// can still read.
///
/// `value == nil` with an `error` is deliberately a different state from a
/// `value` that happens to be empty. Offline-with-nothing-cached and
/// this-season-has-nothing-in-it are different screens; conflating them is how
/// the chat history bug read as *this family has no messages*.
@Observable
@MainActor
final class ActivityScreenState<Value: Sendable> {

    private(set) var value: Value?
    private(set) var isLoading = false
    /// True when `value` came off disk and the live call has not replaced it —
    /// either because it is still in flight or because it failed.
    private(set) var isShowingCached = false
    private(set) var fetchedAt: Date?
    /// Set only when there is nothing at all to show. A failed refresh over a
    /// cached payload is reported by `isShowingCached`, not here.
    private(set) var error: String?

    private var read: ActivityRead<Value>?

    /// Loads the screen: cache first if there is nothing on it yet, then the
    /// server. Safe to call again — `.task` re-fires on a view that comes back.
    func load(_ read: ActivityRead<Value>) async {
        self.read = read
        await refresh(read, consultingCache: true)
    }

    /// Pull to refresh. Goes straight to the server: the user asking again is
    /// asking for what the server has now, and the cache is what they are
    /// already looking at.
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
                // There is still something on screen, and it is honest about
                // being old. An alert here would interrupt a reader to tell
                // them something they can already see.
                isShowingCached = true
            }
        }
    }
}
