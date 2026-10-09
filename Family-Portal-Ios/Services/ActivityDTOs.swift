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

nonisolated struct ListSeasonsRequestDTO: Encodable, Sendable {
    let activityId: Int
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

nonisolated struct ListSeasonsResponseDTO: Decodable, Sendable {
    @OrZero var activityId: Int
    @OrZero var seasons: [SeasonDTO]
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

nonisolated struct CreateAppearanceRequestDTO: Encodable, Sendable {
    let eventId: Int
    let entryId: Int
    let occurredAt: String?
    let notes: String
}

nonisolated struct UpdateAppearanceRequestDTO: Encodable, Sendable {
    let id: Int
    let occurredAt: String?
    let notes: String
}

nonisolated struct AppearanceIdRequestDTO: Encodable, Sendable {
    let id: Int
}

nonisolated struct ResultInputDTO: Encodable, Sendable {
    let kind: String
    let label: String
    let rank: Int?
    let outOf: Int?
    let category: String
    let score: Double?
    let personId: Int?
    let notes: String
}

/// Replaces the whole set, so a save must carry every row the appearance should end up with.
nonisolated struct SetAppearanceResultsRequestDTO: Encodable, Sendable {
    let appearanceId: Int
    let results: [ResultInputDTO]
}

/// Whole-set write over *remote* photo ids; a photo still uploading cannot be attached.
nonisolated struct SetAppearancePhotosRequestDTO: Encodable, Sendable {
    let appearanceId: Int
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
