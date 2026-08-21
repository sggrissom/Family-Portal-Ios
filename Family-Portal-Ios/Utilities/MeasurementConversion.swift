import Foundation

/// Converting between the units a measurement can be *saved* in.
///
/// Records keep whatever unit they were entered in — that is the honest record of
/// what somebody wrote down, and every list shows it that way. A **chart** cannot:
/// one family measuring in inches and another in centimetres puts 20 and 51 on the
/// same axis and draws a growth spurt that never happened. So anything that plots
/// or ranks converts first, and only the display layer keeps the saved unit.
enum MeasurementConversion {

    // Exact by definition (1 in = 2.54 cm) and the international avoirdupois pound
    // (1 lb = 0.45359237 kg). The web rounds the pound to 0.453592; the extra
    // digits change no displayed figure but stop a round trip from drifting.
    private static let centimetersPerInch = 2.54
    private static let kilogramsPerPound = 0.45359237

    /// The unit the WHO/CDC tables are published in for a given measurement.
    static func metricUnit(for type: MeasurementType) -> MeasurementUnit {
        switch type {
        case .height: return .centimeters
        case .weight: return .kilograms
        }
    }

    /// Convert to cm or kg — the common ground for comparison and for percentile
    /// lookup, never for display.
    static func toMetric(_ value: Double, from unit: MeasurementUnit) -> Double {
        switch unit {
        case .inches: return value * centimetersPerInch
        case .pounds: return value * kilogramsPerPound
        case .centimeters, .kilograms: return value
        }
    }

    /// Convert a metric value back out to a display unit.
    static func fromMetric(_ value: Double, to unit: MeasurementUnit) -> Double {
        switch unit {
        case .inches: return value / centimetersPerInch
        case .pounds: return value / kilogramsPerPound
        case .centimeters, .kilograms: return value
        }
    }

    /// Convert between any two units. A height unit and a weight unit have no
    /// meaningful conversion, so a mismatched pair returns the value untouched
    /// rather than a number that looks plausible — callers only ever pair units
    /// from the same `MeasurementType.validUnits`.
    static func convert(_ value: Double, from source: MeasurementUnit, to target: MeasurementUnit) -> Double {
        guard source != target else { return value }
        guard measurementType(of: source) == measurementType(of: target) else { return value }
        return fromMetric(toMetric(value, from: source), to: target)
    }

    static func measurementType(of unit: MeasurementUnit) -> MeasurementType {
        switch unit {
        case .inches, .centimeters: return .height
        case .pounds, .kilograms: return .weight
        }
    }

    /// The unit a chart should open in: the one the most recent record used, since
    /// that is what the family is currently measuring in, falling back to the
    /// type's default when there is nothing to go on.
    static func preferredUnit(for records: [GrowthData], type: MeasurementType) -> MeasurementUnit {
        let candidates = records
            .filter { $0.measurementType == type }
            .sorted { $0.date > $1.date }
        return candidates.first?.unit ?? type.defaultUnit
    }

    /// One measurement reduced to a common unit: what a chart plots.
    struct Normalized: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let value: Double
    }

    /// Every record of one type, oldest first, converted to `unit`.
    ///
    /// This is the whole of the fix for a chart drawn from mixed units, and it
    /// lives here rather than in the view so it can be tested: a series with
    /// some heights in inches and some in centimetres is not a labelling
    /// problem, it is a line that climbs from 34 to 86 and draws a growth spurt
    /// that never happened.
    static func normalized(
        _ records: [GrowthData],
        type: MeasurementType,
        to unit: MeasurementUnit
    ) -> [Normalized] {
        records
            .filter { $0.measurementType == type }
            .sorted { $0.date < $1.date }
            .map { record in
                Normalized(
                    id: record.id,
                    date: record.date,
                    value: convert(record.value, from: record.unit, to: unit)
                )
            }
    }

    /// Short form for an axis label or a chip.
    static func abbreviation(_ unit: MeasurementUnit) -> String {
        unitToString(unit)
    }

    /// A measurement as text: whole numbers keep no decimal, everything else gets
    /// one. Matches how `PersonDetailView` has always formatted them.
    static func format(_ value: Double, unit: MeasurementUnit) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
        return "\(text) \(abbreviation(unit))"
    }
}
