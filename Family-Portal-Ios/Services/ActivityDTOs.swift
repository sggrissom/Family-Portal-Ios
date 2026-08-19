import Foundation

// Wire types for the competitive-activities procs (backend/activity*.go).
//
// Four renames the wire does not have, all for the same reason `FamilyTag` is
// not `Tag`: the short name is taken by something in the standard library or by
// something the reader will confuse it with.
//
//   Go `Result`     → `ActivityResultDTO`   `Result` is a Swift stdlib type, and
//                                           a bare one in a `throws` context is
//                                           a genuine misreading hazard.
//   Go `Event`      → `ActivityEventDTO`    A bare `Event` next to SwiftUI event
//                                           handling reads badly. Not
//                                           `CompetitionDTO`: that bakes the
//                                           dance vocabulary the label pack
//                                           exists to keep out of the types.
//   Go `Entry`      → `ActivityEntryDTO`
//   Go `Appearance` → `AppearanceDTO`
//
// Three encoding traps this file answers, all from §4.3 of the plan:
//
//   1. Absent dates arrive as year 1, not as null. `StartDate`, `EndDate` and
//      `OccurredAt` are non-pointer `time.Time`, so "not known yet" — an
//      explicitly normal state — marshals as "0001-01-01T00:00:00Z". Read every
//      one of them through `Date.isServerZero` / `Date.serverDate` before
//      formatting, or the UI prints *Jan 1, 1* where the web prints nothing.
//   2. Optional numbers are omitted, not null. `rank`, `outOf`, `score` and
//      `personId` are `*T` with `omitempty`, and the backend packs them through
//      `packOptionalInt` precisely so "no placement" stays distinguishable from
//      "1st". They are `Optional` here and must never be defaulted to 0.
//   3. Collections are decoded as absent-means-empty. Every list-bearing getter
//      in backend/activity.go returns `[]T{}` rather than a nil slice today, so
//      none of them marshal as `null` — this is insurance, not a fix, and it is
//      the cheap direction to be wrong in: an empty list renders as an empty
//      list, a decode failure takes the whole screen down.
//
// Responses are `Decodable` only. The snapshot cache stores the raw response
// body rather than a re-encoding of these types, so nothing ever needs to
// serialize one back.

// MARK: - Decoding helpers

private extension KeyedDecodingContainer {
    /// Trap #3: a list the server omitted, or sent as `null`, is an empty list.
    nonisolated func decodeList<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent([T].self, forKey: key) ?? []
    }
}

// MARK: - Records

/// A program the family participates in: "Dance". `kind` drives vocabulary via
/// `ActivityLabels` and nothing else.
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
    /// Trap #1.
    let startDate: Date
    let endDate: Date
    let notes: String
    let createdAt: Date
}

/// Go's `Event`: one competition, game, meet or tournament.
nonisolated struct ActivityEventDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let seasonId: Int
    let familyId: Int
    let name: String
    /// Free text: "Nuvo", "Showstopper".
    let host: String
    let location: String
    /// Trap #1. `endDate` is zero for a single-day event, which is the common case.
    let startDate: Date
    let endDate: Date
    let notes: String
    let createdAt: Date
}

/// Go's `Entry`: the recurring competitive unit within a season — a routine, a
/// team, a swim event. Everything but `name` is free text by design; different
/// competitions do not agree on what a division or a level is called.
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

/// One entry at one event — the hinge the whole schema turns on.
nonisolated struct AppearanceDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let eventId: Int
    let entryId: Int
    let familyId: Int
    /// Trap #1, and zero here is ordinary rather than exceptional: "sometime
    /// that weekend" is a normal state for a competition schedule, and the
    /// backend's own ordering falls back to the event's start date when it sees
    /// one.
    let occurredAt: Date
    let notes: String
    let createdAt: Date
}

/// Go's `Result`. One flat record with a `kind` discriminator; the fields a
/// placement uses and the ones a score uses are disjoint.
nonisolated struct ActivityResultDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let appearanceId: Int
    let familyId: Int
    /// One of `ActivityResultKind`. Unlike `Activity.kind`, an unrecognized
    /// value here is not degraded to a default on write — `normalizeResultKind`
    /// rejects it, because `kind` decides which field carries the meaning.
    let kind: String
    let label: String
    /// Trap #2: absent means "no placement", never 1st.
    let rank: Int?
    let outOf: Int?
    let category: String
    let score: Double?
    /// Narrows an award to one person on the entry's roster.
    let personId: Int?
    let notes: String
    /// Display order within an appearance, assigned by the server from array
    /// position — `ResultInput` carries no sort order of its own.
    let sortOrder: Int
    let createdAt: Date
}

/// The `Result.kind` values (backend/activity.go).
nonisolated enum ActivityResultKind: String, CaseIterable, Sendable {
    case adjudication
    case placement
    case award
    case score
}

// MARK: - Views

/// An entry with its roster, which is how every caller wants it: an entry
/// without its people cannot be rendered or access-checked.
nonisolated struct EntryViewDTO: Decodable, Sendable, Identifiable {
    let entry: ActivityEntryDTO
    /// *Server* person ids, like `Milestone.photoRemoteIds` — resolve what the
    /// local store knows and render the rest as nothing.
    let personIds: [Int]

    var id: Int { entry.id }

    private enum CodingKeys: String, CodingKey { case entry, personIds }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entry = try container.decode(ActivityEntryDTO.self, forKey: .entry)
        personIds = try container.decodeList(Int.self, forKey: .personIds)
    }
}

