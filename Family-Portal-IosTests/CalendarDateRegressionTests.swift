import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Calendar date timezone regressions")
struct CalendarDateRegressionTests {
    private func utc(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func local(_ zone: TimeZone, _ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static let zones = ["UTC", "America/Chicago", "America/Los_Angeles", "Asia/Tokyo", "Pacific/Kiritimati"]

    @Test("Server dates survive an unchanged activity save in every zone", arguments: zones)
    func activityRoundTrip(zone: String) {
        let zone = TimeZone(identifier: zone)!
        let stored = utc("2024-03-01T00:00:00Z")
        #expect(ServerDateFormat.requestString(stored) == "2024-03-01")
        let picker = stored.displayDay(in: zone)
        #expect(ServerDateFormat.requestString(picker.localRecordDay(in: zone)) == "2024-03-01")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(calendar.component(.day, from: picker) == 1)
        #expect(calendar.component(.month, from: picker) == 3)
        #expect(ServerDateFormat.requestString(nil) == nil)
    }

    @Test("A picked or current day is stored as that day at UTC midnight", arguments: zones)
    func localRecordDay(zone: String) {
        let zone = TimeZone(identifier: zone)!
        for hour in [0, 9, 23] {
            let instant = local(zone, 2024, 12, 31, hour: hour, minute: 30)
            #expect(instant.localRecordDay(in: zone) == utc("2024-12-31T00:00:00Z"))
        }
    }

    @Test("A record date names the same day in every zone", arguments: zones)
    func recordDayIgnoresTheDeviceZone(zone: String) {
        let zone = TimeZone(identifier: zone)!
        let midnight = utc("2024-03-10T00:00:00Z")
        #expect(midnight.recordDayKey == "2024-03-10")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let shown = calendar.dateComponents([.year, .month, .day], from: midnight.displayDay(in: zone))
        #expect(shown.year == 2024 && shown.month == 3 && shown.day == 10)
    }

    @Test("A photo keeps its capture day and wall-clock time", arguments: zones)
    func photoWallClock(zone: String) {
        let zone = TimeZone(identifier: zone)!
        let stored = local(zone, 2024, 7, 4, hour: 23, minute: 30).localWallClock(in: zone)
        #expect(stored == utc("2024-07-04T23:30:00Z"))
        #expect(stored.recordDayKey == "2024-07-04")
    }

    @Test("A server record date carrying a time is stored as its UTC day")
    func serverRecordDateWithTime() throws {
        let json = #"{"id":1,"personId":1,"familyId":1,"measurementType":0,"value":30,"unit":"in","measurementDate":"2024-03-01T22:15:00Z","createdAt":"2024-03-01T22:15:00Z"}"#
        let dto = try APIClient.decode(GrowthDataDTO.self, from: Data(json.utf8))
        #expect(growthDataFromDTO(dto).date == utc("2024-03-01T00:00:00Z"))
    }

    @Test("Bare dates decode to the same instant as UTC-midnight dates")
    func bareDate() throws {
        struct Record: Decodable { let date: Date }
        let record = try APIClient.decode(Record.self, from: Data(#"{"date":"2024-03-01"}"#.utf8))
        #expect(record.date == utc("2024-03-01T00:00:00Z"))
    }

    @Test("Growth age reads birthdays and measurement dates as record dates")
    func growthAge() {
        let age = GrowthPercentiles.ageInMonths(birthday: utc("2024-03-01T00:00:00Z"), on: utc("2024-04-15T00:00:00Z"))
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

    @Test("Stored dates migrate to record dates as earlier builds read them", arguments: zones)
    func migration(zone: String) throws {
        let zone = TimeZone(identifier: zone)!
        let context = try TestStore.makeContext()

        let person = Person(name: "Clara", gender: .female, birthday: local(zone, 2020, 6, 15))
        let fromServer = GrowthData(measurementType: .height, value: 30, unit: .inches, date: utc("2024-03-01T00:00:00Z"))
        let entered = GrowthData(measurementType: .weight, value: 20, unit: .pounds, date: local(zone, 2024, 3, 2, hour: 21))
        let milestone = Milestone(descriptionText: "Walked", category: .first, date: local(zone, 2024, 5, 1))
        let synced = Photo(title: "", descriptionText: "", photoDate: utc("2024-07-04T21:30:00Z"))
        synced.remoteId = "9"
        let pending = Photo(title: "", descriptionText: "", photoDate: local(zone, 2024, 7, 4, hour: 23, minute: 15))
        context.insert(person)
        context.insert(fromServer)
        context.insert(entered)
        context.insert(milestone)
        context.insert(synced)
        context.insert(pending)

        try CalendarDateMigration.migrate(context, timeZone: zone)

        #expect(person.birthday == utc("2020-06-15T00:00:00Z"))
        #expect(fromServer.date == utc("2024-03-01T00:00:00Z"))
        #expect(entered.date == utc("2024-03-02T00:00:00Z"))
        #expect(milestone.date == utc("2024-05-01T00:00:00Z"))
        #expect(synced.photoDate == utc("2024-07-04T21:30:00Z"))
        #expect(pending.photoDate == utc("2024-07-04T23:15:00Z"))
    }
}
