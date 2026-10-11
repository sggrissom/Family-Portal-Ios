import Foundation

/// What one widget entry shows, worked out from the snapshot alone. In `Shared/` rather than the extension so the app's tests can pin it.
nonisolated struct WidgetMoment: Equatable, Sendable {

    enum Source: Equatable, Sendable {
        /// No snapshot: never signed in, signed out, or the app has not published yet.
        case signedOut
        /// Signed in, but there is nothing to show — no records at all.
        case nothing
        /// Today's "On this day".
        case onThisDay
        /// A memory from the pool, because today has nothing on this day.
        case memory
    }

    var source: Source
    /// The featured item first, then the rest of what the day has — the medium and large sizes show more of it.
    var items: [WidgetItem] = []
    /// Past the snapshot's horizon: the app has not run for long enough that the day's "On this day" was never computed.
    var isStale = false
    var names: [Int: String] = [:]
    var siteURL: String = ""
    /// The local day (`YYYY-MM-DD`) the entry is shown on, which decides whether an on-this-day item is the anniversary itself or only near it.
    var day: String = ""
    /// How many items the configured pool offers once unusable photos are left out. Shuffle is only offered when there is somewhere to shuffle to.
    var poolSize = 0

    var featured: WidgetItem? { items.first }

    var canShuffle: Bool { poolSize > 1 }

    /// The items with a picture, featured first.
    var pictures: [WidgetItem] { items.filter(\.hasImage) }

    /// The items that are only words, each a record of its own.
    var textRecords: [WidgetItem] { items.filter { !$0.hasImage && !$0.title.isEmpty } }

    /// How an item is dated here: the anniversary itself, a day near it, or a memory with no claim to the day.
    func dating(_ item: WidgetItem) -> WidgetDating {
        guard source == .onThisDay, let years = item.yearsAgo else { return .memory(item.date) }
        return WidgetDay.isAnniversary(of: item.date, on: day) ? .anniversary(yearsAgo: years) : .nearby(item.date)
    }

    func names(for item: WidgetItem) -> [String] {
        item.personIds.compactMap { names[$0] }
    }

    func url(for item: WidgetItem?) -> URL? {
        guard let item else { return URL(string: siteURL + "/dashboard") }
        return URL(string: siteURL + item.link)
    }

    static let signedOut = WidgetMoment(source: .signedOut)
}

/// What a widget may say about when an item happened. Only an exact anniversary says "On this day": the snapshot's window takes the two days either side too.
nonisolated enum WidgetDating: Equatable, Sendable {
    case anniversary(yearsAgo: Int)
    /// From the ±2 day window, so it names its own day.
    case nearby(String)
    /// A memory from the pool, dated by its own day.
    case memory(String)

    /// The small context line: "On this day", "Around this day", "A memory".
    var label: String {
        switch self {
        case .anniversary: WidgetCopy.onThisDay
        case .nearby: WidgetCopy.aroundThisDay
        case .memory: WidgetCopy.memory
        }
    }

    /// "3 years ago", or the record's own date.
    var when: String {
        switch self {
        case .anniversary(let years): WidgetCopy.yearsAgo(years)
        case .nearby(let day), .memory(let day): WidgetCopy.date(day)
        }
    }

    /// One line for the smallest places: "3 years ago", "Oct 13, 2023", "A memory · 2021".
    var compact: String {
        switch self {
        case .anniversary(let years): WidgetCopy.yearsAgo(years)
        case .nearby(let day): WidgetCopy.date(day)
        case .memory(let day): "\(WidgetCopy.memory) · \(day.prefix(4))"
        }
    }
}

