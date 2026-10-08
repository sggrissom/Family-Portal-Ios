import Foundation

// The aggregate reads the redesign renders — Home (`GetDashboard`), the add sheet's Result shortcuts (`ListOpenEvents`), and Same age (`GetSameAge`). backend/dashboard.go and backend/same_age.go.
// The server decides what is in them: which nudges exist, which events are open, which records count as "at this age". The app renders the answer and never re-derives it.
// Every list is decoded with `decodeList`, since Go marshals a nil slice as `null`.

// MARK: - Requests

/// `today` is the **device's** calendar day. The server's own date is a UTC day and can be one off for the family.
nonisolated struct TodayRequestDTO: Encodable, Sendable {
    let today: String
}

/// `ageMonths` nil starts from the person's current age — or, with no person, the youngest own child's. 0 is birth, not "unset", so it is encoded explicitly.
/// `includeAvailableAges` is for the full browse page only: it makes the server scan the family's photo history for the ages worth offering, which a record's strip has no use for. With it and neither an age nor a person, the server starts at the richest comparison — by portraits, or by every record when `details` is set.
nonisolated struct GetSameAgeRequestDTO: Encodable, Sendable, Hashable {
    let ageMonths: Int?
    let fromPersonId: Int
    let today: String
    var includeAvailableAges = false
    var details = false

    private enum CodingKeys: String, CodingKey { case ageMonths, fromPersonId, today, includeAvailableAges, details }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let ageMonths {
            try container.encode(ageMonths, forKey: .ageMonths)
        } else {
            try container.encodeNil(forKey: .ageMonths)
        }
        try container.encode(fromPersonId, forKey: .fromPersonId)
        try container.encode(today, forKey: .today)
        // The Go tags' `omitempty`: a strip's request is the same body it always was.
        if includeAvailableAges { try container.encode(true, forKey: .includeAvailableAges) }
        if details { try container.encode(true, forKey: .details) }
    }
}

/// `GetFamilyTimelineRequest`. The sync pull sends none of these (the whole record); History sends a window with `includeActivities` to fetch the appearances SwiftData does not hold.
nonisolated struct GetFamilyTimelineRequestDTO: Encodable, Sendable {
    var from: String?
    var to: String?
    var skipMilestones = false
    var skipPhotos = false
    var includeActivities = false

    private enum CodingKeys: String, CodingKey { case from, to, skipMilestones, skipPhotos, includeActivities }

    /// Mirrors the Go tags' `omitempty`, so an unwindowed pull is the same `{}` it always was.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(to, forKey: .to)
        if skipMilestones { try container.encode(true, forKey: .skipMilestones) }
        if skipPhotos { try container.encode(true, forKey: .skipPhotos) }
        if includeActivities { try container.encode(true, forKey: .includeActivities) }
    }
}

// MARK: - GetDashboard

nonisolated struct DashboardNudgeDTO: Decodable, Sendable, Identifiable, Equatable {
    /// "measure", "birthday" or "faces". Kept as a string: a kind added server-side still renders its text.
    let kind: String
    /// Stable per occurrence (`birthday:4:2026`), which is what a dismissal remembers.
    let key: String
    let text: String
    let personId: Int
    let count: Int

    var id: String { key }

    private enum CodingKeys: String, CodingKey { case kind, key, text, personId, count }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        key = try container.decode(String.self, forKey: .key)
        text = try container.decode(String.self, forKey: .text)
        personId = try container.decodeIfPresent(Int.self, forKey: .personId) ?? 0
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

nonisolated struct DashboardSeasonDTO: Decodable, Sendable, Identifiable {
    let season: SeasonSummaryDTO
    let activityName: String
    /// The event running today, else the next, else the last. Absent for a season with no events yet.
    let event: EventSummaryDTO?
    /// "now", "next" or "last" — `Copy.home.eventTiming` words it.
    let eventTiming: String
    /// Whether the account may add to this season at all — false for a view-only member, who sees the season but none of its add buttons. A server older than the field leaves it out, which keeps the buttons as they were.
    let canContribute: Bool
    let canAddResults: Bool

    var id: Int { season.id }

    private enum CodingKeys: String, CodingKey { case season, activityName, event, eventTiming, canContribute, canAddResults }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        season = try container.decode(SeasonSummaryDTO.self, forKey: .season)
        activityName = try container.decodeIfPresent(String.self, forKey: .activityName) ?? ""
        event = try container.decodeIfPresent(EventSummaryDTO.self, forKey: .event)
        eventTiming = try container.decodeIfPresent(String.self, forKey: .eventTiming) ?? ""
        canContribute = try container.decodeIfPresent(Bool.self, forKey: .canContribute) ?? true
        canAddResults = try container.decodeIfPresent(Bool.self, forKey: .canAddResults) ?? false
    }
}

