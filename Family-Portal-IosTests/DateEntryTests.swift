import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Date entry")
struct DateEntryTests {

    static func local(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    // MARK: - Age resolution

    /// Must match `personBirthday.AddDate(years, months, 0)` in
    /// backend/growth.go — calendar arithmetic, not 365/30-day approximations.
    @Test("14 months resolves to the same day-of-month, 14 months on")
    func fourteenMonths() throws {
        let birthday = Self.local(2024, 3, 15)
        let resolved = try #require(
            DateEntryField.dateFromAge(birthday: birthday, years: 1, months: 2)
        )
        #expect(Calendar.current.isDate(resolved, inSameDayAs: Self.local(2025, 5, 15)))
    }

    @Test("Whole years land on the birthday")
    func wholeYears() throws {
        let birthday = Self.local(2019, 8, 4)
        let resolved = try #require(
            DateEntryField.dateFromAge(birthday: birthday, years: 6, months: 0)
        )
        #expect(Calendar.current.isDate(resolved, inSameDayAs: Self.local(2025, 8, 4)))
    }

    @Test("Month arithmetic rolls the year over")
    func monthsRollOver() throws {
        let birthday = Self.local(2024, 11, 20)
        let resolved = try #require(
            DateEntryField.dateFromAge(birthday: birthday, years: 0, months: 3)
        )
        #expect(Calendar.current.isDate(resolved, inSameDayAs: Self.local(2025, 2, 20)))
    }

    @Test("A day-of-month that doesn't exist in the target month clamps")
    func clampsShortMonths() throws {
        // Jan 31 + 1 month has no Feb 31; Calendar clamps to Feb 28/29, and so
        // does Go's AddDate normalization landing in early March. This asserts
        // the Swift side is at least stable and inside February.
        let birthday = Self.local(2025, 1, 31)
        let resolved = try #require(
            DateEntryField.dateFromAge(birthday: birthday, years: 0, months: 1)
        )
        let month = Calendar.current.component(.month, from: resolved)
        #expect(month == 2)
    }

    @Test("Age resolution needs a birthday")
    func noBirthdayNoAge() {
        #expect(DateEntryField.dateFromAge(birthday: nil, years: 1, months: 0) == nil)
    }

    // MARK: - Wire resolution

    @Test("Explicit date entry sends inputType date and no age")
    func resolvesExplicitDate() {
        let date = Self.local(2026, 3, 15)
        let result = DateEntryField.resolve(
            mode: .date, date: date, ageYears: 0, ageMonths: 0, birthday: nil
        )

        #expect(result.inputType == "date")
        #expect(result.date == date)
        #expect(result.ageYears == nil)
        #expect(result.ageMonths == nil)
    }

    /// "Today" is resolved on the device and sent as an explicit date. The
    /// backend resolves inputType "today" with time.Now() at *sync* time, so a
    /// queue that sat offline for three days would otherwise record the wrong day.
    @Test("Today is pinned at save time, not sync time")
    func resolvesTodayToExplicitDate() {
        let result = DateEntryField.resolve(
            mode: .today, date: Self.local(2020, 1, 1), ageYears: 0, ageMonths: 0, birthday: nil
        )

        #expect(result.inputType == "date")
        #expect(result.inputType != "today")
        #expect(abs(result.date.timeIntervalSinceNow) < 5)
    }

    @Test("Age entry sends the age and the resolved date together")
    func resolvesAge() {
        let birthday = Self.local(2024, 3, 15)
        let result = DateEntryField.resolve(
            mode: .age, date: Self.local(2020, 1, 1), ageYears: 1, ageMonths: 2, birthday: birthday
        )

        #expect(result.inputType == "age")
        #expect(result.ageYears == 1)
        #expect(result.ageMonths == 2)
        #expect(Calendar.current.isDate(result.date, inSameDayAs: Self.local(2025, 5, 15)))
    }

    @Test("Age entry without a birthday falls back to the picked date")
    func ageWithoutBirthdayFallsBack() {
        let date = Self.local(2026, 3, 15)
        let result = DateEntryField.resolve(
            mode: .age, date: date, ageYears: 1, ageMonths: 2, birthday: nil
        )

        #expect(result.inputType == "date")
        #expect(result.date == date)
    }

    // MARK: - Request encoding

    @Test("AddGrowthData carries the age fields the backend expects")
    func growthRequestCarriesAge() throws {
        let data = try JSONEncoder().encode(
            AddGrowthDataRequestDTO(
                personId: 12,
                measurementType: "height",
                value: 84.5,
                unit: "cm",
                inputType: "age",
                measurementDate: nil,
                ageYears: 1,
                ageMonths: 2
            )
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["inputType"] as? String == "age")
        #expect(object["ageYears"] as? Int == 1)
        #expect(object["ageMonths"] as? Int == 2)
    }

    @Test("AddMilestone carries the age fields the backend expects")
    func milestoneRequestCarriesAge() throws {
        let data = try JSONEncoder().encode(
            AddMilestoneRequestDTO(
                personId: 12,
                description: "First steps",
                category: "physical",
                inputType: "age",
                milestoneDate: nil,
                ageYears: 1,
                ageMonths: 0
            )
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["inputType"] as? String == "age")
        #expect(object["ageYears"] as? Int == 1)
    }

    // MARK: - Queue payload compatibility

    /// Operations queued before age entry existed have no inputType key, and
    /// must still decode and sync as plain dates.
    @Test("Pre-existing queued payloads still decode")
    func legacyPayloadDecodes() throws {
        let json = """
        {
          "personLocalId": "abc",
          "measurementType": "height",
          "value": 84.5,
          "unit": "cm",
          "measurementDate": "2026-03-15"
        }
        """
        let payload = try JSONDecoder().decode(CreateGrowthDataPayload.self, from: Data(json.utf8))

        #expect(payload.inputType == nil)
        #expect(payload.ageYears == nil)
        #expect(payload.measurementDate == "2026-03-15")
    }
}
