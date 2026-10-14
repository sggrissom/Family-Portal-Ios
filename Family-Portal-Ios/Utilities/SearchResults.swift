import Foundation

/// One filter the search understood, shown as a removable chip. Removing it re-runs the search ignoring that whole kind. Tags are not filters, so they get no chip.
struct SearchChip: Identifiable, Equatable {
    let kind: SearchIgnore
    let label: String

    var id: SearchIgnore { kind }
}

/// A row of the Moments group: a moment, or an interview's answers folded into one card where its first answer ranked.
/// Generic so the server's `MilestoneDTO`s and the store's `Milestone`s fold the same way.
enum SearchMomentItem<Item> {
    case moment(Item)
    case interview(InterviewAnswers<Item>)
}

/// Ports of the pure parts of frontend/lib/search.ts and the search page, with their cases in `SearchResultsTests`.
enum SearchResults {

    /// What "Show all N moments" asks for, as the web does. The server caps it here too.
    static let showAllMomentsLimit = 100

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// "June 2024", "June", "2024", or empty — `dateLabel`.
    static func dateLabel(year: Int, month: Int) -> String {
        let name = (1...12).contains(month) ? monthNames[month - 1] : ""
        return [name, year > 0 ? String(year) : ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func categoryLabel(_ category: String) -> String {
        Copy.search.categoryChips[category] ?? MilestoneCategory(rawValue: category)?.label ?? category
    }

    /// One chip per kind of filter — `understoodChips`. People are named by first name, "Ada or Ben" when there are several.
    static func chips(
        personIds: [Int],
        ageLabel: String,
        year: Int,
        month: Int,
        category: String,
        names: [Int: String]
    ) -> [SearchChip] {
        var chips: [SearchChip] = []
        let firstNames = personIds.compactMap { names[$0]?.firstName }
        if !firstNames.isEmpty {
            chips.append(SearchChip(kind: .person, label: firstNames.joined(separator: " or ")))
        }
        if !ageLabel.isEmpty {
            chips.append(SearchChip(kind: .age, label: ageLabel))
        }
        let date = dateLabel(year: year, month: month)
        if !date.isEmpty {
            chips.append(SearchChip(kind: .date, label: date))
        }
        if !category.isEmpty {
            chips.append(SearchChip(kind: .category, label: categoryLabel(category)))
        }
        return chips
    }

    static func chips(_ understood: SearchUnderstoodDTO, names: [Int: String]) -> [SearchChip] {
        chips(
            personIds: understood.personIds, ageLabel: understood.ageLabel,
            year: understood.year, month: understood.month, category: understood.category, names: names
        )
    }

    static func chips(_ parsed: ParsedSearch, names: [Int: String]) -> [SearchChip] {
        chips(
            personIds: parsed.personIds, ageLabel: parsed.ageLabel,
            year: parsed.year, month: parsed.month, category: parsed.category?.rawValue ?? "", names: names
        )
    }

    /// The moments in ranked order, an interview's answers folded where its first answer ranked — `momentItems`.
    static func momentItems(_ moments: [MilestoneDTO]) -> [SearchMomentItem<MilestoneDTO>] {
        momentItems(moments, interviewId: \.interviewId, order: \.id)
    }

    static func momentItems<Item>(_ moments: [Item], interviewId: (Item) -> Int, order: (Item) -> Int) -> [SearchMomentItem<Item>] {
        let groups = Interviews.fold(moments, interviewId: interviewId, order: order).groups
        let byInterview = Dictionary(groups.map { ($0.interviewId, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [SearchMomentItem<Item>] = []
        var shown = Set<Int>()
        for moment in moments {
            let id = interviewId(moment)
            if id == 0 {
                items.append(.moment(moment))
            } else if shown.insert(id).inserted, let group = byInterview[id] {
                items.append(.interview(group))
            }
        }
        return items
    }

    /// The server's photo ids in its order, each with this device's copy when it has one — the rest are shown from the server.
    static func resolve<Local>(_ ids: [Int], in local: [Int: Local]) -> [(id: Int, local: Local?)] {
        ids.map { (id: $0, local: local[$0]) }
    }

    /// The Photos tab showing what the photo group would, as far as its filters reach: people, a year or a month of a year, and the text — `photosHref`.
    /// `localIds` maps server person ids to local ones; anyone not on this device yet is left out.
    static func photoFilter(_ understood: SearchUnderstoodDTO, localIds: [Int: UUID], calendar: Calendar = .current) -> PhotoFilter {
        var filter = PhotoFilter()
        filter.personLocalIds = Set(understood.personIds.compactMap { localIds[$0] })
        if understood.year > 0 {
            let month = understood.month
            let from = DateComponents(year: understood.year, month: month > 0 ? month : 1, day: 1)
            filter.dateFrom = calendar.date(from: from)
            if let start = filter.dateFrom {
                let span: Calendar.Component = month > 0 ? .month : .year
                filter.dateTo = calendar.date(byAdding: DateComponents(day: -1), to: calendar.date(byAdding: span, value: 1, to: start) ?? start)
            }
        }
        filter.searchText = understood.text
        return filter
    }
}
