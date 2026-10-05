import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Calendar date timezone regressions")
struct CalendarDateRegressionTests {
    private func utc(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    @Test("Server dates survive an unchanged activity save in every zone",
          arguments: ["UTC", "America/Chicago", "America/Los_Angeles", "Asia/Tokyo", "Pacific/Kiritimati"])
    func activityRoundTrip(zone: String) {
        let zone = TimeZone(identifier: zone)!
        let stored = utc("2024-03-01T00:00:00Z")
        #expect(ServerDateFormat.requestString(stored, in: zone) == "2024-03-01")
        let picker = stored.localDay(in: zone)
        #expect(ServerDateFormat.requestString(picker, in: zone) == "2024-03-01")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.component(.day, from: picker) == 1)
        #expect(calendar.component(.month, from: picker) == 3)
        #expect(ServerDateFormat.requestString(nil, in: zone) == nil)
    }

    @Test("Bare dates decode to the same instant as UTC-midnight dates")
    func bareDate() throws {
        struct Record: Decodable { let date: Date }
        let record = try APIClient.decode(Record.self, from: Data(#"{"date":"2024-03-01"}"#.utf8))
        #expect(record.date == utc("2024-03-01T00:00:00Z"))
    }

    @Test("Growth age mixes local birthdays and server measurement dates safely",
          arguments: ["UTC", "America/Chicago", "Asia/Tokyo", "Pacific/Kiritimati"])
    func growthAge(zone: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        let birthday = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1))!
        let measured = utc("2024-04-15T00:00:00Z")
        let age = GrowthPercentiles.ageInMonths(birthday: birthday, on: measured, calendar: calendar)
        #expect(abs(age - (1 + 14 / 30.4375)) < 0.000001)
    }

    @Test("Yesterday means a calendar day across both DST transitions")
    func yesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        for (month, day, stored) in [(3, 11, "2024-03-10T00:00:00Z"), (11, 4, "2024-11-03T00:00:00Z")] {
            let now = calendar.date(from: DateComponents(year: 2024, month: month, day: day, hour: 0, minute: 30))!
            #expect(Checkup.timeAgo(utc(stored), now: now, calendar: calendar) == "yesterday")
        }
    }
}
