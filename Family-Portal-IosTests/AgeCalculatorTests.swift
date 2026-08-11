import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("AgeCalculator boundaries")
struct AgeCalculatorTests {

    /// `AgeCalculator` uses `Calendar.current`, so build both dates the same way.
    static func local(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    static func age(bornOn birth: (Int, Int, Int), on reference: (Int, Int, Int)) -> String {
        AgeCalculator.age(
            from: local(birth.0, birth.1, birth.2),
            at: local(reference.0, reference.1, reference.2)
        )
    }

    @Test("The day of birth reads as under a month")
    func dayOfBirth() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2026, 3, 15)) == "< 1 month")
    }

    @Test("The day before the first month-iversary is still under a month")
    func dayBeforeOneMonth() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2026, 4, 14)) == "< 1 month")
    }

    @Test("One month exactly is singular")
    func exactlyOneMonth() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2026, 4, 15)) == "1 month")
    }

    @Test("Two months is plural")
    func twoMonths() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2026, 5, 15)) == "2 months")
    }

    @Test("Eleven months has not yet become a year")
    func elevenMonths() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2027, 2, 15)) == "11 months")
    }

    @Test("The day before the first birthday is still months")
    func dayBeforeFirstBirthday() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2027, 3, 14)) == "11 months")
    }

    @Test("The first birthday is singular")
    func firstBirthday() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2027, 3, 15)) == "1 year")
    }

    @Test("Eighteen months still reads as one year")
    func eighteenMonths() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2027, 9, 15)) == "1 year")
    }

    @Test("The second birthday is plural")
    func secondBirthday() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2028, 3, 15)) == "2 years")
    }

    @Test("A Feb 29 birthday reads as a year old on Feb 28 of a common year")
    func leapDayBirthday() {
        // 2024 is a leap year; 2025 is not.
        #expect(Self.age(bornOn: (2024, 2, 29), on: (2025, 3, 1)) == "1 year")
    }

    @Test("A birthdate in the future reads as under a month rather than negative")
    func futureBirthdate() {
        #expect(Self.age(bornOn: (2027, 3, 15), on: (2026, 3, 15)) == "< 1 month")
    }
}
