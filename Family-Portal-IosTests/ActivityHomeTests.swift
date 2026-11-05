import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/activityHome.test.ts, so the app and the web surface the same competitions.
@Suite("Activities home")
struct ActivityHomeTests {

    private struct Event {
        let id: Int
        let start: String
        let end: String
        let appearances: Int
    }

    private static func progress(_ events: [Event], hasEntries: Bool, today: String) -> ActivityHome.Progress<Event> {
        ActivityHome.seasonProgress(
            events,
            hasEntries: hasEntries,
            today: today,
            days: { ($0.start, $0.end) },
            appearances: { $0.appearances }
        )
    }

    private static let events = [
        Event(id: 1, start: "2026-01-10", end: "", appearances: 2),
        Event(id: 2, start: "2026-03-10", end: "", appearances: 1),
        Event(id: 3, start: "2026-05-10", end: "", appearances: 0),
        Event(id: 4, start: "2026-06-01", end: "2026-06-03", appearances: 0),
        Event(id: 5, start: "2026-08-10", end: "", appearances: 0),
        Event(id: 6, start: "2026-09-10", end: "", appearances: 0),
    ]

    @Test("An open-ended season is current once it starts")
    func seasonPhase() {
        #expect(ActivityHome.seasonPhase(start: "2026-01-01", end: "", today: "2026-10-01") == .current)
        #expect(ActivityHome.seasonPhase(start: "2026-01-01", end: "2026-06-01", today: "2026-10-01") == .past)
        #expect(ActivityHome.seasonPhase(start: "2026-11-01", end: "", today: "2026-10-01") == .upcoming)
        #expect(ActivityHome.seasonPhase(start: "", end: "", today: "2026-10-01") == .current)
    }

    @Test("Surfaces the latest result, what is missing, what is on, and what is next")
    func surfaces() {
        let progress = Self.progress(Self.events, hasEntries: true, today: "2026-06-02")
        #expect(progress.focus.map(\.event.id) == [2, 3, 4, 5])
        #expect(progress.focus.map(\.focus) == [.latest, .needsResults, .now, .next])
        #expect(progress.held == 3)
        #expect(progress.recorded == 2)
    }

    @Test("Asks for no results while the season has nothing entered")
    func noEntries() {
        let progress = Self.progress(Self.events, hasEntries: false, today: "2026-07-01")
        #expect(progress.focus.map(\.focus) == [.latest, .next])
    }

    @Test("Handles a season that has not started")
    func notStarted() {
        let progress = Self.progress(Self.events, hasEntries: true, today: "2025-12-01")
        #expect(progress.focus.map(\.event.id) == [1])
        #expect(progress.focus.map(\.focus) == [.next])
        #expect(progress.held == 0)
    }

    @MainActor
    @Test("The home read asks for the primary family and decodes each season's event counts")
    func readsHome() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetActivitiesHome", respond: .json([
            "familyId": 7,
            "activities": [Fixture.activity(id: 1)],
            "seasons": [[
                "season": Fixture.season(id: 3, startDate: "2026-01-01T00:00:00Z"),
                "events": [["event": Fixture.activityEvent(id: 9, startDate: "2026-03-10T00:00:00Z"), "appearances": 4]],
                "entries": NSNull()
            ]]
        ]))
        let service = ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("ActivityHome-\(UUID().uuidString)", isDirectory: true)
            )
        )

        let state = ActivityScreenState<GetActivitiesHomeResponseDTO>()
        await state.load(service.activitiesHome())

        let home = try #require(state.value)
        #expect(home.activities.count == 1)
        #expect(home.seasons.first?.events.first?.appearances == 4)
        #expect(home.seasons.first?.entries.isEmpty == true)
        #expect(ActivityHome.dayKey(home.seasons[0].season.endDate) == "")
        let request = try #require(server.requests(for: "rpc/GetActivitiesHome").first)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["familyId"] as? Int == 0)
    }
}

/// The cases from frontend/lib/activityResults.test.ts.
@Suite("Activity result summaries")
struct ActivityResultSummaryTests {