nonisolated struct DashboardYearDTO: Decodable, Sendable, Identifiable {
    let yearsAgo: Int
    let photos: [ImageDTO]
    let milestones: [MilestoneDTO]

    var id: Int { yearsAgo }

    private enum CodingKeys: String, CodingKey { case yearsAgo, photos, milestones }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        yearsAgo = try container.decode(Int.self, forKey: .yearsAgo)
        photos = try container.decodeList(ImageDTO.self, forKey: .photos)
        milestones = try container.decodeList(MilestoneDTO.self, forKey: .milestones)
    }
}

nonisolated struct DashboardRecentDTO: Decodable, Sendable {
    /// The first day of the window, `YYYY-MM-DD`.
    let from: String
    let photos: [PhotoWithPeopleDTO]
    let milestones: [MilestoneDTO]
    let growth: [GrowthDataDTO]

    private enum CodingKeys: String, CodingKey { case from, photos, milestones, growth }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decodeIfPresent(String.self, forKey: .from) ?? ""
        photos = try container.decodeList(PhotoWithPeopleDTO.self, forKey: .photos)
        milestones = try container.decodeList(MilestoneDTO.self, forKey: .milestones)
        growth = try container.decodeList(GrowthDataDTO.self, forKey: .growth)
    }
}

nonisolated struct GetDashboardResponseDTO: Decodable, Sendable {
    /// The day the server answered for — the request's `today`, echoed. A cached dashboard whose `today` is not the device's today is stale in the ways that matter (birthdays, open events).
    let today: String
    let people: [PersonDTO]
    let relations: [RelationDTO]
    let nudges: [DashboardNudgeDTO]
    let seasons: [DashboardSeasonDTO]
    let onThisDay: [DashboardYearDTO]
    let recent: DashboardRecentDTO

    private enum CodingKeys: String, CodingKey { case today, people, relations, nudges, seasons, onThisDay, recent }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        today = try container.decodeIfPresent(String.self, forKey: .today) ?? ""
        people = try container.decodeList(PersonDTO.self, forKey: .people)
        relations = try container.decodeList(RelationDTO.self, forKey: .relations)
        nudges = try container.decodeList(DashboardNudgeDTO.self, forKey: .nudges)
        seasons = try container.decodeList(DashboardSeasonDTO.self, forKey: .seasons)
        onThisDay = try container.decodeList(DashboardYearDTO.self, forKey: .onThisDay)
        recent = try container.decode(DashboardRecentDTO.self, forKey: .recent)
    }
}

// MARK: - ListOpenEvents

/// An event whose results can be entered now: running today, or ended within the last few days.
nonisolated struct OpenEventDTO: Decodable, Sendable, Identifiable {
    let event: EventSummaryDTO
    let activityName: String

    var id: Int { event.id }

    private enum CodingKeys: String, CodingKey { case event, activityName }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        event = try container.decode(EventSummaryDTO.self, forKey: .event)
        activityName = try container.decodeIfPresent(String.self, forKey: .activityName) ?? ""
    }
}

nonisolated struct ListOpenEventsResponseDTO: Decodable, Sendable {
    /// Newest first.
    let events: [OpenEventDTO]

    private enum CodingKeys: String, CodingKey { case events }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeList(OpenEventDTO.self, forKey: .events)
    }
}

// MARK: - GetSameAge

/// One person at the chosen age: the day they reached it, and the records nearest it.
nonisolated struct SameAgeRowDTO: Decodable, Sendable, Identifiable {
    let person: PersonDTO
    let date: Date
    let height: GrowthDataDTO?
    let weight: GrowthDataDTO?
    let milestones: [MilestoneDTO]
    let photoIds: [Int]
    /// The photos in the window that best show this person, best first, for the side-by-side montage. Empty from a server that predates it.
    let portraits: [PortraitPhotoDTO]

    var id: Int { person.id }

    /// Nothing at this age — the web's `!hasSameAgeRecords`.
    var isEmpty: Bool {
        height == nil && weight == nil && milestones.isEmpty && photoIds.isEmpty && portraits.isEmpty
    }

    private enum CodingKeys: String, CodingKey { case person, date, height, weight, milestones, photoIds, portraits }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        person = try container.decode(PersonDTO.self, forKey: .person)
        date = try container.decode(Date.self, forKey: .date)
        height = try container.decodeIfPresent(GrowthDataDTO.self, forKey: .height)
        weight = try container.decodeIfPresent(GrowthDataDTO.self, forKey: .weight)
        milestones = try container.decodeList(MilestoneDTO.self, forKey: .milestones)
        photoIds = try container.decodeList(Int.self, forKey: .photoIds)
        portraits = try container.decodeList(PortraitPhotoDTO.self, forKey: .portraits)
    }
}

