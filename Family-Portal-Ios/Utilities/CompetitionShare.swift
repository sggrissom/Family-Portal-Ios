import Foundation

/// A routine's card on the results page: every routine in the season, recorded or not, then any routine the season no longer lists that still has performances here.
struct CompetitionRoutine: Identifiable {
    let entry: ActivityEntryDTO?
    let entryId: Int
    let name: String
    let appearances: [AppearanceDetailDTO]
    var id: Int { entryId }

    static func list(entries: [ActivityEntryDTO], appearances: [AppearanceDetailDTO]) -> [CompetitionRoutine] {
        let byEntry = Dictionary(grouping: appearances) { $0.entry.id }
        var routines = entries.map { entry in
            CompetitionRoutine(entry: entry, entryId: entry.id, name: entry.name, appearances: byEntry[entry.id] ?? [])
        }
        let listed = Set(routines.map(\.entryId))
        for run in Matchups.group(appearances, by: { $0.entry.id }) {
            guard let first = run.first, !listed.contains(first.entry.id) else { continue }
            routines.append(CompetitionRoutine(entry: first.entry, entryId: first.entry.id, name: first.entry.name, appearances: run))
        }
        return routines
    }
}

/// What a competition's shared recap carries: the event, then each included routine's performances and results in the page's order. Notes stay out.
struct CompetitionShare: Equatable {

    struct Result: Equatable {
        let kind: ActivityResultKind?
        let text: String
        let detail: String?
    }

    struct Performance: Identifiable, Equatable {
        let id: Int
        let when: String?
        let matchup: String?
        let results: [Result]
    }

    struct Routine: Identifiable, Equatable {
        let id: Int
        let name: String
        let descriptors: String?
        let roster: String?
        let summary: String?
        let performances: [Performance]
    }

    struct Options: Equatable {
        var omitted: Set<Int> = []
        var showsNames = false
        var isSnapshot = false
    }

    let eventName: String
    let seasonName: String
    let dates: String?
    let place: String?
    let routines: [Routine]
    /// "Results so far, as of Nov 21, 2026" while results are still coming in.
    let snapshotLabel: String?

