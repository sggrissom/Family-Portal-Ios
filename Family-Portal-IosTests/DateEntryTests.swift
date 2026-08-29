import Foundation
import SwiftUI
import Testing
@testable import Family_Portal_Ios

@Suite("Age date entry")
struct DateEntryTests {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Whole years count from the birthday")
    @MainActor
    func wholeYears() {
        let birthday = date(2020, 6, 15)
        let resolved = DateEntryPicker.date(from: birthday, years: 3, months: 0)

        #expect(resolved == date(2023, 6, 15))
    }

    @Test("Years and months combine")
    @MainActor
    func yearsAndMonths() {
        let birthday = date(2020, 6, 15)

        #expect(DateEntryPicker.date(from: birthday, years: 1, months: 2) == date(2021, 8, 15))
        // "at 14 months" — the case the plan calls out as awkward on a phone.
        #expect(DateEntryPicker.date(from: birthday, years: 0, months: 14) == date(2021, 8, 15))
    }

    @Test("Zero age is the birthday itself")
    @MainActor
    func zeroAge() {
        let birthday = date(2020, 2, 29)

        #expect(DateEntryPicker.date(from: birthday, years: 0, months: 0) == birthday)
    }

    @Test("A month step off Jan 31 stays in February")
    @MainActor
    func clampsShortMonths() {
        let resolved = DateEntryPicker.date(from: date(2021, 1, 31), years: 0, months: 1)

        #expect(resolved == date(2021, 2, 28))
    }
}