/// An age worth offering, and how many people have something there.
nonisolated struct SameAgeOptionDTO: Decodable, Sendable, Equatable {
    let ageMonths: Int
    let peopleCount: Int

    init(ageMonths: Int, peopleCount: Int) {
        self.ageMonths = ageMonths
        self.peopleCount = peopleCount
    }

    private enum CodingKeys: String, CodingKey { case ageMonths, peopleCount }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ageMonths = try container.decode(Int.self, forKey: .ageMonths)
        peopleCount = try container.decodeIfPresent(Int.self, forKey: .peopleCount) ?? 0
    }
}

nonisolated struct GetSameAgeResponseDTO: Decodable, Sendable {
    /// The age answered for — the request's, or the one the server chose when it sent none.
    let ageMonths: Int
    /// The anchor the server settled on; 0 when nobody qualifies.
    let fromPersonId: Int
    /// The oldest age anyone has reached, which is as far as **Older** goes.
    let maxAgeMonths: Int
    /// Anchor first. Only people who have reached the age.
    let rows: [SameAgeRowDTO]
    /// Ages with any record — photo, milestone or measurement — on the age grid, ascending. Filled only when the request asked for discovery; a server that predates discovery leaves the key out, which decodes as nil rather than as "no ages".
    let availableAges: [SameAgeOptionDTO]?
    /// Ages with a photo, for Portraits. Nil exactly as `availableAges` is.
    let portraitAges: [SameAgeOptionDTO]?
    /// Everyone with a birthday who could be compared. Nil from a server that predates it.
    let peopleCount: Int?

    private enum CodingKeys: String, CodingKey { case ageMonths, fromPersonId, maxAgeMonths, rows, availableAges, portraitAges, peopleCount }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ageMonths = try container.decodeIfPresent(Int.self, forKey: .ageMonths) ?? 0
        fromPersonId = try container.decodeIfPresent(Int.self, forKey: .fromPersonId) ?? 0
        maxAgeMonths = try container.decodeIfPresent(Int.self, forKey: .maxAgeMonths) ?? 0
        rows = try container.decodeList(SameAgeRowDTO.self, forKey: .rows)
        // Present-but-null is Go's nil slice, an empty list; only a missing key means an older server.
        availableAges = container.contains(.availableAges) ? try container.decodeList(SameAgeOptionDTO.self, forKey: .availableAges) : nil
        portraitAges = container.contains(.portraitAges) ? try container.decodeList(SameAgeOptionDTO.self, forKey: .portraitAges) : nil
        peopleCount = try container.decodeIfPresent(Int.self, forKey: .peopleCount)
    }
}

// MARK: - GetFamilyTimeline appearances

/// One activity appearance and which of the family's people were in it, once however many were.
nonisolated struct TimelineAppearanceDTO: Decodable, Sendable, Identifiable {
    let detail: AppearanceDetailDTO
    let personIds: [Int]

    var id: Int { detail.id }

    /// For a person's own appearances (`GetPersonSeason`), which arrive without the wrapper.
    init(detail: AppearanceDetailDTO, personIds: [Int]) {
        self.detail = detail
        self.personIds = personIds
    }

    private enum CodingKeys: String, CodingKey { case detail, personIds }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detail = try container.decode(AppearanceDetailDTO.self, forKey: .detail)
        personIds = try container.decodeList(Int.self, forKey: .personIds)
    }
}

// MARK: - GetFaceReview

/// The only part of `GetFaceReview` the app reads: whether face tagging is on, and how many photos wait for review. Face review itself is web-only; the account menu links to it with this count.
nonisolated struct FaceReviewSummaryDTO: Decodable, Sendable {
    let enabled: Bool
    let unknownCount: Int
    let autoCount: Int

    private enum CodingKeys: String, CodingKey { case enabled, unknownCount, autoCount }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        unknownCount = try container.decodeIfPresent(Int.self, forKey: .unknownCount) ?? 0
        autoCount = try container.decodeIfPresent(Int.self, forKey: .autoCount) ?? 0
    }
}

/// The body for an argument-less proc — vbeam still requires one.
nonisolated struct EmptyRequestDTO: Encodable, Sendable {}
