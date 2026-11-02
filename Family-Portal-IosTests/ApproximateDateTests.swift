import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// Records whose date is approximate, an age, or unknown: how they decode, store, group, match and show.
@MainActor
@Suite("Approximate dates")
struct ApproximateDateTests {

    static let context = try! TestStore.makeContext()

    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    static func ageFour(_ meaning: String = "period", anchor: Int = 5) -> RecordTime {
        var rt = RecordTime()
        rt.meaning = meaning
        rt.basis = "age"
        rt.precision = "year"
        rt.anchorPersonId = anchor
        rt.ageYears = 4
        rt.start = "2024-06-15"
        rt.end = "2025-06-15"
        rt.resolved = true
        return rt
    }

    static func month(_ from: String, start: String, end: String) -> RecordTime {
        var rt = RecordTime()
        rt.precision = "month"
        rt.from = from
        rt.start = start
        rt.end = end
        rt.resolved = true
        return rt
    }

    static func milestone(_ text: String, _ iso: String, _ rt: RecordTime?) -> Milestone {
        let milestone = Milestone(descriptionText: text, category: .other, date: date(iso))
        context.insert(milestone)
        milestone.recordTime = rt
        return milestone
    }

    @Test("Storing an assertion records whether the date is exact")
    func storesAssertion() {
        let exact = Self.milestone("party", "2024-06-15T00:00:00Z", .exact(day: "2024-06-15"))
        let period = Self.milestone("painting", "2024-06-15T00:00:00Z", Self.ageFour())
        let legacy = Self.milestone("old", "2024-06-15T00:00:00Z", nil)

        #expect(exact.hasExactDate)
        #expect(legacy.hasExactDate)
        #expect(!period.hasExactDate)
        #expect(period.recordTime == Self.ageFour())
        #expect(period.dateText(.long) == "At age 4")
    }

    @Test("History puts periods under their label, never a day, and undated records last")
    func groupsPeriods() {
        let party = Self.milestone("party", "2024-06-15T00:00:00Z", .exact(day: "2024-06-15"))
        let painting = Self.milestone("painting", "2024-06-15T00:00:00Z", Self.ageFour())
        var unknown = RecordTime()
        unknown.basis = "unknown"
        unknown.precision = "unknown"
        let shoebox = Self.milestone("shoebox", "0001-01-01T00:00:00Z", unknown)

        let days = DaySummaries.summarize(DayRecords(milestones: [party, painting, shoebox]), people: [])

        #expect(days.map(\.day) == ["2024-06-15", "2024-06-15", ""])
        #expect(days.map(\.period) == ["", "At age 4", "Date unknown"])
        #expect(days[1].milestones.map(\.descriptionText) == ["painting"])
        #expect(days[1].periodTo == "2025-06-14")
        #expect(days[0].id != days[1].id)
    }

    @Test("A period longer than a month gets a group of its own")
    func monthGroups() {
        let painting = Self.milestone("painting", "2024-06-15T00:00:00Z", Self.ageFour())
        let october = Self.milestone("trip", "2023-10-01T00:00:00Z", Self.month("2023-10", start: "2023-10-01", end: "2023-11-01"))

        let groups = DaySummaries.groupByMonth(DaySummaries.summarize(DayRecords(milestones: [painting, october]), people: []))

        #expect(groups.map(\.label) == ["", "October 2023"])
        #expect(groups[1].days.map(\.period) == ["Sometime in October 2023"])
    }

    @Test("Offline search matches an age period by overlap, and by age without a birthday")
    func offlineSearch() {
        let ada = SearchLocal.Person(id: UUID(), serverId: 5, name: "Ada", relationship: nil, birthday: nil)
        let painting = SearchLocal.Moment(
            id: UUID(), personServerId: 5, date: Self.date("2024-06-15T00:00:00Z"),
            category: .other, text: "Loved painting", recordTime: Self.ageFour()
        )
        let queryPeople = [SearchQuery.Person(id: 5, name: "Ada", relationship: nil)]
        func found(_ query: String) -> Bool {
            let parsed = SearchQuery.parse(query, people: queryPeople, tags: [])
            return !SearchLocal.search(parsed, people: [ada], moments: [painting], photos: []).moments.isEmpty
        }

        #expect(found("painting 2025"))
        #expect(!found("painting 2026"))
        #expect(!found("painting june"))
        #expect(SearchLocal.ageSpan(Self.ageFour(), personId: 5, birthday: nil) == 48..<60)
        #expect(SearchLocal.ageSpan(Self.ageFour(), personId: 6, birthday: nil) == nil)
    }

    @Test("A widget says how the family dated a memory instead of inventing a day")
    func widgetDating() throws {
        let item = WidgetItem(id: "milestone:1", kind: .milestone, date: "2024-06-15", yearsAgo: nil, dateLabel: "At age 4", title: "painting", personIds: [], link: "/")
        let moment = WidgetMoment(source: .memory, items: [item])
        #expect(moment.dating(item) == .period("At age 4"))
        #expect(moment.dating(item).when == "At age 4")

        let older = #"{"id":"photo:1","kind":"photo","date":"2024-06-15","title":"","personIds":[],"link":"/"}"#
        let decoded = try JSONDecoder().decode(WidgetItem.self, from: Data(older.utf8))
        #expect(decoded.dateLabel == nil)
    }

    @Test("DTOs carry the assertion and tolerate servers without it")
    func decoding() throws {
        let json = """
        {
          "id": 77, "personId": 5, "familyId": 7, "description": "Loved painting", "category": "other",
          "milestoneDate": "2024-06-15T00:00:00Z", "createdAt": "2026-11-02T10:00:00Z",
          "recordTime": {"version": 1, "meaning": "period", "basis": "age", "precision": "year",
            "estimated": false, "anchorPersonId": 5, "ageYears": 4, "ageMonths": 0, "ageToYears": 0,
            "source": "family", "changedAt": "2026-11-02T10:00:00Z",
            "start": "2024-06-15", "end": "2025-06-15", "resolved": true, "resolverVersion": 1}
        }
        """
        let dto = try APIClient.decode(MilestoneDTO.self, from: Data(json.utf8))
        #expect(dto.recordTime?.label == "At age 4")
        #expect(dto.recordTime?.isExactDay == false)

    }
}
