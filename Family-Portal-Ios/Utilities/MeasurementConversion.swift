import Foundation

/// Converting between the units a measurement can be saved in. Records keep the unit they were entered in; anything that plots or ranks converts first.
enum MeasurementConversion {

    // Exact by definition (1 in = 2.54 cm) and the international avoirdupois pound. The web rounds to 0.453592; the extra digits stop a round trip from drifting.
    private static let centimetersPerInch = 2.54
    private static let kilogramsPerPound = 0.45359237

    /// The unit the WHO/CDC tables are published in for a given measurement.
    static func metricUnit(for type: MeasurementType) -> MeasurementUnit {
        switch type {
        case .height: return .centimeters
        case .weight: return .kilograms
        }
    }

    static func toMetric(_ value: Double, from unit: MeasurementUnit) -> Double {
        switch unit {
        case .inches: return value * centimetersPerInch
        case .pounds: return value * kilogramsPerPound
        case .centimeters, .kilograms: return value
        }
    }

    static func fromMetric(_ value: Double, to unit: MeasurementUnit) -> Double {
        switch unit {
        case .inches: return value / centimetersPerInch
        case .pounds: return value / kilogramsPerPound
        case .centimeters, .kilograms: return value
        }
    }

    /// A height unit and a weight unit have no meaningful conversion, so a mismatched pair returns the value untouched.
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

    static func preferredUnit(for records: [GrowthData], type: MeasurementType) -> MeasurementUnit {
        let candidates = records
            .filter { $0.measurementType == type }
            .sorted { $0.date > $1.date }
        return candidates.first?.unit ?? type.defaultUnit
    }

    struct Normalized: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let value: Double
    }

    /// Every record of one type, oldest first, converted to `unit` — the fix for a chart drawn from mixed units.
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

    static func abbreviation(_ unit: MeasurementUnit) -> String {
        unitToString(unit)
    }

    static func format(_ value: Double, unit: MeasurementUnit) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
        return "\(text) \(abbreviation(unit))"
    }
}
