import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/checkup.test.ts.
@MainActor
@Suite("Checkup")
struct CheckupTests {

    private static func growth(_ type: MeasurementType, _ value: Double, _ unit: MeasurementUnit, _ iso: String) -> GrowthData {
        GrowthData(measurementType: type, value: value, unit: unit, date: ISO8601DateFormatter().date(from: iso)!)
    }

    // MARK: - Measurements

    @Test("At least one of height and weight is needed")
    func needsOne() {
        #expect(Checkup.measurements(CheckupEntry()).error == "Enter a height, a weight, or both")
    }

    @Test("Both are saved from one entry")
    func savesBoth() {
        let result = Checkup.measurements(CheckupEntry(height: "38.5", weight: "32"))
        #expect(result.error == nil)
        #expect(result.measurements == [
            CheckupMeasurement(type: .height, value: 38.5, unit: .inches),
            CheckupMeasurement(type: .weight, value: 32, unit: .pounds),
        ])
    }

    @Test("Feet and inches, and pounds and ounces, convert")
    func converts() {
        var entry = CheckupEntry()
        entry.heightUnit = .feetInches
        entry.feet = "3"
        entry.inches = "2.5"
        entry.weightUnit = .poundsOunces
        entry.pounds = "7"
        entry.ounces = "8"

        #expect(Checkup.measurements(entry).measurements == [
            CheckupMeasurement(type: .height, value: 38.5, unit: .inches),
            CheckupMeasurement(type: .weight, value: 7.5, unit: .pounds),
        ])
    }

    @Test("Centimetres stay centimetres, and kilograms kilograms")
    func metricStaysMetric() {
        var entry = CheckupEntry(heightUnit: .centimeters, height: "98")
        #expect(Checkup.measurements(entry).measurements == [CheckupMeasurement(type: .height, value: 98, unit: .centimeters)])

        entry = CheckupEntry(weightUnit: .kilograms, weight: "14.2")
        #expect(Checkup.measurements(entry).measurements == [CheckupMeasurement(type: .weight, value: 14.2, unit: .kilograms)])
    }

    @Test("Values that are not measurements are refused")
    func rejectsNonsense() {
        #expect(Checkup.measurements(CheckupEntry(height: "abc")).error == "Enter a height above zero")
        #expect(Checkup.measurements(CheckupEntry(weight: "0")).error == "Enter a weight above zero")
        var entry = CheckupEntry()
        entry.weightUnit = .poundsOunces
        entry.pounds = "7"
        entry.ounces = "16"
        #expect(Checkup.measurements(entry).error == "Enter a weight in pounds and ounces under 16")
    }

    @Test("Clearing keeps the units")
    func clearingKeepsUnits() {
        let entry = CheckupEntry(heightUnit: .centimeters, height: "98", weightUnit: .poundsOunces, pounds: "7")
        #expect(entry.cleared() == CheckupEntry(heightUnit: .centimeters, weightUnit: .poundsOunces))
    }

    // MARK: - Units

    @Test("The person's own choice comes first")
    func personFirst() {
        let prefs = UnitPrefs(height: ["a": .feetInches], weight: ["a": .pounds])
        #expect(Checkup.defaultHeightUnit(prefs, personKey: "a", personGrowth: []) == .feetInches)
        #expect(Checkup.defaultWeightUnit(prefs, personKey: "a", ageMonths: 3) == .pounds)
    }

    @Test("Then the unit of their last height")
    func thenLastHeight() {
        let records = [Self.growth(.height, 98, .centimeters, "2026-01-01T00:00:00Z")]
        #expect(Checkup.defaultHeightUnit(UnitPrefs(), personKey: "a", personGrowth: records) == .centimeters)
    }

    @Test("Babies are weighed in pounds and ounces")
    func babies() {
        let prefs = UnitPrefs(lastWeight: .pounds)
        #expect(Checkup.defaultWeightUnit(prefs, personKey: "a", ageMonths: 4) == .poundsOunces)
        #expect(Checkup.defaultWeightUnit(prefs, personKey: "a", ageMonths: 40) == .pounds)
    }

    @Test("Then what the family used last")
    func thenFamily() {
        #expect(Checkup.defaultHeightUnit(UnitPrefs(lastHeight: .centimeters), personKey: "a", personGrowth: []) == .centimeters)
        #expect(Checkup.defaultWeightUnit(UnitPrefs(), personKey: "a", ageMonths: nil) == .pounds)
    }

    @Test("Only the units that were used are remembered")
    func remembersUsedUnits() {
        let next = Checkup.remember(
            UnitPrefs(),
            personKey: "e",
            measurements: [CheckupMeasurement(type: .weight, value: 7.5, unit: .pounds)],
            entry: CheckupEntry(heightUnit: .centimeters, weightUnit: .poundsOunces)
        )
        #expect(next == UnitPrefs(height: [:], weight: ["e": .poundsOunces], lastHeight: nil, lastWeight: .poundsOunces))
    }

    // MARK: - Helper text

    @Test("The latest of the type is described")
    func describesLatest() {
        let now = ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z")!
        let list = [
            Self.growth(.height, 36, .inches, "2026-01-01T00:00:00Z"),
            Self.growth(.height, 37.75, .inches, "2026-05-20T00:00:00Z"),
            Self.growth(.weight, 30, .pounds, "2026-08-01T00:00:00Z"),
        ]
        let latest = Checkup.latest(of: list, type: .height)
        #expect(latest?.value == 37.75)
        #expect(Checkup.describeLast(latest, ageMonthsThen: 38, now: now) == "last: 3 ft 1.75 in, 4 months ago")
        #expect(Checkup.describeLast(nil, ageMonthsThen: nil, now: now) == "")
    }

    @Test("How long ago, in words")
    func timeAgo() {
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-09-27T12:00:00Z")!
        #expect(Checkup.timeAgo(iso.date(from: "2026-09-27T08:00:00Z")!, now: now) == "today")
        #expect(Checkup.timeAgo(iso.date(from: "2026-09-20T08:00:00Z")!, now: now) == "7 days ago")
        #expect(Checkup.timeAgo(iso.date(from: "2026-08-20T08:00:00Z")!, now: now) == "5 weeks ago")
        #expect(Checkup.timeAgo(iso.date(from: "2023-09-20T08:00:00Z")!, now: now) == "3 years ago")
    }
}
