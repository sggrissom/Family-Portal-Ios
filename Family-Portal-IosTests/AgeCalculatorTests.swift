import Foundation
import Testing
@testable import Family_Portal_Ios

/// `AgeCalculator` is a port of `calculateAgeAt` and `calculateGestationalAgeAt`
/// in `backend/person.go`, not an independent implementation. The server sends
/// its own rendering as `PersonDTO.age` and the app throws it away — a stored
/// string goes stale the moment a birthday passes, and a person created offline
/// has none at all — which is only the right trade while the two agree.
///
/// Every case below is the server's answer for the same pair of dates, worked
/// through its arithmetic by hand.
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

    static func age(
        bornOn birth: (Int, Int, Int),
        on reference: (Int, Int, Int),
        isPregnancy: Bool = false
    ) -> String {
        AgeCalculator.age(
            from: local(birth.0, birth.1, birth.2),
            at: local(reference.0, reference.1, reference.2),
            isPregnancy: isPregnancy
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

    // MARK: - Where the app and the website used to disagree

    /// The reason this stopped using `Calendar.dateComponents`.
    ///
    /// Foundation resolves "31 March plus one month" by clamping to 30 April and
    /// calls that a whole month. The server compares the day numbers, finds 30
    /// less than 31, and calls it none. So a child born on the 31st read as
    /// "1 month" on the phone and "< 1 month" on the website — on one day of
    /// every month, for every month-end birthday.
    @Test("A month-end birthday is not a full month until the day number comes round")
    func monthEndBirthdayMatchesTheServer() {
        #expect(Self.age(bornOn: (2026, 3, 31), on: (2026, 4, 30)) == "< 1 month")
        #expect(Self.age(bornOn: (2026, 3, 31), on: (2026, 5, 1)) == "1 month")
    }

    /// Same clamping, a year up: 29 February plus one year is 28 February, which
    /// Foundation calls a whole year and the server does not.
    @Test("A leap-day birthday is not a year old on 28 February")
    func leapDayEveMatchesTheServer() {
        #expect(Self.age(bornOn: (2024, 2, 29), on: (2025, 2, 28)) == "11 months")
    }

    /// A due date is gestational age in weeks, counting back from a 40-week
    /// term. The old implementation ran the ordinary path on a negative interval
    /// and produced "< 1 month" while the website said "38 weeks".
    @Test("A due date in the future reads as weeks of pregnancy")
    func futureDueDateReadsAsWeeks() {
        // 14 days out: 40 - ceil(14/7) = 38.
        #expect(Self.age(bornOn: (2026, 3, 29), on: (2026, 3, 15)) == "38 weeks")
        // A week out.
        #expect(Self.age(bornOn: (2026, 3, 22), on: (2026, 3, 15)) == "39 weeks")
        // The due date itself.
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2026, 3, 15), isPregnancy: true) == "40 weeks")
    }

    @Test("Thirty-nine weeks out is week one, and singular")
    func oneWeekIsSingular() {
        // 273 days is 39 weeks: 40 - 39 = 1.
        #expect(Self.age(bornOn: (2026, 12, 13), on: (2026, 3, 15)) == "1 week")
    }

    /// The case the flag exists for. Once the due date has passed, the date
    /// alone no longer says this is a pregnancy — and an overdue baby is 41
    /// weeks, not a day old.
    @Test("An overdue pregnancy keeps counting in weeks")
    func overduePregnancyKeepsCountingWeeks() {
        #expect(Self.age(bornOn: (2026, 3, 15), on: (2026, 3, 22), isPregnancy: true) == "41 weeks")
    }

    /// A very early pregnancy would count past 40 weeks in the other direction;
    /// the server floors it at zero and so does this.
    @Test("A due date further out than a full term floors at zero")
    func veryEarlyPregnancyFloorsAtZero() {
        #expect(Self.age(bornOn: (2027, 3, 15), on: (2026, 3, 15)) == "0 weeks")
    }
}