/// An appearance with its results and photos — the only useful shape, since an
/// appearance alone says a routine turned up and nothing about how it went.
nonisolated struct AppearanceViewDTO: Decodable, Sendable, Identifiable {
    let appearance: AppearanceDTO
    let results: [ActivityResultDTO]
    /// Filtered per caller by `visiblePhotoIds`, so these are ids this session
    /// can actually load — but not necessarily ones this device has pulled.
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

/// One row of either roster-scoped view. It carries both the entry that
/// performed and the competition it happened at, even though the caller already
/// knows one of them, so one row component renders a performance wherever it
/// appears.
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

/// The parent context a record needs to be readable, and nothing more. These
/// exist because the roster-scoped views cross a link boundary.
nonisolated struct SeasonSummaryDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    /// The owning activity's kind, carried here because it is what selects the
    /// label pack. Read the pack from this wherever the response has no
    /// `ActivityDTO` — a season that arrives without it renders as "Event",
    /// which is the one word the label map exists to avoid.
    let kind: String
    /// Trap #1.
    let startDate: Date
    let endDate: Date
}

nonisolated struct EventSummaryDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let host: String
    let location: String
    /// Trap #1.
    let startDate: Date
    let endDate: Date
}

// MARK: - Requests

nonisolated struct ListActivitiesRequestDTO: Encodable, Sendable {
    /// Zero means the caller's primary family, matching the Go fallback — the
    /// same convention `FamilyMembershipService` uses. This and
    /// `CreateActivity` are the only activities requests that carry a family
    /// id; everything below activity level is reached by its own id.
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
    /// Zero means every season the person has ever been in. A linked household
    /// cannot list seasons — those have no person dimension — so requiring one
    /// would leave it with no way to ask the question at all.
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
    /// Newest first: a season list is almost always consulted to get at the
    /// current season.
    let seasons: [SeasonDTO]

    private enum CodingKeys: String, CodingKey { case activityId, seasons }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activityId = try container.decodeIfPresent(Int.self, forKey: .activityId) ?? 0
        seasons = try container.decodeList(SeasonDTO.self, forKey: .seasons)
    }
}

/// Events and entries ship once each and appearances as the bare hinge, rather
/// than repeating the parents on every row. The client joins on `entryId` and
/// `eventId`, which it already has — see `SeasonView`.
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
    /// The competition's *own* photos — the weekend shots that are not of any
    /// one routine. A routine's photos travel with its appearance.
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
    /// Echoes the request: zero means every season the person has been in.
    let seasonId: Int
    /// Only the seasons the returned entries belong to.
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

/// One list per free-text field, so a form can autocomplete each one from what
/// this family has already typed. Not a nicety: adjudication labels are free
/// text by design and nothing normalizes them at write time, so without
/// suggestions "High Gold" becomes "high gold" and the season view cannot even
/// count them, let alone rank them.
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
//
// Trap #5, and it is the one that loses data quietly: request dates are
// `*string` in `YYYY-MM-DD`, and **nil clears**. `UpdateAppearance` and
// `UpdateSeason` assign whatever `parseActivityDate` returns unconditionally, so
// omitting the key does *not* mean "leave it alone" — it means "set it to
// unknown". An editor must always send the value it is currently showing.
//
// Swift's synthesized encoding uses `encodeIfPresent` for an `Optional`
// property, so `nil` here omits the key, which is exactly the clear. That is the
// intended behaviour and not an accident: `ActivityDateText.request` turns the
// screen's `Date?` into this field, and a screen that has no date genuinely
// means "unknown".

nonisolated struct CreateAppearanceRequestDTO: Encodable, Sendable {
    let eventId: Int
    let entryId: Int
    /// `YYYY-MM-DD`; absent means "sometime that weekend", which is a normal
    /// state for a competition schedule rather than missing information.
    let occurredAt: String?
    let notes: String
}

/// Deliberately cannot move an appearance to a different event or entry: which
/// routine performed at which competition is the identity of the record, not a
/// field on it. A misfiled one is deleted and re-entered, which also makes it
/// obvious that its results went with it.
nonisolated struct UpdateAppearanceRequestDTO: Encodable, Sendable {
    let id: Int
    let occurredAt: String?
    let notes: String
}

nonisolated struct AppearanceIdRequestDTO: Encodable, Sendable {
    let id: Int
}

/// A `Result` without the fields the server owns.
///
/// There is no sort order: position in the array *is* the order, so reordering a
/// results sheet is a reordered array rather than a second field to keep in
/// sync. The optional numbers are `encodeIfPresent` for the same reason they are
/// `decodeIfPresent` coming back — a `0` rank is not "no rank", it is a rank the
/// server refuses.
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

/// Replaces the whole set. Results arrive together off one sheet and are entered
/// together, so replace-all is the honest shape — and it means a save must carry
/// every row the appearance should end up with, never just the changed ones.
nonisolated struct SetAppearanceResultsRequestDTO: Encodable, Sendable {
    let appearanceId: Int
    let results: [ResultInputDTO]
}

/// Also a whole-set write, over *remote* photo ids. A photo still uploading has
/// no remote id and cannot be attached; since this path is online-only there is
/// nothing to resolve later.
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
