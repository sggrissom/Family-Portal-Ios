import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Measurement conversion")
struct MeasurementConversionTests {

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func record(
        _ value: Double,
        _ unit: MeasurementUnit,
        _ type: MeasurementType = .height,
        on day: Date
    ) -> GrowthData {
        GrowthData(measurementType: type, value: value, unit: unit, date: day)
    }

    // MARK: - The arithmetic

    @Test("An inch is exactly 2.54 centimetres, both ways")
    func inchesAndCentimetres() {
        #expect(MeasurementConversion.convert(10, from: .inches, to: .centimeters) == 25.4)
        #expect(abs(MeasurementConversion.convert(25.4, from: .centimeters, to: .inches) - 10) < 1e-9)
    }

    @Test("A pound is the international avoirdupois pound, both ways")
    func poundsAndKilograms() {
        #expect(abs(MeasurementConversion.convert(10, from: .pounds, to: .kilograms) - 4.5359237) < 1e-9)
        #expect(abs(MeasurementConversion.convert(4.5359237, from: .kilograms, to: .pounds) - 10) < 1e-9)
    }

    @Test("A round trip does not drift")
    func roundTripIsStable() {
        let original = 37.75
        let there = MeasurementConversion.convert(original, from: .inches, to: .centimeters)
        let back = MeasurementConversion.convert(there, from: .centimeters, to: .inches)
        #expect(abs(back - original) < 1e-9)
    }

    @Test("Mismatched units are left alone")
    func mismatchedUnitsAreNotConverted() {
        #expect(MeasurementConversion.convert(10, from: .inches, to: .kilograms) == 10)
    }

    // MARK: - Choosing the unit

    @Test("A chart opens in whatever the family measured in most recently")
    func preferredUnitFollowsTheLatestRecord() {
        let records = [
            Self.record(34, .inches, on: Self.date(2024, 1, 1)),
            Self.record(90, .centimeters, on: Self.date(2025, 6, 1)),
            Self.record(36, .inches, on: Self.date(2024, 8, 1)),
        ]

        #expect(MeasurementConversion.preferredUnit(for: records, type: .height) == .centimeters)
    }

    @Test("With nothing recorded, the type's default is used")
    func preferredUnitFallsBackToTheDefault() {
        #expect(MeasurementConversion.preferredUnit(for: [], type: .height) == .inches)
        #expect(MeasurementConversion.preferredUnit(for: [], type: .weight) == .pounds)
    }

    @Test("The other measurement type does not decide the unit")
    func preferredUnitIgnoresTheOtherType() {
        let records = [
            Self.record(34, .inches, .height, on: Self.date(2024, 1, 1)),
            Self.record(15, .kilograms, .weight, on: Self.date(2025, 6, 1)),
        ]

        #expect(MeasurementConversion.preferredUnit(for: records, type: .height) == .inches)
    }

    // MARK: - The series a chart plots

    @Test("A mixed-unit series is plotted in one unit")
    func mixedUnitsAreNormalized() {
        let records = [
            Self.record(34, .inches, on: Self.date(2024, 1, 1)),
            Self.record(86.36, .centimeters, on: Self.date(2024, 6, 1)),
            Self.record(36, .inches, on: Self.date(2025, 1, 1)),
        ]

        let series = MeasurementConversion.normalized(records, type: .height, to: .inches)

        #expect(series.count == 3)
        #expect(abs(series[0].value - 34) < 1e-9)
        // 86.36 cm is exactly 34 inches.
        #expect(abs(series[1].value - 34) < 1e-9)
        #expect(abs(series[2].value - 36) < 1e-9)
        // Monotone, which is what the child actually did.
        #expect(series[0].value <= series[1].value)
        #expect(series[1].value <= series[2].value)
    }

    @Test("A series is oldest first, whatever order it arrives in")
    func seriesIsChronological() {
        let records = [
            Self.record(36, .inches, on: Self.date(2025, 1, 1)),
            Self.record(34, .inches, on: Self.date(2024, 1, 1)),
        ]

        let series = MeasurementConversion.normalized(records, type: .height, to: .inches)

        #expect(series.map(\.value) == [34, 36])
    }

    @Test("A series holds one measurement type")
    func seriesExcludesTheOtherType() {
        let records = [
            Self.record(34, .inches, .height, on: Self.date(2024, 1, 1)),
            Self.record(30, .pounds, .weight, on: Self.date(2024, 2, 1)),
        ]

        let series = MeasurementConversion.normalized(records, type: .height, to: .inches)

        #expect(series.count == 1)
        #expect(series[0].value == 34)
    }

    // MARK: - Formatting

    @Test("Whole numbers keep no decimal; everything else gets one")
    func formatting() {
        #expect(MeasurementConversion.format(34, unit: .inches) == "34 in")
        #expect(MeasurementConversion.format(34.25, unit: .inches) == "34.3 in")
        #expect(MeasurementConversion.format(86.36, unit: .centimeters) == "86.4 cm")
    }
}