nonisolated enum WidgetTimeline {

    /// How long one featured picture stays up before the next of the day's takes over.
    static let slotHours = 3

    /// The entries from `now` for the next `hours`: one now, then one at every slot boundary. Slots are counted from local midnight, so a new day always starts with a new entry.
    static func entryDates(from now: Date, hours: Int = 48, slotHours: Int = slotHours, calendar: Calendar = .current) -> [Date] {
        var dates = [now]
        let start = calendar.startOfDay(for: now)
        let end = now.addingTimeInterval(TimeInterval(hours) * 3600)
        var slot = 1
        while let boundary = calendar.date(byAdding: .hour, value: slot * slotHours, to: start), boundary < end {
            if boundary > now { dates.append(boundary) }
            slot += 1
        }
        return dates
    }

    /// Which slot of its day `date` falls in, and how many slots have passed since a fixed day — the walk through the pool, which must not restart every midnight.
    static func slot(of date: Date, slotHours: Int = slotHours, calendar: Calendar = .current) -> (inDay: Int, overall: Int) {
        let start = calendar.startOfDay(for: date)
        let hour = calendar.dateComponents([.hour], from: start, to: date).hour ?? 0
        let inDay = max(0, hour / slotHours)
        let days = calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: start).day ?? 0
        let perDay = max(1, 24 / slotHours)
        return (inDay, days * perDay + inDay)
    }

    /// "On this day" for `date`, or a memory when the day has none. `personId` keeps only what that person is in.
    ///
    /// `imageAvailable` says whether a named image file can actually be drawn. A photo whose file is gone has nothing to show and is left out; a milestone loses only its picture.
    static func onThisDay(
        _ snapshot: WidgetSnapshot?,
        at date: Date,
        personId: Int? = nil,
        calendar: Calendar = .current,
        imageAvailable: (String) -> Bool = { _ in true }
    ) -> WidgetMoment {
        guard let snapshot else { return .signedOut }
        let day = WidgetDay.key(date, calendar: calendar)
        let slot = slot(of: date, calendar: calendar)
        var moment = moment(snapshot, source: .onThisDay)
        moment.day = day
        moment.isStale = day > snapshot.horizon
        let filter = MemoryFilter(content: .everything, personId: personId)

        let items = usable((snapshot.onThisDay[day] ?? []).filter(filter.admits), imageAvailable)
        if !items.isEmpty {
            moment.items = featuring(items, slot: slot.inDay)
            return moment
        }

        let pool = usable(snapshot.pool.filter(filter.admits), imageAvailable)
        guard !pool.isEmpty else {
            moment.source = .nothing
            return moment
        }
        moment.source = .memory
        moment.items = [pool[slot.overall % pool.count]]
        return moment
    }

    /// The Memory widget at `date`: the filtered pool, walked one item per rotation slot, `shuffle` steps ahead.
    static func memory(
        _ snapshot: WidgetSnapshot?,
        at date: Date,
        filter: MemoryFilter,
        rotationHours: Int,
        shuffle: Int = 0,
        calendar: Calendar = .current,
        imageAvailable: (String) -> Bool = { _ in true }
    ) -> WidgetMoment {
        guard let snapshot else { return .signedOut }
        var moment = moment(snapshot, source: .memory)
        moment.day = WidgetDay.key(date, calendar: calendar)
        let pool = usable(snapshot.pool.filter(filter.admits), imageAvailable)
        moment.poolSize = pool.count
        guard !pool.isEmpty else {
            moment.source = .nothing
            return moment
        }
        let slot = slot(of: date, slotHours: rotationHours, calendar: calendar).overall
        let index = ((slot + shuffle) % pool.count + pool.count) % pool.count
        moment.items = [pool[index]]
        return moment
    }

    /// The Quote widget: every quote (or the pool's, from an older snapshot), turned over every `slotHours`.
    static func quote(_ snapshot: WidgetSnapshot?, at date: Date, personId: Int? = nil, calendar: Calendar = .current) -> WidgetMoment {
        guard var snapshot else { return .signedOut }
        snapshot.pool = snapshot.quotes ?? snapshot.pool
        return memory(snapshot, at: date, filter: MemoryFilter(content: .quotes, personId: personId), rotationHours: slotHours, calendar: calendar)
    }

    /// The Family ages widget on the day `date` falls on. nil without a snapshot.
    static func ages(_ snapshot: WidgetSnapshot?, at date: Date, personId: Int? = nil, calendar: Calendar = .current) -> FamilyAges? {
        guard let snapshot else { return nil }
        let day = WidgetDay.key(date, calendar: calendar)
        let members = (snapshot.family ?? []).filter { personId == nil || $0.personId == personId }
        let rows = members.compactMap { member in
            member.ageByDay[day].map { FamilyAges.Row(name: member.name, age: $0) }
        }
        let birthdays = members.compactMap { $0.birthdayByDay[day] }.sorted { $0.inDays < $1.inDays }.map(\.text)
        return FamilyAges(rows: rows, birthdays: birthdays, isStale: day > snapshot.horizon)
    }

    private static func moment(_ snapshot: WidgetSnapshot, source: WidgetMoment.Source) -> WidgetMoment {
        WidgetMoment(
            source: source,
            names: Dictionary(snapshot.people.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }),
            siteURL: snapshot.siteURL
        )
    }

    /// Items whose pictures can be drawn, or which have words to stand in for a missing one. A photo is only its picture, so without it the item goes rather than showing an empty frame or a made-up caption.
    static func usable(_ items: [WidgetItem], _ imageAvailable: (String) -> Bool) -> [WidgetItem] {
        items.compactMap { item in
            guard let file = item.imageFile, !imageAvailable(file) else { return item }
            guard item.kind != .photo else { return nil }
            var item = item
            item.imageFile = nil
            return item
        }
    }

    /// The day's items with the featured one first. Pictures take turns by slot; a day with none features its first milestone.
    static func featuring(_ items: [WidgetItem], slot: Int) -> [WidgetItem] {
        let pictured = items.indices.filter { items[$0].hasImage }
        guard !pictured.isEmpty else { return items }
        let chosen = pictured[slot % pictured.count]
        var ordered = items
        let featured = ordered.remove(at: chosen)
        return [featured] + ordered
    }
}

/// What the Memory widget is configured to show.
nonisolated struct MemoryFilter: Equatable, Sendable {

    enum Content: String, CaseIterable, Sendable {
        case everything, photos, milestones, quotes
    }

    var content: Content = .everything
    /// A server id; nil is the whole family.
    var personId: Int? = nil

    func admits(_ item: WidgetItem) -> Bool {
        if let personId, !item.personIds.contains(personId) { return false }
        switch content {
        case .everything: return true
        case .photos: return item.kind == .photo
        case .milestones: return item.kind == .milestone || item.kind == .artwork
        case .quotes: return item.kind == .quote
        }
    }
}

/// What the Family ages widget shows on one day.
nonisolated struct FamilyAges: Equatable, Sendable {
    struct Row: Equatable, Hashable, Sendable {
        var name: String
        var age: String
    }

    var rows: [Row]
    /// Upcoming birthdays, soonest first.
    var birthdays: [String]
    /// Past the horizon the app has not worked the ages out, and the rows are empty.
    var isStale: Bool
}
