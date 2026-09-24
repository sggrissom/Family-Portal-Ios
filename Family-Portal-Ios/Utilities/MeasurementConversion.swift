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

    /// Pounds read as pounds and ounces while `ageMonths` is under two years; with no age to go on, while the weight is under 25 lb. Same rule as the web's `formatMeasurement`.
    static func format(_ value: Double, unit: MeasurementUnit, ageMonths: Double? = nil) -> String {
        if prefersPoundsAndOunces(value, unit: unit, ageMonths: ageMonths) {
            return formatPoundsAndOunces(value)
        }
        return "\(oneDecimal(value)) \(abbreviation(unit))"
    }

    static func format(_ record: GrowthData) -> String {
        format(record.value, unit: record.unit, ageMonths: ageMonths(of: record))
    }

    static func ageMonths(of record: GrowthData) -> Double? {
        guard let birthday = record.person?.birthday, record.person?.isPregnancy != true else { return nil }
        let months = GrowthPercentiles.ageInMonths(birthday: birthday, on: record.date)
        return months >= 0 ? months : nil
    }

    // MARK: - Pounds and ounces

    static let ouncesPerPound = 16.0
    private static let poundsAndOuncesMaxAgeMonths = 24.0
    private static let poundsAndOuncesMaxPounds = 25.0

    static func prefersPoundsAndOunces(_ value: Double, unit: MeasurementUnit, ageMonths: Double? = nil) -> Bool {
        guard unit == .pounds else { return false }
        if let ageMonths, ageMonths >= 0 {
            return ageMonths < poundsAndOuncesMaxAgeMonths
        }
        return value < poundsAndOuncesMaxPounds
    }

    /// Ounces to one decimal, carried into the pounds when they round up to a full pound.
    static func splitPoundsAndOunces(_ value: Double) -> (pounds: Int, ounces: Double) {
        var pounds = Int(value.rounded(.down))
        var ounces = ((value - Double(pounds)) * ouncesPerPound * 10).rounded() / 10
        if ounces >= ouncesPerPound {
            pounds += 1
            ounces -= ouncesPerPound
        }
        return (pounds, ounces)
    }

    static func pounds(_ pounds: Double, ounces: Double) -> Double {
        pounds + ounces / ouncesPerPound
    }

    /// Either field may be left blank, but not both; ounces stop short of a full pound.
    static func parsePoundsAndOunces(pounds: String, ounces: String) -> Double? {
        let poundsText = pounds.trimmingCharacters(in: .whitespaces)
        let ouncesText = ounces.trimmingCharacters(in: .whitespaces)
        guard !(poundsText.isEmpty && ouncesText.isEmpty) else { return nil }
        guard let whole = poundsText.isEmpty ? 0 : Double(poundsText),
              let part = ouncesText.isEmpty ? 0 : Double(ouncesText),
              whole >= 0, part >= 0, part < ouncesPerPound else {
            return nil
        }
        let total = self.pounds(whole, ounces: part)
        return total > 0 ? total : nil
    }

    /// Whether a new weight for `person` should start out in pounds and ounces.
    static func entersPoundsAndOunces(for person: Person?, on date: Date) -> Bool {
        guard let person, let birthday = person.birthday, !person.isPregnancy else { return false }
        let months = GrowthPercentiles.ageInMonths(birthday: birthday, on: date)
        return months >= 0 && months < poundsAndOuncesMaxAgeMonths
    }

    static func formatPoundsAndOunces(_ value: Double) -> String {
        let (pounds, ounces) = splitPoundsAndOunces(value)
        if pounds == 0 { return "\(oneDecimal(ounces)) oz" }
        if ounces == 0 { return "\(pounds) lb" }
        return "\(pounds) lb \(oneDecimal(ounces)) oz"
    }

    static func oneDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
    }
}
