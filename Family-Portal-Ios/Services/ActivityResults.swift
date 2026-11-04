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

    /// "1st", "22nd", "113th" — in English, as the web writes them.
    static func ordinal(_ n: Int) -> String {
        let mod100 = n % 100
        if (11...13).contains(mod100) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// One result on its own: "1st of 14", "92.5 points", or its label.
    static func text(_ result: some ActivityResultLike) -> String {
        switch result.kind {
        case ActivityResultKind.placement.rawValue:
            let place = result.rank.map(ordinal) ?? result.label
            return place + (result.outOf.map { " of \($0)" } ?? "")
        case ActivityResultKind.score.rawValue:
            guard let score = result.score else { return result.label }
            let number = score.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
            let label = result.label.trimmingCharacters(in: .whitespaces)
            if label.isEmpty || label == number { return number }
            return label.hasPrefix("\(number) ") ? label : "\(number) \(label)"
        default:
            return result.label
        }
    }

    static func bestPlacement<R: ActivityResultLike>(_ results: [R]) -> R? {
        var best: R?
        for result in results where result.kind == ActivityResultKind.placement.rawValue {
            guard let rank = result.rank else { continue }
            if best == nil || rank < (best?.rank ?? .max) { best = result }
        }
        return best
    }

    /// How a performance went in a few words: the best placement and the adjudication, else an award, else whatever came first.
    static func headline<R: ActivityResultLike>(_ results: [R]) -> String {
        let placement = bestPlacement(results)
        let adjudication = results.first { $0.kind == ActivityResultKind.adjudication.rawValue && !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        let award = results.first { $0.kind == ActivityResultKind.award.rawValue && !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        let parts = [
            placement?.rank.map(ordinal) ?? "",
            adjudication?.label ?? "",
            placement == nil && adjudication == nil ? (award?.label ?? "") : "",
        ].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return results.first.map { text($0) } ?? ""
    }

    /// A season grid's cell: a game's outcome ("W 3–1"), a bracket's record ("2–1"), else the results' headline, else "Recorded". Empty when the routine didn't perform there.
    static func cellHeadline<R: ActivityResultLike>(_ views: [(matchup: Matchup, results: [R])]) -> String {
        guard !views.isEmpty else { return "" }
        let decided = views.map(\.matchup).filter { !$0.outcome.isEmpty }
        if decided.count == 1, let m = decided.first {
            let letter = m.outcome == MatchupOutcome.win ? "W" : m.outcome == MatchupOutcome.loss ? "L" : "D"
            if let ours = m.scoreFor, let theirs = m.scoreAgainst { return "\(letter) \(ours)–\(theirs)" }
            return letter
        }
        if decided.count > 1 {
            let wins = decided.filter { $0.outcome == MatchupOutcome.win }.count
            let losses = decided.filter { $0.outcome == MatchupOutcome.loss }.count
            let draws = decided.filter { $0.outcome == MatchupOutcome.draw }.count
            return ([wins, losses] + (draws > 0 ? [draws] : [])).map(String.init).joined(separator: "–")
        }
        let summary = headline(views.flatMap(\.results))
        return summary.isEmpty ? "Recorded" : summary
    }

    struct LabelCount: Equatable, Sendable {
        let label: String
        let count: Int
    }

    /// Each adjudication and how often it was given, most first, then by name.
    static func adjudicationCounts(_ results: [some ActivityResultLike]) -> [LabelCount] {
        var counts: [String: Int] = [:]
        for result in results where result.kind == ActivityResultKind.adjudication.rawValue {
            let label = result.label.trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            counts[label, default: 0] += 1
        }
        return counts
            .map { LabelCount(label: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
    }

    /// The best placement across performances, and which performance it was.
    static func bestFinish<View, R: ActivityResultLike>(_ views: [View], results: (View) -> [R]) -> (view: View, result: R)? {
        var best: (view: View, result: R)?
        for view in views {
            guard let placement = bestPlacement(results(view)), let rank = placement.rank else { continue }
            if best == nil || rank < (best?.result.rank ?? .max) { best = (view, placement) }
        }
        return best
    }
}

/// What the summaries read of a result, so they work on the server's rows and on test values alike.
nonisolated protocol ActivityResultLike {
    var kind: String { get }
    var label: String { get }
    var rank: Int? { get }
    var outOf: Int? { get }
    var score: Double? { get }
}

extension ActivityResultDTO: ActivityResultLike {}

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
