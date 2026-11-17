import Foundation

// Wire types for the competitive-activities procs (backend/activity*.go).
// Absent dates arrive as year 1 rather than null; read them through `Date.serverDate`.

// MARK: - Records

nonisolated struct ActivityDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let familyId: Int
    let name: String
    let kind: String
    let createdAt: Date
}

nonisolated struct SeasonDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let activityId: Int
    let familyId: Int
    let name: String
    let startDate: Date
    let endDate: Date
    let notes: String
    let createdAt: Date
}

nonisolated struct ActivityEventDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let seasonId: Int
    let familyId: Int
    let name: String
    let host: String
    let location: String
    let startDate: Date
    let endDate: Date
    let notes: String
    let createdAt: Date
}

nonisolated struct ActivityEntryDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let seasonId: Int
    let familyId: Int
    let name: String
    let format: String
    let style: String
    let division: String
    let level: String
    let notes: String
    let createdAt: Date
}

nonisolated struct AppearanceDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let eventId: Int
    let entryId: Int
    let familyId: Int
    let occurredAt: Date
    let notes: String
    let createdAt: Date
    /// The head-to-head fields (`Matchup`), flat on the record. Absent from servers older than matchups; the scores are omitted when no score was kept.
    @OrZero var round: String
    @OrZero var opponent: String
    @OrZero var outcome: String
    var scoreFor: Int? = nil
    var scoreAgainst: Int? = nil
    /// Advances on every change to the performance, its results and its photos, wherever it was made. Absent (0) from servers older than revisions; see `SyncSaveAppearance`.
    @OrZero var revision: Int
}

nonisolated struct ActivityResultDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let appearanceId: Int
    let familyId: Int
    let kind: String
    let label: String
    /// Absent means "no placement", never 1st.
    let rank: Int?
    let outOf: Int?
    let category: String
    let score: Double?
    let personId: Int?
    let notes: String
    let sortOrder: Int
    let createdAt: Date
}

nonisolated enum ActivityResultKind: String, CaseIterable, Sendable {
    case adjudication
    case placement
    case award
    case score
}

// MARK: - Views

nonisolated struct EntryViewDTO: Decodable, Sendable, Identifiable {
    let entry: ActivityEntryDTO
    /// *Server* person ids — resolve what the local store knows, render the rest as nothing.
    @OrZero var personIds: [Int]

    var id: Int { entry.id }
}

nonisolated struct AppearanceViewDTO: Decodable, Sendable, Identifiable {
    let appearance: AppearanceDTO
    @OrZero var results: [ActivityResultDTO]
    @OrZero var photoIds: [Int]

    var id: Int { appearance.id }
}

nonisolated struct AppearanceDetailDTO: Decodable, Sendable, Identifiable {
    let appearance: AppearanceDTO
    @OrZero var results: [ActivityResultDTO]
    @OrZero var photoIds: [Int]
    let entry: ActivityEntryDTO
    let event: EventSummaryDTO

    var id: Int { appearance.id }
}

nonisolated struct SeasonSummaryDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let kind: String
    let startDate: Date
    let endDate: Date
}

nonisolated struct EventSummaryDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let host: String
    let location: String
    let startDate: Date
    let endDate: Date
}

// MARK: - Requests

nonisolated struct ListActivitiesRequestDTO: Encodable, Sendable {
    let familyId: Int
}

nonisolated struct GetSeasonOverviewRequestDTO: Encodable, Sendable {
    let seasonId: Int
}

nonisolated struct GetEventDetailRequestDTO: Encodable, Sendable {
    let eventId: Int
}

nonisolated struct GetEntryHistoryRequestDTO: Encodable, Sendable {
    let entryId: Int
}

nonisolated struct GetPersonSeasonRequestDTO: Encodable, Sendable {
    let personId: Int
    let seasonId: Int
}

nonisolated struct ListActivityVocabularyRequestDTO: Encodable, Sendable {
    let activityId: Int
}

// MARK: - Responses

nonisolated struct ListActivitiesResponseDTO: Decodable, Sendable {
    @OrZero var familyId: Int
    @OrZero var activities: [ActivityDTO]
}

nonisolated struct HomeEventDTO: Decodable, Sendable, Identifiable {
    let event: ActivityEventDTO
    /// How many performances are recorded there.
    @OrZero var appearances: Int

    var id: Int { event.id }
}

nonisolated struct HomeSeasonDTO: Decodable, Sendable, Identifiable {
    let season: SeasonDTO
    @OrZero var events: [HomeEventDTO]
    @OrZero var entries: [EntryViewDTO]

    var id: Int { season.id }
}

