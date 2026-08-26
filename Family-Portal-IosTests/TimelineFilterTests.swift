import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Timeline filters")
struct TimelineFilterTests {

    // MARK: - Year bounds

    @Test("A year's bounds run from its first instant to the next year's")
    func boundsCoverExactlyOneYear() throws {
        let calendar = Calendar.current
        let bounds = TimelineYear.bounds(2025, calendar: calendar)

        #expect(calendar.component(.year, from: bounds.start) == 2025)
        #expect(calendar.component(.month, from: bounds.start) == 1)
        #expect(calendar.component(.day, from: bounds.start) == 1)
        #expect(calendar.component(.year, from: bounds.end) == 2026)
        #expect(calendar.component(.month, from: bounds.end) == 1)
        #expect(calendar.component(.day, from: bounds.end) == 1)
    }

    @Test("Midnight on 1 January belongs to the year starting, not the one ending")
    func theBoundaryInstantBelongsToOneYearOnly() throws {
        let calendar = Calendar.current
        let start2026 = TimelineYear.bounds(2026, calendar: calendar).start

        #expect(TimelineYear.bounds(2025, calendar: calendar).end == start2026)
        #expect(start2026 >= TimelineYear.bounds(2026, calendar: calendar).start)
        #expect(start2026 < TimelineYear.bounds(2026, calendar: calendar).end)
        #expect(!(start2026 < TimelineYear.bounds(2025, calendar: calendar).end))
    }

    @Test("No year selected admits everything")
    func noYearAdmitsEverything() {
        let bounds = TimelineYear.bounds(nil)
        #expect(bounds.start == .distantPast)
        #expect(bounds.end == .distantFuture)

        let now = Date()
        #expect(now >= bounds.start && now < bounds.end)
    }

    @Test("A leap year still ends on the following 1 January")
    func leapYearsEndWhereTheyShould() throws {
        let calendar = Calendar.current
        let bounds = TimelineYear.bounds(2024, calendar: calendar)

        let leapDay = try #require(calendar.date(from: DateComponents(year: 2024, month: 2, day: 29)))
        #expect(leapDay >= bounds.start && leapDay < bounds.end)
        #expect(calendar.component(.year, from: bounds.end) == 2025)
    }

    // MARK: - Type filter

    @Test("All Activity admits every kind")
    func allAdmitsEveryKind() {
        for kind in TimelineFilterType.allCases {
            #expect(TimelineFilterType.all.includes(kind))
        }
    }

    @Test(
        "Every other filter admits only its own kind",
        arguments: [TimelineFilterType.milestones, .measurements, .photos]
    )
    func narrowFiltersAdmitOnlyThemselves(filter: TimelineFilterType) {
        for kind in TimelineFilterType.allCases where kind != .all {
            #expect(filter.includes(kind) == (kind == filter))
        }
    }
}
