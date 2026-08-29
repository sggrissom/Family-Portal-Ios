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

    @Test("Formats as a UTC calendar day")
    func dateToAPIStringUsesUTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 12
        let noon = calendar.date(from: components)!

        #expect(dateToAPIString(noon) == "2026-03-15")
    }

    @Test("Late-evening US times don't roll back a day")
    func dateToAPIStringNearMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 15
        components.hour = 23
        components.minute = 30
        let lateEvening = calendar.date(from: components)!

        #expect(dateToAPIString(lateEvening) == "2026-03-15")
    }

    @Test("Formats a single-digit month and day with leading zeros")
    func dateToAPIStringPadsComponents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        let date = calendar.date(from: components)!

        #expect(dateToAPIString(date) == "2026-01-05")
    }
}
