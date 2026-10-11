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

    var featured: WidgetItem? { items.first }

    func names(for item: WidgetItem) -> [String] {
        item.personIds.compactMap { names[$0] }
    }

    func url(for item: WidgetItem?) -> URL? {
        guard let item else { return URL(string: siteURL + "/dashboard") }
        return URL(string: siteURL + item.link)
    }

    /// The featured item's year, and the other pictures from it — the large widget's mosaic.
    var featuredYear: [WidgetItem] {
        guard let featured, let years = featured.yearsAgo else { return featured.map { [$0] } ?? [] }
        return items.filter { $0.yearsAgo == years }
    }

    static let signedOut = WidgetMoment(source: .signedOut)
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
    static func onThisDay(_ snapshot: WidgetSnapshot?, at date: Date, personId: Int? = nil, calendar: Calendar = .current) -> WidgetMoment {
        guard let snapshot else { return .signedOut }
        let day = WidgetDay.key(date, calendar: calendar)
        let slot = slot(of: date, calendar: calendar)
        var moment = moment(snapshot, source: .onThisDay)
        moment.isStale = day > snapshot.horizon
        let filter = MemoryFilter(content: .everything, personId: personId)

        let items = (snapshot.onThisDay[day] ?? []).filter(filter.admits)
        if !items.isEmpty {
            moment.items = featuring(items, slot: slot.inDay)
            return moment
        }

        let pool = snapshot.pool.filter(filter.admits)
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
        calendar: Calendar = .current
    ) -> WidgetMoment {
        guard let snapshot else { return .signedOut }
        var moment = moment(snapshot, source: .memory)
        let pool = snapshot.pool.filter(filter.admits)
        guard !pool.isEmpty else {
            moment.source = .nothing
            return moment
        }
        let slot = slot(of: date, slotHours: rotationHours, calendar: calendar).overall
        let index = ((slot + shuffle) % pool.count + pool.count) % pool.count
        moment.items = [pool[index]]
        return moment
    }

    private static func moment(_ snapshot: WidgetSnapshot, source: WidgetMoment.Source) -> WidgetMoment {
        WidgetMoment(
            source: source,
            names: Dictionary(snapshot.people.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }),
            siteURL: snapshot.siteURL
        )
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
