import Foundation
import Testing
@testable import Family_Portal_Ios

nonisolated private final class FixtureBundle {}

/// The golden cases in RecordTimeFixtures.json, copied verbatim from the web repo's frontend/lib/recordTimeFixtures.json, which the Go and web tests also run.
@Suite("Record time")
struct RecordTimeTests {

    nonisolated struct Expect: Decodable {
        let start: String
        let end: String
        let label: String
        let exactDay: Bool
    }

    nonisolated struct Case: Decodable {
        let name: String
        let record: RecordTime
        let birthday: String?
        let expect: Expect
    }

    nonisolated struct Fixtures: Decodable {
        let valid: [Case]
    }

    nonisolated static let fixtures: [Case] = {
        let url = Bundle(for: FixtureBundle.self).url(forResource: "RecordTimeFixtures", withExtension: "json")!
        return try! JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url)).valid
    }()

    @Test("matches the shared fixtures", arguments: fixtures.map(\.name))
    func fixture(_ name: String) {
        let f = Self.fixtures.first { $0.name == name }!
        let range = f.record.range(birthday: f.birthday)
        #expect(range.start == f.expect.start)
        #expect(range.end == f.expect.end)
        #expect(range.resolved == !f.expect.start.isEmpty)
        #expect(f.record.label == f.expect.label)
        #expect(f.record.isExactDay == f.expect.exactDay)
    }

    @Test func groupLabels() {
        var month = RecordTime()
        month.precision = "month"
        month.from = "2022-10"
        #expect(month.groupLabel == "Sometime in October 2022")
        var period = RecordTime()
        period.meaning = "period"
        period.basis = "age"
        period.precision = "year"
        period.ageYears = 4
        #expect(period.groupLabel == "At age 4")
    }

    @Test func decodesWhatOlderServersOmit() throws {
        let rt = try JSONDecoder().decode(RecordTime.self, from: Data(#"{"from":"2022-10-31"}"#.utf8))
        #expect(rt.isExactDay)
        #expect(rt.label == "Oct 31, 2022")
    }
}
