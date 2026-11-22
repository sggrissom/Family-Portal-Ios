import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Measurement share")
struct MeasurementShareTests {

    nonisolated private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func sample() -> MeasurementShare {
        MeasurementShare(
            personName: "Mia",
            dateText: "April 11, 2017",
            ageText: "1 year",
            sections: [
                MeasurementShare.Section(
                    id: UUID(),
                    type: .height,
                    value: "30.0 in",
                    alternate: "76.2 cm",
                    rows: [
                        .init(id: "since", group: nil, heading: "Since last", lines: [.init(title: "+1.0 in over 4 wk", detail: nil)]),
                        .init(id: "ben", group: "Siblings", heading: "Ben · Brother", lines: [
                            .init(title: "At 12 mo: 29.5 in", detail: "Mia was 0.5 in taller at this age"),
                        ]),
                    ]
                ),
            ]
        )
    }

    @Test("The text carries the value, then each comparison under its group")
    func text() {
        #expect(Self.sample().text == """
        Mia · April 11, 2017 · 1 year

        Height: 30.0 in (76.2 cm)
        • Since last: +1.0 in over 4 wk
        Siblings:
        • Ben · Brother: At 12 mo: 29.5 in — Mia was 0.5 in taller at this age
        """)
    }

    @Test("An omitted comparison leaves the card and the text alike")
    func omitting() {
        let share = Self.sample().omitting(["ben"])
        #expect(share.rowIds == ["since"])
        #expect(!share.text.contains("Ben"))
        #expect(!share.text.contains("Siblings"))
        #expect(Self.sample().omitting(Set(Self.sample().rowIds)).text == """
        Mia · April 11, 2017 · 1 year

        Height: 30.0 in (76.2 cm)
        """)
    }

    @Test("A saved measurement shares with its change, percentile and family comparison, before it has synced")
    func builtFromTheStore() throws {
        let context = try TestStore.makeContext()
        let mia = Person(name: "Mia", gender: .female, birthday: Self.day(2016, 4, 11))
        let ben = Person(name: "Ben", gender: .male, birthday: Self.day(2019, 8, 1))
        context.insert(mia)
        context.insert(ben)

        let earlier = GrowthData(measurementType: .height, value: 29, unit: .inches, date: Self.day(2017, 3, 11))
        let latest = GrowthData(measurementType: .height, value: 30, unit: .inches, date: Self.day(2017, 4, 11))
        let bens = GrowthData(measurementType: .height, value: 29.5, unit: .inches, date: Self.day(2020, 8, 1))
        for record in [earlier, latest] {
            context.insert(record)
            record.person = mia
        }
        context.insert(bens)
        bens.person = ben
        try context.save()

        #expect(latest.remoteId == nil)
        let share = try #require(MeasurementShare(measurements: [latest], people: [mia, ben], relations: []))
        let section = try #require(share.sections.first)
        #expect(share.personName == "Mia")
        #expect(section.value == "30 in")
        #expect(section.rows.map(\.heading).first == "Since last")
        #expect(section.rows.contains { $0.id.hasSuffix("-percentile") })
        let benRow = try #require(section.rows.first { $0.heading == "Ben" })
        #expect(benRow.group == "Family")
        #expect(benRow.lines.first?.title == "At 12 mo: 29.5 in")
        #expect(benRow.lines.first?.detail == "Mia was 0.5 in taller at this age")
        #expect(!share.text.contains("2016"))

        let without = share.omitting([benRow.id])
        #expect(!without.text.contains("Ben"))
        #expect(without.text.contains("Since last"))
    }
}

@MainActor
@Suite("Competition share")
struct CompetitionShareTests {

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try APIClient.decode(T.self, from: Fixture.data(object))
    }

    private static let held = "2025-11-08T00:00:00Z"

    private func event(start: String = held, end: String = held) throws -> ActivityEventDTO {
        try decode(ActivityEventDTO.self, Fixture.activityEvent(id: 3, startDate: start, endDate: end, notes: "Hotel is the Marriott"))
    }

    private func fixtures(soloResults: [[String: Any]]? = nil) throws -> (entries: [ActivityEntryDTO], appearances: [AppearanceDetailDTO]) {
        let group = Fixture.activityEntry(id: 1, name: "Rise Up")
        let solo = Fixture.activityEntry(id: 2, name: "Firework", format: "solo", style: "Jazz", division: "Junior", level: "")
        let summary = Fixture.eventSummary(id: 3, startDate: Self.held, endDate: Self.held)
        let entries = try [group, solo].map { try decode(ActivityEntryDTO.self, $0) }
        // The solo was entered first, but the season lists the group first.
        let appearances = try [
            Fixture.appearanceDetail(
                Fixture.appearance(id: 11, eventId: 3, entryId: 2, notes: "Fell on the turn"),
                results: soloResults ?? [
                    Fixture.activityResult(id: 21, appearanceId: 11, kind: "placement", label: "", rank: 1, outOf: 14),
                    Fixture.activityResult(id: 22, appearanceId: 11, kind: "adjudication", label: "Platinum", notes: "Judge 2 loved it"),
                ],
                entry: solo,
                event: summary
            ),
            Fixture.appearanceDetail(
                Fixture.appearance(id: 10, eventId: 3, entryId: 1),
                results: [
                    Fixture.activityResult(id: 20, appearanceId: 10, kind: "adjudication", label: "High Gold"),
                    Fixture.activityResult(id: 23, appearanceId: 10, kind: "award", label: "Judges' Choice", category: "Technique", personId: 5),
                ],
                entry: group,
                event: summary
            ),
        ].map { try decode(AppearanceDetailDTO.self, $0) }
        return (entries, appearances)
    }

    private func share(_ options: CompetitionShare.Options = .init()) throws -> CompetitionShare {
        let (entries, appearances) = try fixtures()
        return CompetitionShare(
            event: try event(),
            seasonName: "2025-26 Season",
            routines: CompetitionRoutine.list(entries: entries, appearances: appearances),
            rosters: [1: [5, 6]],
            people: ActivityPeople([Person(remoteId: "5", name: "Clara", gender: .female), Person(remoteId: "6", name: "Ada", gender: .female)]),
            options: options
        )
    }

    @Test("Routines keep the page's order, each with all of its results")
    func order() throws {
        let share = try share()
        #expect(share.routines.map(\.name) == ["Rise Up", "Firework"])
        #expect(share.routines[0].performances[0].results.map(\.text) == ["High Gold", "Judges' Choice"])
        #expect(share.routines[1].performances[0].results.count == 2)
        #expect(share.routines[1].descriptors == "solo · Jazz · Junior")
    }

    @Test("An omitted routine is left out of the recap and its text")
    func omitted() throws {
        let share = try share(.init(omitted: [2]))
        #expect(share.routines.map(\.name) == ["Rise Up"])
        #expect(!share.text.contains("Firework"))
    }

    @Test("Names stay out unless asked for, but a dancer's own award still reads as one")
    func names() throws {
        let hidden = try share()
        #expect(hidden.routines[0].roster == nil)
        #expect(hidden.routines[0].performances[0].results[1].detail == "Technique · \(Copy.share.individual)")
        #expect(!hidden.text.contains("Clara"))

        let shown = try share(.init(showsNames: true))
        #expect(shown.routines[0].roster == "Clara and Ada")
        #expect(shown.routines[0].performances[0].results[1].detail == "Technique · Clara")
    }

    @Test("Notes never go out")
    func notes() throws {
        let text = try share(.init(showsNames: true)).text
        #expect(!text.contains("Marriott"))
        #expect(!text.contains("Fell on the turn"))
        #expect(!text.contains("Judge 2"))
        #expect(text.contains("Nuvo · Nashville, TN"))
    }

    @Test("A snapshot is labelled with the day it was shared")
    func snapshot() throws {
        let share = try share(.init(isSnapshot: true))
        #expect(share.snapshotLabel?.hasPrefix("Results so far, as of ") == true)
        #expect(share.text.contains("Results so far"))
        #expect(try self.share().snapshotLabel == nil)
    }

    @Test("A recap starts as a snapshot while the event is on, or a performance has nothing recorded")
    func unfinished() throws {
        let (_, appearances) = try fixtures()
        #expect(!CompetitionShare.looksUnfinished(event: try event(), appearances: appearances, today: "2025-12-01"))
        #expect(CompetitionShare.looksUnfinished(event: try event(), appearances: appearances, today: "2025-11-08"))

        let (_, empty) = try fixtures(soloResults: [])
        #expect(CompetitionShare.looksUnfinished(event: try event(), appearances: empty, today: "2025-12-01"))
    }
}

@Suite("Share pagination")
struct SharePaginationTests {

    private typealias P = SharePagination.Placement

    @Test("Routines that fit share a page")
    func fits() {
        let pages = SharePagination.pages(groups: [[100], [200], [200]], pageHeight: 700, spacing: 10)
        #expect(pages == [[P(group: 0, item: 0), P(group: 1, item: 0), P(group: 2, item: 0)]])
    }

    @Test("A routine that would straddle a break starts the next page whole")
    func breaksBetweenRoutines() {
        let pages = SharePagination.pages(groups: [[100], [300, 200], [150, 150]], pageHeight: 700, spacing: 10)
        #expect(pages == [
            [P(group: 0, item: 0), P(group: 1, item: 0), P(group: 1, item: 1)],
            [P(group: 2, item: 0), P(group: 2, item: 1)],
        ])
    }

    @Test("A routine taller than a page runs on, a performance at a time")
    func splitsALongRoutine() {
        let pages = SharePagination.pages(groups: [[100], [400, 400, 400]], pageHeight: 700, spacing: 10)
        #expect(pages == [
            [P(group: 0, item: 0), P(group: 1, item: 0)],
            [P(group: 1, item: 1)],
            [P(group: 1, item: 2)],
        ])
    }

    @Test("Every block lands on exactly one page")
    func keepsEverything() {
        let groups: [[Double]] = [[80], [900], [120, 60], [700], [10, 10, 10]]
        let placed = SharePagination.pages(groups: groups, pageHeight: 700, spacing: 16).flatMap { $0 }
        let expected = groups.enumerated().flatMap { group, items in items.indices.map { P(group: group, item: $0) } }
        #expect(placed == expected)
    }
}
