import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Growth comparison")
struct GrowthComparisonTests {

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func sample(_ value: Double, _ unit: MeasurementUnit, on day: Date) -> GrowthComparison.Sample {
        GrowthComparison.Sample(date: day, value: value, unit: unit)
    }

    private static let mia = UUID()
    private static let ben = UUID()
    private static let miaBorn = date(2016, 4, 11)
    private static let benBorn = date(2019, 8, 1)

    /// Mia measured 30 in at twelve months; the question is always how Ben stood against that.
    private static let miaAtOne = sample(30, .inches, on: date(2017, 4, 11))

    private static func benCandidate(_ samples: [GrowthComparison.Sample], born: Date? = benBorn, isPregnancy: Bool = false) -> GrowthComparison.Candidate {
        GrowthComparison.Candidate(id: ben, birthday: born, isPregnancy: isPregnancy, samples: samples)
    }

    private static func compare(_ candidates: [GrowthComparison.Candidate]) -> [GrowthComparison.Entry] {
        GrowthComparison.compare(target: miaAtOne, targetBirthday: miaBorn, targetPersonId: mia, among: candidates)
    }

    // MARK: - Matching

    @Test("A record at the same age is matched, and the gap is read in the relative's own unit")
    func matchesTheSameAge() throws {
        let entries = Self.compare([Self.benCandidate([Self.sample(74, .centimeters, on: Self.date(2020, 8, 1))])])

        let point = try #require(entries.first?.atSameAge)
        #expect(point.unit == .centimeters)
        #expect(abs(point.valueDiff - (76.2 - 74)) < 1e-9)
        #expect(abs(point.ageDiffMonths) < 1e-9)
        // 74 cm is well outside 2% of 76.2 cm, so it is not also "reached this height".
        #expect(entries.first?.atSameValue == nil)
    }

    @Test("A record at the same value is matched, whatever age it came at")
    func matchesTheSameValue() throws {
        let entries = Self.compare([Self.benCandidate([Self.sample(30.2, .inches, on: Self.date(2020, 11, 1))])])

        let point = try #require(entries.first?.atSameValue)
        #expect(abs(point.ageDiffMonths - 3) < 1e-9)
        #expect(entries.first?.atSameAge == nil)
    }

    @Test("A relative with nothing close is left out, one with no records at all is kept")
    func farAwayRecordsAreDropped() {
        let far = Self.compare([Self.benCandidate([Self.sample(40, .inches, on: Self.date(2023, 8, 1))])])
        let none = Self.compare([Self.benCandidate([])])

        #expect(far.isEmpty)
        #expect(none.map(\.hasNoRecords) == [true])
    }

    @Test("The person themselves, pregnancies and anyone without a birthday are skipped")
    func skipsWhoCannotBeCompared() {
        let own = GrowthComparison.Candidate(id: Self.mia, birthday: Self.miaBorn, isPregnancy: false, samples: [Self.miaAtOne])
        let entries = Self.compare([
            own,
            Self.benCandidate([], isPregnancy: true),
            Self.benCandidate([], born: nil),
        ])

        #expect(entries.isEmpty)
    }

    // MARK: - Wording

    @Test("The value gap names the person being viewed")
    func describesTheValueGap() throws {
        let entries = Self.compare([Self.benCandidate([Self.sample(29, .inches, on: Self.date(2020, 8, 1))])])
        let point = try #require(entries.first?.atSameAge)

        #expect(GrowthComparison.describeValue(point, type: .height, subject: "Mia") == "Mia was 1 in taller at this age")
    }

    @Test("The age gap says whether the relative got there sooner or later")
    func describesTheAgeGap() throws {
        let later = try #require(Self.compare([Self.benCandidate([Self.sample(30, .inches, on: Self.date(2020, 11, 1))])]).first?.atSameValue)
        let sameTime = try #require(Self.compare([Self.benCandidate([Self.sample(30, .inches, on: Self.date(2020, 8, 5))])]).first?.atSameValue)

        #expect(GrowthComparison.describeAge(later, subject: "Mia") == "3 mo later than Mia")
        #expect(GrowthComparison.describeAge(sameTime, subject: "Mia") == "about the same age as Mia")
    }

    @Test("Durations read in months, then years and months")
    func formatsDurations() {
        #expect(GrowthComparison.formatDuration(months: 5.2) == "5 mo")
        #expect(GrowthComparison.formatDuration(months: 24) == "2 yr")
        #expect(GrowthComparison.formatDuration(months: 14) == "1 yr 2 mo")
    }

    // MARK: - Grouping

    @Test("Siblings come first, then parents, then everyone else")
    func groupsByRelation() {
        let steven = UUID()
        let rose = UUID()
        let entries = [Self.ben, steven, rose].map {
            GrowthComparison.Entry(personId: $0, atSameAge: nil, atSameValue: nil)
        }
        let edges = [
            RelationEdge(fromId: 2, toId: 4, kind: .parent),
            RelationEdge(fromId: 2, toId: 5, kind: .parent),
        ]

        let groups = GrowthComparison.group(
            entries,
            subjectRemoteId: 4,
            remoteIds: [Self.ben: 5, steven: 2, rose: 1],
            relations: edges
        )

        #expect(groups.map(\.title) == ["Siblings", "Parents", "Rest of the family"])
        #expect(groups.map { $0.entries.map(\.personId) } == [[Self.ben], [steven], [rose]])
    }

    @Test("With no edges to go on, everyone is simply family")
    func ungroupedFamily() {
        let entries = [GrowthComparison.Entry(personId: Self.ben, atSameAge: nil, atSameValue: nil)]

        let groups = GrowthComparison.group(entries, subjectRemoteId: nil, remoteIds: [:], relations: [])

        #expect(groups.map(\.title) == ["Family"])
    }

    // MARK: - Since the last measurement

    @Test("The change is from the latest earlier record, converted into this one's unit")
    func changeSinceTheLastRecord() throws {
        let earlier = [
            Self.sample(70, .centimeters, on: Self.date(2017, 1, 11)),
            Self.sample(29, .inches, on: Self.date(2017, 3, 11)),
            Self.sample(31, .inches, on: Self.date(2017, 6, 11)),
        ]

        let change = try #require(GrowthComparison.change(from: earlier, to: Self.miaAtOne))

        #expect(change.previous.date == Self.date(2017, 3, 11))
        #expect(abs(change.difference - 1) < 1e-9)
        #expect(change.elapsedDays == 31)
    }

    @Test("A first measurement has no change")
    func firstMeasurementHasNoChange() {
        #expect(GrowthComparison.change(from: [], to: Self.miaAtOne) == nil)
    }

    @Test("Short gaps keep their precision")
    func formatsElapsedTime() {
        #expect(GrowthComparison.formatElapsed(days: 1) == "1 day")
        #expect(GrowthComparison.formatElapsed(days: 10) == "10 days")
        #expect(GrowthComparison.formatElapsed(days: 21) == "3 wk")
        #expect(GrowthComparison.formatElapsed(days: 92) == "3 mo")
    }
}
