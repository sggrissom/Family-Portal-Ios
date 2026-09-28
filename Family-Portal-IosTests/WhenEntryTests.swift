import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/when.test.ts.
@Suite("When entry")
struct WhenEntryTests {

    private static let chicago = TimeZone(identifier: "America/Chicago")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = chicago
        return calendar
    }

    private static func local(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static let now = local(2026, 9, 27, hour: 9, minute: 30)

    @Test("Today is sent as the local date, not the server's")
    func todayIsLocal() {
        #expect(WhenEntry().request(now: Self.now, calendar: Self.calendar) == WhenEntry.Request(
            inputType: "date", date: "2026-09-27", ageYears: nil, ageMonths: nil
        ))
    }

    @Test("A late evening is still today, even where UTC has moved on")
    func lateEveningIsStillToday() {
        let evening = Self.local(2026, 9, 27, hour: 22, minute: 45)
        #expect(WhenEntry().request(now: evening, calendar: Self.calendar).date == "2026-09-27")
    }

    @Test("Yesterday is a local date, across a month end")
    func yesterdayIsLocal() {
        let entry = WhenEntry(mode: .yesterday)
        #expect(entry.request(now: Self.now, calendar: Self.calendar).date == "2026-09-26")
        #expect(entry.request(now: Self.local(2026, 3, 1), calendar: Self.calendar).date == "2026-02-28")
    }

    @Test("A picked date is sent as is")
    func pickedDate() {
        let entry = WhenEntry(mode: .date, date: Self.local(2025, 12, 24))
        let request = entry.request(now: Self.now, calendar: Self.calendar)
        #expect(request.inputType == "date")
        #expect(request.date == "2025-12-24")
    }

    @Test("Blank months are zero")
    func blankMonthsAreZero() {
        let entry = WhenEntry(mode: .age, ageYears: 3)
        let request = entry.request(now: Self.now, calendar: Self.calendar)
        #expect(request == WhenEntry.Request(inputType: "age", date: nil, ageYears: 3, ageMonths: 0))
    }

    @Test("A date or an age is needed when those are chosen")
    func problems() {
        #expect(WhenEntry().problem == nil)
        #expect(WhenEntry(mode: .date).problem == "Pick a date")
        #expect(WhenEntry(mode: .age).problem == "Enter an age in years")
        #expect(WhenEntry(mode: .age, ageYears: 2, ageMonths: 12).problem == "Months should be 0 to 11")
    }

    @Test("An age resolves against the birthday, and needs one")
    func ageResolves() {
        let birthday = Self.local(2020, 6, 15)
        let entry = WhenEntry(mode: .age, ageYears: 3, ageMonths: 2)

        #expect(entry.resolvedDate(birthday: birthday, now: Self.now, calendar: Self.calendar) == Self.local(2023, 8, 15))
        #expect(entry.resolvedDate(birthday: nil, now: Self.now, calendar: Self.calendar) == nil)
    }

    @Test("An entry with a problem resolves to nothing")
    func problemResolvesToNothing() {
        #expect(WhenEntry(mode: .date).resolvedDate(birthday: nil, now: Self.now) == nil)
    }
}
