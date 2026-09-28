import Foundation
import Testing
@testable import Family_Portal_Ios

/// "By age…" in `WhenControl`: an age resolves against the birthday on the device, so the record on screen and the day sent agree.
@Suite("Age date entry")
struct DateEntryTests {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func resolve(_ birthday: Date, years: Int, months: Int) -> Date? {
        WhenEntry(mode: .age, ageYears: years, ageMonths: months).resolvedDate(birthday: birthday)
    }

    @Test("Whole years count from the birthday")
    func wholeYears() {
        #expect(resolve(date(2020, 6, 15), years: 3, months: 0) == date(2023, 6, 15))
    }

    @Test("Years and months combine")
    func yearsAndMonths() {
        #expect(resolve(date(2020, 6, 15), years: 1, months: 2) == date(2021, 8, 15))
    }

    @Test("Zero age is the birthday itself")
    func zeroAge() {
        let birthday = date(2020, 2, 29)
        #expect(resolve(birthday, years: 0, months: 0) == birthday)
    }

    @Test("A month step off Jan 31 stays in February")
    func clampsShortMonths() {
        #expect(resolve(date(2021, 1, 31), years: 0, months: 1) == date(2021, 2, 28))
    }
}
