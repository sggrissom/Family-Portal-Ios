import Foundation

// Global search (backend/search.go). One request answers every group at once. Every group and field reads as empty when missing, so a newer server adding a group, or an older one lacking one, never fails the whole response.

nonisolated struct SearchRequestDTO: Encodable, Sendable {
    let query: String
    /// Kinds of understanding to switch off, from `SearchIgnore`: removing a chip re-sends the query with its kind here.
    var ignore: [String]? = nil
    /// Scales the moments group only, for "show all". 0 or absent is the server's 20.
    var limit: Int? = nil
}

/// The structure the server pulled out of the query, which the screen shows as removable chips. `SearchQuery.parse` produces the same thing on the phone.
nonisolated struct SearchUnderstoodDTO: Decodable, Sendable, Equatable, ZeroValue {
    @OrZero var personIds: [Int] = []
    /// Months of age, `[from, to)`. Both or neither.
    var ageFromMonth: Int? = nil
    var ageToMonth: Int? = nil
    @OrZero var ageLabel: String = ""
    @OrZero var year: Int = 0
    /// 1–12, or 0. A month with no year matches that month in any year.
    @OrZero var month: Int = 0
    /// A `MilestoneCategory` raw value, or empty.
    @OrZero var category: String = ""
    /// Tags named in the query. Not a filter: their words stay in `text`.
    @OrZero var tagIds: [Int] = []
    /// What is left to match words against.
    @OrZero var text: String = ""

    static var zero: SearchUnderstoodDTO { SearchUnderstoodDTO() }
}

/// An activity, a season or an event, in one flat list. `id` is only unique within a kind, so lists key on `key`.
nonisolated struct ActivityHitDTO: Decodable, Sendable, Hashable {
    @OrZero var kind: String
    let id: Int
    @OrZero var name: String
    /// The activity's name for a season, the location (or host) for an event.
    @OrZero var detail: String
    /// The start date for a season or an event. An activity has none, and Go sends its zero time.
    var date: Date? = nil

    static let activity = "activity"
    static let season = "season"
    static let event = "event"

    var key: String { "\(kind)-\(id)" }

    /// `date`, unless it is Go's zero time.
    var startDate: Date? { date?.serverDate }
}

nonisolated struct SearchResponseDTO: Decodable, Sendable {
    /// The query as the server ran it: trimmed and capped at 200 characters.
    @OrZero var query: String
    @OrZero var understood: SearchUnderstoodDTO
    @OrZero var people: [PersonDTO]
    @OrZero var moments: [MilestoneDTO]
    /// Every moment that matched, for "Show all N moments". `moments` holds the first `limit`.
    @OrZero var momentCount: Int
    /// The interviews behind any answers in `moments`, so they fold into one card as History folds them.
    @OrZero var interviews: [InterviewDTO]
    @OrZero var photos: [PhotoWithPeopleDTO]
    @OrZero var morePhotos: Bool
    @OrZero var tags: [TagDTO]
    @OrZero var places: [PhotoPlaceDTO]
    @OrZero var activities: [ActivityHitDTO]
    @OrZero var books: [BookSummaryDTO]
    /// `"semantic"`, or `"text"` when the vision daemon is down and only words were matched.
    @OrZero var searchMode: String

    var isTextOnly: Bool { searchMode == "text" }

    var isEmpty: Bool {
        people.isEmpty && moments.isEmpty && photos.isEmpty && tags.isEmpty
            && places.isEmpty && activities.isEmpty && books.isEmpty
    }
}
