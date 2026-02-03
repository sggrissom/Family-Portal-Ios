import XCTest
@testable import Family_Portal_Ios

final class AgeCalculatorTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }()

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testAgeUnderOneMonth() {
        let birthdate = makeDate(year: 2024, month: 1, day: 1)
        let referenceDate = makeDate(year: 2024, month: 1, day: 15)

        XCTAssertEqual(AgeCalculator.age(from: birthdate, at: referenceDate), "< 1 month")
    }

    func testAgeOneMonth() {
        let birthdate = makeDate(year: 2024, month: 1, day: 1)
        let referenceDate = calendar.date(byAdding: .month, value: 1, to: birthdate)!

        XCTAssertEqual(AgeCalculator.age(from: birthdate, at: referenceDate), "1 month")
    }

    func testAgeMultipleMonths() {
        let birthdate = makeDate(year: 2024, month: 1, day: 1)
        let referenceDate = calendar.date(byAdding: .month, value: 4, to: birthdate)!

        XCTAssertEqual(AgeCalculator.age(from: birthdate, at: referenceDate), "4 months")
    }

    func testAgeOneYear() {
        let birthdate = makeDate(year: 2020, month: 6, day: 1)
        let referenceDate = calendar.date(byAdding: .year, value: 1, to: birthdate)!

        XCTAssertEqual(AgeCalculator.age(from: birthdate, at: referenceDate), "1 year")
    }

    func testAgeMultipleYears() {
        let birthdate = makeDate(year: 2018, month: 6, day: 1)
        let referenceDate = calendar.date(byAdding: .year, value: 5, to: birthdate)!

        XCTAssertEqual(AgeCalculator.age(from: birthdate, at: referenceDate), "5 years")
    }
}