    private struct Result: ActivityResultLike {
        var kind: String
        var label = ""
        var rank: Int? = nil
        var outOf: Int? = nil
        var score: Double? = nil
    }

    private static func result(_ kind: ActivityResultKind, label: String = "", rank: Int? = nil, outOf: Int? = nil, score: Double? = nil) -> Result {
        Result(kind: kind.rawValue, label: label, rank: rank, outOf: outOf, score: score)
    }

    @Test("Ordinals keep 11th to 13th")
    func ordinals() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 32, 93, 111].map(ActivityResults.ordinal)
                == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "32nd", "93rd", "111th"])
    }

    @Test("A headline leads with the best placement and the adjudication")
    func headlineLeads() {
        #expect(ActivityResults.headline([
            Self.result(.placement, rank: 4, outOf: 20),
            Self.result(.adjudication, label: "Platinum"),
            Self.result(.placement, rank: 1, outOf: 6),
        ]) == "1st · Platinum")
    }

    @Test("A headline falls back to an award, then to whatever came first")
    func headlineFallsBack() {
        #expect(ActivityResults.headline([Self.result(.award, label: "Studio Choice")]) == "Studio Choice")
        #expect(ActivityResults.headline([Self.result(.score, label: "3–1 W")]) == "3–1 W")
        #expect(ActivityResults.headline([Result]()) == "")
    }

    @Test("A score whose label already starts with its number is shown once")
    func scoreText() {
        #expect(ActivityResults.text(Self.result(.score, label: "1 goal(s)", score: 1)) == "1 goal(s)")
        #expect(ActivityResults.text(Self.result(.score, label: "points", score: 92.5)) == "92.5 points")
        #expect(ActivityResults.text(Self.result(.placement, rank: 2, outOf: 9)) == "2nd of 9")
    }

    @Test("A grid cell sums a performance, a game, or a bracket")
    func cellHeadline() {
        typealias View = (matchup: Matchup, results: [Result])
        #expect(ActivityResults.cellHeadline([View]()) == "")
        #expect(ActivityResults.cellHeadline([(Matchup(), [
            Self.result(.adjudication, label: "High Gold"),
            Self.result(.placement, rank: 3, outOf: 18),
        ])]) == "3rd · High Gold")
        #expect(ActivityResults.cellHeadline([(Matchup(), [Result]())]) == "Recorded")
        #expect(ActivityResults.cellHeadline([(Matchup(outcome: "win", scoreFor: 3, scoreAgainst: 1), [Result]())]) == "W 3–1")
        #expect(ActivityResults.cellHeadline([(Matchup(outcome: "loss"), [Result]())]) == "L")
        #expect(ActivityResults.cellHeadline([
            (Matchup(outcome: "win"), [Result]()),
            (Matchup(outcome: "win"), [Result]()),
            (Matchup(outcome: "loss"), [Result]()),
        ]) == "2–1")
    }

    @Test("Adjudications are counted, most first")
    func adjudicationCounts() {
        let counts = ActivityResults.adjudicationCounts([
            Self.result(.adjudication, label: "High Gold"),
            Self.result(.adjudication, label: "Platinum"),
            Self.result(.adjudication, label: " Platinum "),
            Self.result(.award, label: "Platinum"),
            Self.result(.adjudication, label: ""),
        ])
        #expect(counts == [.init(label: "Platinum", count: 2), .init(label: "High Gold", count: 1)])
    }

    @Test("The best finish is the best placement across performances")
    func bestFinish() {
        let views: [(name: String, results: [Result])] = [
            ("autumn", [Self.result(.placement, rank: 3, outOf: 18)]),
            ("winter", [Self.result(.award, label: "Studio Choice")]),
            ("spring", [Self.result(.placement, rank: 1, outOf: 24)]),
        ]
        let best = ActivityResults.bestFinish(views) { $0.results }
        #expect(best?.view.name == "spring")
        #expect(best?.result.rank == 1)
        #expect(ActivityResults.bestFinish([views[1]]) { $0.results } == nil)
    }
}
