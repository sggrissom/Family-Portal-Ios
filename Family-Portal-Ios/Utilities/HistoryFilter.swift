import Foundation

/// The kinds of record History shows, in the order the **More** menu lists them.
enum HistoryType: String, CaseIterable, Identifiable, Sendable {
    case milestones, measurements, photos, activities, birthdays

    var id: String { rawValue }

    var label: String {
        switch self {
        case .milestones: return Copy.history.types.milestones
        case .measurements: return Copy.history.types.measurements
        case .photos: return Copy.history.types.photos
        case .activities: return Copy.history.types.activities
        case .birthdays: return Copy.history.types.birthdays
        }
    }
}

/// History's filters. Held above the navigation stack, so opening a record and coming back keeps them.
struct HistoryFilters: Equatable {
    var personIds: Set<UUID> = []
    var types: Set<HistoryType> = Set(HistoryType.allCases)
    var tagIds: Set<Int> = []
    var search = ""

    var trimmedSearch: String { search.trimmingCharacters(in: .whitespaces) }

    /// Anything other than the defaults — what **Clear** resets.
    var isActive: Bool {
        !personIds.isEmpty || types != Set(HistoryType.allCases) || !tagIds.isEmpty || !trimmedSearch.isEmpty
    }
}

/// What History renders for a set of filters.
struct HistoryContent {
    var records: DayRecords
    var birthdayPeople: [Person]
    var range: (from: String, to: String)?
}

/// Picks the records History shows — a port of `historyView` in frontend/lib/history.ts, over the store rather than a `GetFamilyTimeline` response.
/// The web pages a year at a time; the app has every record locally, so it renders them all and `LazyVStack` does the paging.
/// As on the web, only photos tagged with someone appear: the store knows a photo's people, and an untagged one belongs to nobody's history. This is noted rather than fixed in one client.
enum History {

    static func view(
        people: [Person],
        milestones: [Milestone],
        growth: [GrowthData],
        photos: [Photo],
        appearances: [TimelineAppearanceDTO],
        filters: HistoryFilters,
        today: String
    ) -> HistoryContent {
        let wantType = { (type: HistoryType) in filters.types.contains(type) }
        let wantPerson = { (person: Person?) in
            filters.personIds.isEmpty || (person.map { filters.personIds.contains($0.id) } ?? false)
        }
        let wantPeople = { (people: [Person]) in
            filters.personIds.isEmpty || people.contains { filters.personIds.contains($0.id) }
        }
        let tagged = { (tagIds: [Int]) in
            filters.tagIds.isEmpty || tagIds.contains { filters.tagIds.contains($0) }
        }
        let tagsOnly = !filters.tagIds.isEmpty
        let search = filters.trimmedSearch

        var records = DayRecords()

        if wantType(.milestones) {
            records.milestones = milestones.filter { milestone in
                wantPerson(milestone.person)
                    && tagged(milestone.tagRemoteIds)
                    && (search.isEmpty
                        || milestone.descriptionText.localizedCaseInsensitiveContains(search)
                        || milestone.context.localizedCaseInsensitiveContains(search))
            }
        }

        // A search is for milestones: everything else steps aside while one is running, as the web's results list does.
        guard search.isEmpty else {
            return HistoryContent(records: records, birthdayPeople: [], range: nil)
        }

        if wantType(.measurements) && !tagsOnly {
            records.growth = growth.filter { wantPerson($0.person) }
        }

        if wantType(.photos) {
            records.photos = photos.filter { photo in
                !photo.taggedPeople.isEmpty && wantPeople(photo.taggedPeople) && tagged(photo.tagRemoteIds)
            }
        }

        if wantType(.activities) && !tagsOnly {
            let remoteIds = filters.personIds.isEmpty
                ? nil
                : Set(people.filter { filters.personIds.contains($0.id) }.compactMap { $0.remoteId.flatMap(Int.init) })
            records.appearances = appearances.filter { appearance in
                remoteIds.map { ids in appearance.personIds.contains { ids.contains($0) } } ?? true
            }
        }

        let firstYear = earliestYear(milestones: milestones, growth: growth, photos: photos)
        let showBirthdays = wantType(.birthdays) && !tagsOnly && firstYear != nil
        return HistoryContent(
            records: records,
            birthdayPeople: showBirthdays ? people.filter { wantPerson($0) } : [],
            range: showBirthdays ? (from: "\(firstYear!)-01-01", to: today) : nil
        )
    }

    /// Every year with a record, newest first — the **Jump to year** menu.
    static func years(milestones: [Milestone], growth: [GrowthData], photos: [Photo]) -> [Int] {
        var years = Set<Int>()
        for milestone in milestones { years.insert(milestone.date.calendarDay().year ?? 0) }
        for record in growth { years.insert(record.date.calendarDay().year ?? 0) }
        for photo in photos where !photo.taggedPeople.isEmpty { years.insert(photo.photoDate.calendarDay().year ?? 0) }
        years.remove(0)
        return years.sorted(by: >)
    }

    private static func earliestYear(milestones: [Milestone], growth: [GrowthData], photos: [Photo]) -> Int? {
        years(milestones: milestones, growth: growth, photos: photos).last
    }
}
