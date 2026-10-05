import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Sync mappers")
struct SyncMappersTests {

    // MARK: - Enum round-trips

    @Test("StatedRelation codes match the backend's iota order")
    func statedRelationCodes() {
        #expect(StatedRelation.none.rawValue == 0)
        #expect(StatedRelation.child.rawValue == 1)
        #expect(StatedRelation.parent.rawValue == 2)
        #expect(StatedRelation.sibling.rawValue == 3)
        #expect(StatedRelation.partner.rawValue == 4)
    }

    @Test("Every relation wording names a real edge kind")
    func relationOptionsAreStated() {
        #expect(RelationOption.all.count == 12)
        #expect(RelationOption.all.allSatisfy { $0.stated != .none })
        // A gendered word states the gender too, so the form can stop asking twice.
        #expect(RelationOption.all.first { $0.label == "daughter" }?.gender == .female)
        #expect(RelationOption.all.first { $0.label == "father" }?.gender == .male)
        #expect(RelationOption.all.first { $0.label == "sibling" }?.gender == nil)
    }

    @Test("Gender survives a round-trip", arguments: [Gender.male, .female, .other])
    func genderRoundTrip(gender: Gender) {
        #expect(intToGender(genderToInt(gender)) == gender)
    }

    @Test("Gender codes match the backend")
    func genderCodes() {
        #expect(genderToInt(.male) == 0)
        #expect(genderToInt(.female) == 1)
        #expect(genderToInt(.other) == 2)
    }

    @Test("MeasurementUnit survives a round-trip",
          arguments: [MeasurementUnit.centimeters, .inches, .kilograms, .pounds])
    func unitRoundTrip(unit: MeasurementUnit) {
        #expect(unitFromString(unitToString(unit)) == unit)
    }

    @Test("MeasurementUnit strings match the backend")
    func unitStrings() {
        #expect(unitToString(.centimeters) == "cm")
        #expect(unitToString(.inches) == "in")
        #expect(unitToString(.kilograms) == "kg")
        #expect(unitToString(.pounds) == "lbs")
    }

    @Test("MeasurementType codes match the backend")
    func measurementTypeCodes() {
        #expect(intToMeasurementType(0) == .height)
        #expect(intToMeasurementType(1) == .weight)
        #expect(measurementTypeToString(.height) == "height")
        #expect(measurementTypeToString(.weight) == "weight")
    }

    @Test("Unknown codes fall back instead of trapping")
    func unknownCodesFallBack() {
        #expect(intToGender(99) == .other)
        #expect(intToMeasurementType(99) == .height)
        #expect(unitFromString("furlongs") == .inches)
    }

    // MARK: - dateToAPIString

    private static let chicago = TimeZone(identifier: "America/Chicago")!
    private static let sydney = TimeZone(identifier: "Australia/Sydney")!

    private static func instant(_ zone: TimeZone, _ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("A record date is sent as its own day")
    func recordDatesKeepTheirUTCDay() {
        #expect(dateToAPIString(Self.instant(.gmt, 2026, 3, 15)) == "2026-03-15")
    }

    @Test("An evening entry in the US is stored and sent as that evening's day, not the UTC one")
    func eveningEntriesUseTheLocalDay() {
        // 21:30 in Chicago is already the 16th in UTC.
        let evening = Self.instant(Self.chicago, 2026, 3, 15, hour: 21, minute: 30)

        #expect(dateToAPIString(evening.localRecordDay(in: Self.chicago)) == "2026-03-15")
    }

    @Test("A local midnight east of UTC is not stored as the day before")
    func localMidnightEastOfUTC() {
        let midnight = Self.instant(Self.sydney, 2026, 3, 15)

        #expect(dateToAPIString(midnight.localRecordDay(in: Self.sydney)) == "2026-03-15")
    }

    @Test("Formats a single-digit month and day with leading zeros")
    func dateToAPIStringPadsComponents() {
        #expect(dateToAPIString(Self.instant(.gmt, 2026, 1, 5)) == "2026-01-05")
    }
}