nonisolated struct GetActivitiesHomeResponseDTO: Decodable, Sendable {
    @OrZero var familyId: Int
    @OrZero var activities: [ActivityDTO]
    @OrZero var seasons: [HomeSeasonDTO]
}

nonisolated struct GetSeasonOverviewResponseDTO: Decodable, Sendable {
    let activity: ActivityDTO
    let season: SeasonDTO
    @OrZero var events: [ActivityEventDTO]
    @OrZero var entries: [EntryViewDTO]
    @OrZero var appearances: [AppearanceViewDTO]
}

nonisolated struct GetEventDetailResponseDTO: Decodable, Sendable {
    let event: ActivityEventDTO
    let season: SeasonSummaryDTO
    @OrZero var photoIds: [Int]
    @OrZero var appearances: [AppearanceDetailDTO]
}

nonisolated struct GetEntryHistoryResponseDTO: Decodable, Sendable {
    let entry: EntryViewDTO
    let season: SeasonSummaryDTO
    @OrZero var appearances: [AppearanceDetailDTO]
}

nonisolated struct GetPersonSeasonResponseDTO: Decodable, Sendable {
    @OrZero var personId: Int
    @OrZero var seasonId: Int
    @OrZero var seasons: [SeasonSummaryDTO]
    @OrZero var entries: [EntryViewDTO]
    @OrZero var appearances: [AppearanceDetailDTO]
}

nonisolated struct ListActivityVocabularyResponseDTO: Decodable, Sendable {
    @OrZero var activityId: Int
    @OrZero var adjudications: [String]
    @OrZero var awards: [String]
    @OrZero var categories: [String]
    @OrZero var styles: [String]
    @OrZero var divisions: [String]
    @OrZero var levels: [String]
    @OrZero var formats: [String]
    @OrZero var hosts: [String]
}

// MARK: - Write requests
// Dates are `YYYY-MM-DD` strings and **nil clears**, so an editor must always send the value it is showing.

nonisolated struct MatchupInputDTO: Codable, Sendable, Equatable {
    let round: String
    let opponent: String
    /// `""`, `"win"`, `"loss"` or `"draw"`; anything else is refused.
    let outcome: String
    /// 0–9999, omitted when no score was kept.
    let scoreFor: Int?
    let scoreAgainst: Int?
}

nonisolated struct AppearanceIdRequestDTO: Encodable, Sendable {
    let id: Int
}

nonisolated struct ResultInputDTO: Codable, Sendable, Equatable {
    let kind: String
    let label: String
    let rank: Int?
    let outOf: Int?
    let category: String
    let score: Double?
    let personId: Int?
    let notes: String
}

/// `SaveAppearance`: creates the appearance when `id` is 0 (from `eventId` and `entryId`, which an update ignores), then replaces its whole results sheet and its whole photo set.
nonisolated struct SaveAppearanceRequestDTO: Codable, Sendable, Equatable {
    let id: Int
    let eventId: Int
    let entryId: Int
    /// `nil` stores no date.
    let occurredAt: String?
    let notes: String
    /// Absent leaves the stored matchup alone, an empty one clears it.
    let matchup: MatchupInputDTO?
    let results: [ResultInputDTO]
    let photoIds: [Int]
}

// MARK: - Write responses

nonisolated struct AppearanceResponseDTO: Decodable, Sendable {
    let appearance: AppearanceViewDTO
}

nonisolated struct ActivityDeleteResponseDTO: Decodable, Sendable {
    let success: Bool
}

// MARK: - Structure write requests

nonisolated struct ActivityRecordIdRequestDTO: Encodable, Sendable {
    let id: Int
}

nonisolated struct CreateActivityRequestDTO: Encodable, Sendable {
    let familyId: Int
    let name: String
    let kind: String
}

nonisolated struct UpdateActivityRequestDTO: Encodable, Sendable {
    let id: Int
    let name: String
    let kind: String
}

nonisolated struct ActivityRecordResponseDTO: Decodable, Sendable {
    let activity: ActivityDTO
}

nonisolated struct CreateSeasonRequestDTO: Encodable, Sendable {
    let activityId: Int
    let name: String
    let startDate: String?
    let endDate: String?
    let notes: String
}

nonisolated struct UpdateSeasonRequestDTO: Encodable, Sendable {
    let id: Int
    let name: String
    let startDate: String?
    let endDate: String?
    let notes: String
}

nonisolated struct SeasonResponseDTO: Decodable, Sendable {
    let season: SeasonDTO
}

nonisolated struct CreateActivityEventRequestDTO: Encodable, Sendable {
    let seasonId: Int
    let name: String
    let host: String
    let location: String
    let startDate: String?
    let endDate: String?
    let notes: String
}

