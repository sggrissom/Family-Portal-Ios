import Foundation
import Testing
@testable import Family_Portal_Ios

/// The timeline's person, type and year filters moved into `@Query` predicates,
/// so the two pieces of arithmetic they are built from are worth pinning: a year
/// boundary the predicate disagrees with is a record that vanishes from the chip
/// that should hold it, and there is no test the store itself can fail.
@Suite("Timeline filters")
struct TimelineFilterTests {

    // MARK: - Year bounds

    /// The predicate's range has to agree with `Calendar.component(.year:)`,
    /// which is what built the chip the user tapped.
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

    /// Half-open, so midnight on 1 January belongs to exactly one year. Closed
    /// bounds would put it in both, and a record dated then would show under two
    /// different chips.
    @Test("Midnight on 1 January belongs to the year starting, not the one ending")
    func theBoundaryInstantBelongsToOneYearOnly() throws {
        let calendar = Calendar.current
        let start2026 = TimelineYear.bounds(2026, calendar: calendar).start

        // The instant is the end of 2025's range and the start of 2026's, and the
        // predicate is `>= start && < end`.
        #expect(TimelineYear.bounds(2025, calendar: calendar).end == start2026)
        #expect(start2026 >= TimelineYear.bounds(2026, calendar: calendar).start)
        #expect(start2026 < TimelineYear.bounds(2026, calendar: calendar).end)
        #expect(!(start2026 < TimelineYear.bounds(2025, calendar: calendar).end))
    }

    /// The "All Years" chip. `distantPast ..< distantFuture` is what lets the
    /// predicate keep one shape whether or not a year is chosen.
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

    /// `.all` is the only case that admits a kind other than its own — this is
    /// what decides whether a query is built at all or replaced with one that
    /// matches nothing.
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
