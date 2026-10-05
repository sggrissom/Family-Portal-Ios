import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Home")
struct HomeTests {

    // MARK: - Family strip (frontend/lib/familyStrip.test.ts)

    private static let zone = TimeZone(identifier: "America/Chicago")!

    private static let today: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 10))!
    }()

    private static func utc(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso + "T00:00:00Z")!
    }

    private static func age(_ born: String) -> String {
        FamilyStrip.compactAge(birthday: utc(born), today: today.localRecordDay(in: zone))
    }

    private static func due(_ date: String) -> String {
        FamilyStrip.dueSummary(dueDate: utc(date), today: today.localRecordDay(in: zone))
    }

    @Test("A newborn is counted in days and weeks")
    func newborn() {
        #expect(Self.age("2026-09-24") == "3d")
        #expect(Self.age("2026-09-06") == "3w")
    }

    @Test("Months under two")
    func months() {
        #expect(Self.age("2026-01-10") == "8m")
        #expect(Self.age("2024-10-01") == "23m")
    }

    @Test("Years and months for children, years for adults")
    func years() {
        #expect(Self.age("2023-05-02") == "3y 4m")
        #expect(Self.age("2019-09-27") == "7y")
        #expect(Self.age("1985-03-01") == "41y")
    }

    @Test("A date that has not come yet has no age")
    func future() {
        #expect(Self.age("2026-12-01") == "")
    }

    @Test("A due date counts down in weeks and days")
    func dueDates() {
        #expect(Self.due("2026-11-01") == "Due in 5w")
        #expect(Self.due("2026-11-03") == "Due in 5w 2d")
        #expect(Self.due("2026-09-30") == "Due in 3 days")
        #expect(Self.due("2026-09-27") == "Due today")
        #expect(Self.due("2026-09-26") == "Due date passed 1 day ago")
    }

    // MARK: - Nudges

    private static func scratch() -> UserDefaults {
        let name = "HomeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static func nudges(_ keys: [String]) throws -> [DashboardNudgeDTO] {
        try keys.map { key in
            try APIClient.decode(DashboardNudgeDTO.self, from: Fixture.data([
                "kind": "measure", "key": key, "text": key, "personId": 1, "count": 0,
            ]))
        }
    }

    @Test("At most two nudges show, in the server's order, minus the dismissed")
    func visibleNudges() throws {
        let dismissals = NudgeDismissals(defaults: Self.scratch())
        let all = try Self.nudges(["a", "b", "c"])

        #expect(dismissals.visible(all).map(\.key) == ["a", "b"])

        dismissals.dismiss("a")
        #expect(dismissals.visible(all).map(\.key) == ["b", "c"])
    }

    @Test("Dismissals are capped at the newest hundred")
    func dismissalCap() {
        let dismissals = NudgeDismissals(defaults: Self.scratch())
        for index in 0..<105 {
            dismissals.dismiss("n\(index)")
        }
        #expect(dismissals.keys.count == 100)
        #expect(dismissals.keys.first == "n5")
        #expect(dismissals.keys.last == "n104")
    }

    @Test("Dismissing again moves a key to the newest end rather than repeating it")
    func redismiss() {
        let dismissals = NudgeDismissals(defaults: Self.scratch())
        dismissals.dismiss("a")
        dismissals.dismiss("b")
        dismissals.dismiss("a")
        #expect(dismissals.keys == ["b", "a"])
    }

    // MARK: - Cached dashboard

    @Test("A cached dashboard reads back, and its day says whether it is today's")
    func cachedDashboard() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HomeTests-\(UUID().uuidString)")
        let cache = ActivitySnapshotCache(directory: directory)
        let payload = Fixture.data([
            "today": "2026-09-26",
            "people": [], "relations": [], "nudges": [], "seasons": [], "onThisDay": [],
            "recent": ["from": "2026-09-13", "photos": [], "milestones": [], "growth": []],
        ])
        await cache.store(payload, key: ActivitySnapshotKey(.getDashboard))

        let snapshot = await cache.load(GetDashboardResponseDTO.self, key: ActivitySnapshotKey(.getDashboard))

        #expect(snapshot?.value.today == "2026-09-26")
        #expect(snapshot?.value.today != "2026-09-27")
    }
}