nonisolated struct UpdateActivityEventRequestDTO: Encodable, Sendable {
    let id: Int
    let name: String
    let host: String
    let location: String
    let startDate: String?
    let endDate: String?
    let notes: String
}

nonisolated struct ActivityEventResponseDTO: Decodable, Sendable {
    let event: ActivityEventDTO
}

nonisolated struct CreateActivityEntryRequestDTO: Encodable, Sendable {
    let seasonId: Int
    let name: String
    let format: String
    let style: String
    let division: String
    let level: String
    let notes: String
    /// Absent leaves the roster empty; `nil` and `[]` mean the same thing here.
    let personIds: [Int]?
}

nonisolated struct UpdateActivityEntryRequestDTO: Encodable, Sendable {
    let id: Int
    let name: String
    let format: String
    let style: String
    let division: String
    let level: String
    let notes: String
}

nonisolated struct SetEntryRosterRequestDTO: Encodable, Sendable {
    let entryId: Int
    let personIds: [Int]
}

nonisolated struct ActivityEntryResponseDTO: Decodable, Sendable {
    let entry: EntryViewDTO
}

nonisolated struct SetEventPhotosRequestDTO: Encodable, Sendable {
    let eventId: Int
    let photoIds: [Int]
}

nonisolated struct SetEventPhotosResponseDTO: Decodable, Sendable {
    @OrZero var eventId: Int
    @OrZero var photoIds: [Int]
}

// MARK: - Local updates
// Built here rather than beside their callers: an `@OrZero` field's storage is private to this file.

nonisolated extension EventSummaryDTO {
    init(_ event: ActivityEventDTO) {
        self.init(
            id: event.id,
            name: event.name,
            host: event.host,
            location: event.location,
            startDate: event.startDate,
            endDate: event.endDate
        )
    }
}

nonisolated extension AppearanceDetailDTO {
    /// A saved performance as a competition page lists it: the save response plus the routine and competition it belongs to.
    init(view: AppearanceViewDTO, entry: ActivityEntryDTO, event: EventSummaryDTO) {
        appearance = view.appearance
        _results = OrZero(wrappedValue: view.results)
        _photoIds = OrZero(wrappedValue: view.photoIds)
        self.entry = entry
        self.event = event
    }
}

nonisolated extension GetEventDetailResponseDTO {
    func replacingAppearances(_ appearances: [AppearanceDetailDTO]) -> GetEventDetailResponseDTO {
        GetEventDetailResponseDTO(copying: self, appearances: appearances)
    }

    private init(copying other: GetEventDetailResponseDTO, appearances: [AppearanceDetailDTO]) {
        event = other.event
        season = other.season
        _photoIds = OrZero(wrappedValue: other.photoIds)
        _appearances = OrZero(wrappedValue: appearances)
    }
}

nonisolated extension ResultInputDTO {
    /// A stored result as the input that would write it again.
    init(_ result: ActivityResultDTO) {
        self.init(
            kind: result.kind,
            label: result.label,
            rank: result.rank,
            outOf: result.outOf,
            category: result.category,
            score: result.score,
            personId: result.personId,
            notes: result.notes
        )
    }
}

// MARK: - Queued writes (backend/activity_mutations.go)

/// The contract version this build speaks. Queued results go only to a server reporting it.
nonisolated enum ActivityMutationContract {
    static let version = 1
}

nonisolated struct ActivitySyncSupportResponseDTO: Decodable, Sendable {
    @OrZero var mutationVersion: Int
}

/// Codable so the outbox can keep the exact request it first sent and send that again: the server binds the mutation id to it.
nonisolated struct SyncSaveAppearanceRequestDTO: Codable, Sendable, Equatable {
    let mutationId: String
    /// `nil` on a create; required on an edit.
    let expectedRevision: Int?
    let appearance: SaveAppearanceRequestDTO
}

nonisolated struct SyncDeleteAppearanceRequestDTO: Codable, Sendable, Equatable {
    let mutationId: String
    let id: Int
    let expectedRevision: Int
}

nonisolated struct AppearanceMutationResponseDTO: Decodable, Sendable {
    /// `AppearanceMutationStatus`'s raw value; an unknown one is treated as a failure to retry.
    let status: String
    @OrZero var appearanceId: Int
    @OrZero var revision: Int
    var appearance: AppearanceViewDTO? = nil
    @OrZero var code: String
    @OrZero var message: String
}

nonisolated enum AppearanceMutationStatus: String, Sendable {
    case applied, replayed, conflict, deleted, notFound, forbidden, invalid
}
