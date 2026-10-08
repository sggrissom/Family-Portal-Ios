import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/sameAge.test.ts.
@Suite("Age steps")
struct AgeStepsTests {

    @Test("A month at a time under two")
    func monthly() {
        #expect(AgeSteps.ageStep(10) == 1)
        #expect(AgeSteps.nextAge(10, maxMonths: 200) == 11)
        #expect(AgeSteps.prevAge(10) == 9)
    }

    @Test("Three months from two to six, and six after")
    func coarser() {
        #expect(AgeSteps.nextAge(23, maxMonths: 200) == 24)
        #expect(AgeSteps.nextAge(24, maxMonths: 200) == 27)
        #expect(AgeSteps.nextAge(70, maxMonths: 200) == 72)
        #expect(AgeSteps.nextAge(72, maxMonths: 200) == 78)
        #expect(AgeSteps.prevAge(78) == 72)
        #expect(AgeSteps.prevAge(72) == 69)
        #expect(AgeSteps.prevAge(24) == 23)
    }

    @Test("An off-grid age snaps onto the grid")
    func snaps() {
        #expect(AgeSteps.nextAge(41, maxMonths: 200) == 42)
        #expect(AgeSteps.prevAge(41) == 39)
    }

    @Test("Stepping stops at zero and at the oldest age anyone has reached")
    func bounds() {
        #expect(AgeSteps.prevAge(0) == 0)
        #expect(AgeSteps.nextAge(78, maxMonths: 80) == 80)
    }

    @Test("The age in a link reads as months, years, or both")
    func parsesAgeParam() {
        #expect(AgeSteps.parseAgeParam("40m") == 40)
        #expect(AgeSteps.parseAgeParam("3y4m") == 40)
        #expect(AgeSteps.parseAgeParam("3y") == 36)
        #expect(AgeSteps.parseAgeParam("40") == 40)
        #expect(AgeSteps.parseAgeParam("0m") == 0)
        #expect(AgeSteps.parseAgeParam("soon") == nil)
        #expect(AgeSteps.parseAgeParam(nil) == nil)
    }

    @Test("The link is written with months and the person")
    func writesPath() {
        #expect(AgeSteps.sameAgePath(ageMonths: 40, fromPersonId: 7) == "/same-age?age=40m&from=7")
        #expect(AgeSteps.sameAgePath(ageMonths: 0, fromPersonId: 7) == "/same-age?age=0m&from=7")
        #expect(AgeSteps.sameAgePath(ageMonths: nil, fromPersonId: 0) == "/same-age")
    }

    @Test("Details is written into the link; Portraits, the default, is not")
    func writesView() {
        #expect(AgeSteps.sameAgePath(ageMonths: 0, fromPersonId: 7, view: .details) == "/same-age?age=0m&from=7&view=details")
        #expect(AgeSteps.sameAgePath(ageMonths: 0, fromPersonId: 7, view: .portraits) == "/same-age?age=0m&from=7")
    }

    @Test("Younger and Older find the nearest age with records, and nothing past either end")
    func nearbyAge() {
        let ages = [0, 3, 12, 48]
        #expect(AgeSteps.nearbyAge(in: ages, from: 12, direction: -1) == 3)
        #expect(AgeSteps.nearbyAge(in: ages, from: 12, direction: 1) == 48)
        // An explicitly chosen empty age still steps to its neighbours.
        #expect(AgeSteps.nearbyAge(in: ages, from: 20, direction: -1) == 12)
        #expect(AgeSteps.nearbyAge(in: ages, from: 20, direction: 1) == 48)
        #expect(AgeSteps.nearbyAge(in: ages, from: 0, direction: -1) == nil)
        #expect(AgeSteps.nearbyAge(in: ages, from: 48, direction: 1) == nil)
        #expect(AgeSteps.nearbyAge(in: [], from: 6, direction: 1) == nil)
    }

    @Test("The heading names newborns as newborns")
    func heading() {
        #expect(AgeSteps.ageHeading(0) == "Everyone as newborns")
        #expect(AgeSteps.ageHeading(36) == "Everyone at 3 years")
    }

    @Test("The age is spelled out")
    func titles() {
        #expect(AgeSteps.ageTitle(40) == "3 years 4 months")
        #expect(AgeSteps.ageTitle(13) == "1 year 1 month")
        #expect(AgeSteps.ageTitle(8) == "8 months")
        #expect(AgeSteps.ageTitle(24) == "2 years")
        #expect(AgeSteps.ageTitle(0) == "Newborn")
    }

    @Test("Whole months are counted between two server dates")
    func monthsOld() {
        let iso = ISO8601DateFormatter()
        let born = iso.date(from: "2020-06-15T00:00:00Z")!
        #expect(AgeSteps.monthsOld(birthday: born, at: iso.date(from: "2024-01-15T00:00:00Z")!) == 43)
        #expect(AgeSteps.monthsOld(birthday: born, at: iso.date(from: "2024-01-14T00:00:00Z")!) == 42)
    }

    @Test("A birthday picked east of UTC is stored as its own day")
    func localBirthday() {
        let sydney = TimeZone(identifier: "Australia/Sydney")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sydney
        let born = calendar.date(from: DateComponents(year: 2020, month: 6, day: 15))!
        let then = ISO8601DateFormatter().date(from: "2024-01-15T00:00:00Z")!

        #expect(AgeSteps.monthsOld(birthday: born.localRecordDay(in: sydney), at: then) == 43)
    }

    // MARK: - Photo age

    private func photoAge(_ at: String) -> String {
        let iso = ISO8601DateFormatter()
        return AgeSteps.photoAge(birthday: iso.date(from: "2014-03-02T00:00:00Z")!, at: iso.date(from: at)!)
    }

    @Test("A photo's age counts days past the month under two")
    func photoAgeDays() {
        #expect(photoAge("2014-09-10T15:30:00Z") == "6 months, 8 days")
        #expect(photoAge("2014-09-02T08:00:00Z") == "6 months")
        #expect(photoAge("2014-03-03T00:00:00Z") == "1 day")
        #expect(photoAge("2014-03-02T00:00:00Z") == "Newborn")
        #expect(photoAge("2015-04-01T00:00:00Z") == "1 year, 30 days")
    }

    @Test("A photo's age drops the days from two on")
    func photoAgeYears() {
        #expect(photoAge("2019-05-20T00:00:00Z") == "5 years 2 months")
    }

    @Test("A photo before the birthday has no age")
    func photoAgeBeforeBirth() {
        #expect(photoAge("2014-01-01T00:00:00Z") == "")
    }

    @Test("A 31st birthday rolls into the next month the way the web's does")
    func photoAgeMonthEnd() {
        let iso = ISO8601DateFormatter()
        let born = iso.date(from: "2020-01-31T00:00:00Z")!
        // Jan 31 + 1 month is Mar 2 in 2020, so Mar 5 is 3 days past it.
        #expect(AgeSteps.photoAge(birthday: born, at: iso.date(from: "2020-03-05T00:00:00Z")!) == "1 month, 3 days")
    }
}
