import Foundation

// Wire types for the competitive-activities procs (backend/activity*.go).
// Absent dates arrive as year 1 rather than null; read them through `Date.serverDate`.

// MARK: - Decoding helpers

private extension KeyedDecodingContainer {
    nonisolated func decodeList<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent([T].self, forKey: key) ?? []
    }
}

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
    let personIds: [Int]

    var id: Int { entry.id }

    private enum CodingKeys: String, CodingKey { case entry, personIds }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entry = try container.decode(ActivityEntryDTO.self, forKey: .entry)
        personIds = try container.decodeList(Int.self, forKey: .personIds)
    }
}

nonisolated struct AppearanceViewDTO: Decodable, Sendable, Identifiable {
    let appearance: AppearanceDTO
    let results: [ActivityResultDTO]
    let photoIds: [Int]

    var id: Int { appearance.id }

    private enum CodingKeys: String, CodingKey { case appearance, results, photoIds }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try container.decode(AppearanceDTO.self, forKey: .appearance)
        results = try container.decodeList(ActivityResultDTO.self, forKey: .results)
        photoIds = try container.decodeList(Int.self, forKey: .photoIds)
    }
}

nonisolated struct AppearanceDetailDTO: Decodable, Sendable, Identifiable {
    let appearance: AppearanceDTO
    let results: [ActivityResultDTO]
    let photoIds: [Int]
    let entry: ActivityEntryDTO
    let event: EventSummaryDTO

    var id: Int { appearance.id }

    private enum CodingKeys: String, CodingKey {
        case appearance, results, photoIds, entry, event
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try container.decode(AppearanceDTO.self, forKey: .appearance)
        results = try container.decodeList(ActivityResultDTO.self, forKey: .results)
        photoIds = try container.decodeList(Int.self, forKey: .photoIds)
        entry = try container.decode(ActivityEntryDTO.self, forKey: .entry)
        event = try container.decode(EventSummaryDTO.self, forKey: .event)
    }
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
    let familyId: Int
    let activities: [ActivityDTO]

    private enum CodingKeys: String, CodingKey { case familyId, activities }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        familyId = try container.decodeIfPresent(Int.self, forKey: .familyId) ?? 0
        activities = try container.decodeList(ActivityDTO.self, forKey: .activities)
    }
}

nonisolated struct ListSeasonsResponseDTO: Decodable, Sendable {
    let activityId: Int
    let seasons: [SeasonDTO]

    private enum CodingKeys: String, CodingKey { case activityId, seasons }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityId = try container.decodeIfPresent(Int.self, forKey: .activityId) ?? 0
        seasons = try container.decodeList(SeasonDTO.self, forKey: .seasons)
    }
}

nonisolated struct GetSeasonOverviewResponseDTO: Decodable, Sendable {
    let activity: ActivityDTO
    let season: SeasonDTO
    let events: [ActivityEventDTO]
    let entries: [EntryViewDTO]
    let appearances: [AppearanceViewDTO]

    private enum CodingKeys: String, CodingKey {
        case activity, season, events, entries, appearances
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activity = try container.decode(ActivityDTO.self, forKey: .activity)
        season = try container.decode(SeasonDTO.self, forKey: .season)
        events = try container.decodeList(ActivityEventDTO.self, forKey: .events)
        entries = try container.decodeList(EntryViewDTO.self, forKey: .entries)
        appearances = try container.decodeList(AppearanceViewDTO.self, forKey: .appearances)
    }
}

nonisolated struct GetEventDetailResponseDTO: Decodable, Sendable {
    let event: ActivityEventDTO
    let season: SeasonSummaryDTO
    let photoIds: [Int]
    let appearances: [AppearanceDetailDTO]

    private enum CodingKeys: String, CodingKey {
        case event, season, photoIds, appearances
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(ActivityEventDTO.self, forKey: .event)
        season = try container.decode(SeasonSummaryDTO.self, forKey: .season)
        photoIds = try container.decodeList(Int.self, forKey: .photoIds)
        appearances = try container.decodeList(AppearanceDetailDTO.self, forKey: .appearances)
    }
}

nonisolated struct GetEntryHistoryResponseDTO: Decodable, Sendable {
    let entry: EntryViewDTO
    let season: SeasonSummaryDTO
    let appearances: [AppearanceDetailDTO]

    private enum CodingKeys: String, CodingKey { case entry, season, appearances }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entry = try container.decode(EntryViewDTO.self, forKey: .entry)
        season = try container.decode(SeasonSummaryDTO.self, forKey: .season)
        appearances = try container.decodeList(AppearanceDetailDTO.self, forKey: .appearances)
    }
}

nonisolated struct GetPersonSeasonResponseDTO: Decodable, Sendable {
    let personId: Int
    let seasonId: Int
    let seasons: [SeasonSummaryDTO]
    let entries: [EntryViewDTO]
    let appearances: [AppearanceDetailDTO]

    private enum CodingKeys: String, CodingKey {
        case personId, seasonId, seasons, entries, appearances
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        personId = try container.decodeIfPresent(Int.self, forKey: .personId) ?? 0
        seasonId = try container.decodeIfPresent(Int.self, forKey: .seasonId) ?? 0
        seasons = try container.decodeList(SeasonSummaryDTO.self, forKey: .seasons)
        entries = try container.decodeList(EntryViewDTO.self, forKey: .entries)
        appearances = try container.decodeList(AppearanceDetailDTO.self, forKey: .appearances)
    }
}

nonisolated struct ListActivityVocabularyResponseDTO: Decodable, Sendable {
    let activityId: Int
    let adjudications: [String]
    let awards: [String]
    let categories: [String]
    let styles: [String]
    let divisions: [String]
    let levels: [String]
    let formats: [String]
    let hosts: [String]

    private enum CodingKeys: String, CodingKey {
        case activityId, adjudications, awards, categories
        case styles, divisions, levels, formats, hosts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityId = try container.decodeIfPresent(Int.self, forKey: .activityId) ?? 0
        adjudications = try container.decodeList(String.self, forKey: .adjudications)
        awards = try container.decodeList(String.self, forKey: .awards)
        categories = try container.decodeList(String.self, forKey: .categories)
        styles = try container.decodeList(String.self, forKey: .styles)
        divisions = try container.decodeList(String.self, forKey: .divisions)
        levels = try container.decodeList(String.self, forKey: .levels)
        formats = try container.decodeList(String.self, forKey: .formats)
        hosts = try container.decodeList(String.self, forKey: .hosts)
    }
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
    let eventId: Int
    let photoIds: [Int]

    private enum CodingKeys: String, CodingKey { case eventId, photoIds }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try container.decodeIfPresent(Int.self, forKey: .eventId) ?? 0
        photoIds = try container.decodeIfPresent([Int].self, forKey: .photoIds) ?? []
    }
}
