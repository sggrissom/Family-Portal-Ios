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