    var text: String {
        var lines = [eventName]
        let facts = [dates, place].compactMap { $0 }
        if !facts.isEmpty { lines.append(facts.joined(separator: " · ")) }
        if let snapshotLabel { lines.append(snapshotLabel) }
        for routine in routines {
            lines.append("")
            lines.append(routine.name)
            if let descriptors = routine.descriptors { lines.append(descriptors) }
            if let roster = routine.roster { lines.append(roster) }
            if let summary = routine.summary { lines.append(summary) }
            for performance in routine.performances {
                let heading = [performance.when, performance.matchup].compactMap { $0 }.joined(separator: " · ")
                let indent = heading.isEmpty ? "" : "  "
                if !heading.isEmpty { lines.append("• \(heading)") }
                if performance.results.isEmpty && performance.matchup == nil {
                    lines.append("\(indent)• No results recorded")
                }
                for result in performance.results {
                    let detail = result.detail.map { " (\($0))" } ?? ""
                    lines.append("\(indent)• \(result.text)\(detail)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

extension CompetitionShare {

    /// While the event is on or yet to come, or a performance has nothing recorded, the recap starts labelled as results so far.
    static func looksUnfinished(event: ActivityEventDTO, appearances: [AppearanceDetailDTO], today: String) -> Bool {
        let status = ActivityHome.eventStatus(
            start: ActivityHome.dayKey(event.startDate),
            end: ActivityHome.dayKey(event.endDate),
            today: today
        )
        if status != .done { return true }
        return appearances.contains { $0.results.isEmpty && !Matchup($0.appearance).isRecorded }
    }

    init(
        event: ActivityEventDTO,
        seasonName: String,
        routines: [CompetitionRoutine],
        rosters: [Int: [Int]],
        people: ActivityPeople,
        options: Options,
        today: Date = .now
    ) {
        let start = event.startDate.serverDate
        let end = event.endDate.serverDate
        let spansDays = start != nil && end != nil && start?.recordDayKey != end?.recordDayKey

        let shared = routines.filter { !$0.appearances.isEmpty && !options.omitted.contains($0.entryId) }
        self.init(
            eventName: event.name,
            seasonName: seasonName,
            dates: ActivityDateText.range(from: event.startDate, to: event.endDate),
            place: Self.joined([event.host, event.location]),
            routines: shared.map { routine in
                Routine(
                    id: routine.entryId,
                    name: routine.name,
                    descriptors: routine.entry.map(ActivityEntryText.descriptors).flatMap { $0.isEmpty ? nil : $0 },
                    roster: options.showsNames ? people.rosterText(rosters[routine.entryId] ?? []) : nil,
                    summary: routine.appearances.count > 1
                        ? Self.nonEmpty(Matchups.runSummary(routine.appearances.map { Matchup($0.appearance) }))
                        : nil,
                    performances: routine.appearances.map { detail in
                        let matchup = Matchup(detail.appearance)
                        return Performance(
                            id: detail.id,
                            when: spansDays ? ActivityDateText.occurred(detail.appearance, at: detail.event) : nil,
                            matchup: matchup.isRecorded ? matchup.parts.joined(separator: " · ") : nil,
                            results: detail.results.map { Self.result($0, people: people, showsNames: options.showsNames) }
                        )
                    }
                )
            },
            snapshotLabel: options.isSnapshot
                ? Copy.share.asOf(today.formatted(date: .abbreviated, time: .omitted))
                : nil
        )
    }

    private static func result(_ result: ActivityResultDTO, people: ActivityPeople, showsNames: Bool) -> Result {
        var detail: [String] = []
        if !result.category.isEmpty { detail.append(result.category) }
        if let personId = result.personId, let name = people.name(personId) {
            detail.append(showsNames ? name : Copy.share.individual)
        }
        return Result(
            kind: ActivityResultKind(rawValue: result.kind),
            text: ActivityResultText.headline(result),
            detail: detail.isEmpty ? nil : detail.joined(separator: " · ")
        )
    }

    private static func joined(_ parts: [String]) -> String? {
        nonEmpty(parts.filter { !$0.isEmpty }.joined(separator: " · "))
    }

    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }
}

extension CompetitionShare {

    /// The recap as a hosted link stores it, matching the web's fields. `revisions` are the server's, by performance id: the server refuses a performance whose revision has moved on, and keeps neither ids nor revisions.
    func recapInput(revisions: [Int: Int]) -> RecapInputDTO {
        RecapInputDTO(
            eventName: eventName,
            subtitle: [seasonName.isEmpty ? nil : seasonName, dates].compactMap { $0 }.joined(separator: " · "),
            place: place ?? "",
            snapshotLabel: snapshotLabel ?? "",
            routines: routines.map { routine in
                RecapRoutineInputDTO(
                    entryId: routine.id,
                    name: routine.name,
                    descriptors: routine.descriptors ?? "",
                    roster: routine.roster ?? "",
                    summary: routine.summary ?? "",
                    performances: routine.performances.map { performance in
                        RecapPerformanceInputDTO(
                            appearanceId: performance.id,
                            revision: revisions[performance.id] ?? 0,
                            when: performance.when ?? "",
                            matchup: performance.matchup ?? "",
                            results: performance.results.map {
                                RecapResultDTO(kind: $0.kind?.rawValue ?? "", text: $0.text, detail: $0.detail ?? "")
                            }
                        )
                    }
                )
            }
        )
    }
}

/// How the recap falls onto PDF pages. Each group (the header, then each routine) starts a new page rather than split, unless it is taller than a page on its own; then its items run on across pages.
nonisolated enum SharePagination {
    struct Placement: Equatable, Sendable {
        let group: Int
        let item: Int
    }

    static func pages(groups: [[Double]], pageHeight: Double, spacing: Double) -> [[Placement]] {
        var pages: [[Placement]] = []
        var current: [Placement] = []
        var used = 0.0

        func place(_ placement: Placement, height: Double) {
            let needed = current.isEmpty ? height : used + spacing + height
            if !current.isEmpty && needed > pageHeight {
                pages.append(current)
                current = [placement]
                used = height
            } else {
                current.append(placement)
                used = needed
            }
        }

        for (group, items) in groups.enumerated() {
            let total = items.reduce(0, +) + spacing * Double(max(items.count - 1, 0))
            if !current.isEmpty && total <= pageHeight && used + spacing + total > pageHeight {
                pages.append(current)
                current = []
                used = 0
            }
            for (item, height) in items.enumerated() {
                place(Placement(group: group, item: item), height: height)
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }
}
