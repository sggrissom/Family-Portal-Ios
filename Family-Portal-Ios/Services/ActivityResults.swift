import Foundation

/// Ports of `frontend/lib/activityResults.ts`, so the app and the web sum up a performance in the same words.
nonisolated enum ActivityResults {

    /// A new dance program has no adjudications of its own yet.
    static let danceAdjudications = ["Platinum", "High Gold", "Gold"]

    /// The adjudications offered as one-tap rows: the family's own, else the common dance ones, else none.
    static func quickLabels(kind: String, used: [String]) -> [String] {
        let labels = used.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !labels.isEmpty { return Array(labels.prefix(6)) }
        return kind == ActivityKind.dance ? danceAdjudications : []
    }
}

// MARK: - The activities page (frontend/lib/activityHome.ts)

nonisolated enum ActivityHome {

    enum EventStatus: Equatable, Sendable {
        case upcoming, now, done
    }

    /// Days are `YYYY-MM-DD`; an empty start is a held event, an empty or earlier end means a one-day one.
    static func eventStatus(start: String, end: String, today: String) -> EventStatus {
        guard !start.isEmpty else { return .done }
        let last = !end.isEmpty && end >= start ? end : start
        if today < start { return .upcoming }
        if today <= last { return .now }
        return .done
    }

    enum SeasonPhase: Equatable, Sendable {
        case upcoming, current, past
    }

    /// An open-ended season is current once it starts.
    static func seasonPhase(start: String, end: String, today: String) -> SeasonPhase {
        if !start.isEmpty && today < start { return .upcoming }
        if !end.isEmpty && today > end { return .past }
        return .current
    }

    enum Focus: Equatable, Sendable {
        case latest, needsResults, now, next

        var label: String {
            switch self {
            case .latest: return "Latest"
            case .needsResults: return "No results yet"
            case .now: return "Happening now"
            case .next: return "Next"
            }
        }
    }

    struct Focused<Event> {
        let event: Event
        let focus: Focus
    }

    struct Progress<Event> {
        var focus: [Focused<Event>]
        /// Events already held, and how many of them have a performance recorded.
        var held: Int
        var recorded: Int
    }

    /// Which competitions a season's card surfaces: the latest with results, each held one still missing them (only once the season has routines), what is on today, and the next one — in date order.
    static func seasonProgress<Event>(
        _ events: [Event],
        hasEntries: Bool,
        today: String,
        days: (Event) -> (start: String, end: String),
        appearances: (Event) -> Int
    ) -> Progress<Event> {
        var focus: [(event: Event, focus: Focus, start: String)] = []
        var held = 0
        var recorded = 0
        var latest: (Event, String)?
        var next: (Event, String)?

        for event in events {
            let day = days(event)
            switch eventStatus(start: day.start, end: day.end, today: today) {
            case .now:
                focus.append((event, .now, day.start))
            case .upcoming:
                if next == nil { next = (event, day.start) }
            case .done:
                held += 1
                if appearances(event) > 0 {
                    recorded += 1
                    latest = (event, day.start)
                } else if hasEntries {
                    focus.append((event, .needsResults, day.start))
                }
            }
        }

        if let latest { focus.insert((latest.0, .latest, latest.1), at: 0) }
        if let next { focus.append((next.0, .next, next.1)) }
        // Stable, as the web's sort is.
        let ordered = focus.enumerated().sorted { a, b in
            a.element.start == b.element.start ? a.offset < b.offset : a.element.start < b.element.start
        }
        return Progress(focus: ordered.map { Focused(event: $0.element.event, focus: $0.element.focus) }, held: held, recorded: recorded)
    }

    static func progress(of home: HomeSeasonDTO, today: String) -> Progress<HomeEventDTO> {
        seasonProgress(
            home.events,
            hasEntries: !home.entries.isEmpty,
            today: today,
            days: { (dayKey($0.event.startDate), dayKey($0.event.endDate)) },
            appearances: \.appearances
        )
    }

    static func phase(of season: SeasonDTO, today: String) -> SeasonPhase {
        seasonPhase(start: dayKey(season.startDate), end: dayKey(season.endDate), today: today)
    }

    /// A server day as `YYYY-MM-DD`, or empty for Go's zero time.
    static func dayKey(_ date: Date) -> String {
        date.serverDate?.recordDayKey ?? ""
    }
}
