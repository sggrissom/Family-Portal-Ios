import Foundation

/// How a height is typed in. `ft-in` is two fields that save as inches.
enum CheckupHeightUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case inches = "in"
    case feetInches = "ft-in"
    case centimeters = "cm"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inches: return "in"
        case .feetInches: return "ft/in"
        case .centimeters: return "cm"
        }
    }

    /// The unit a height typed this way is saved in.
    var savedUnit: MeasurementUnit {
        self == .centimeters ? .centimeters : .inches
    }
}

/// How a weight is typed in. `lb-oz` is two fields that save as pounds. Kilograms are the one addition over the web, which only offers pounds; the app has always accepted them.
enum CheckupWeightUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case pounds = "lb"
    case poundsOunces = "lb-oz"
    case kilograms = "kg"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pounds: return "lb"
        case .poundsOunces: return "lb/oz"
        case .kilograms: return "kg"
        }
    }

    var savedUnit: MeasurementUnit {
        self == .kilograms ? .kilograms : .pounds
    }
}

/// The two fields of one checkup, as typed. Either half may be blank.
struct CheckupEntry: Equatable, Sendable {
    var heightUnit: CheckupHeightUnit = .inches
    var height = ""
    var feet = ""
    var inches = ""
    var weightUnit: CheckupWeightUnit = .pounds
    var weight = ""
    var pounds = ""
    var ounces = ""

    /// Clears the values and keeps the units — what "Add another measurement" starts from.
    func cleared() -> CheckupEntry {
        CheckupEntry(heightUnit: heightUnit, weightUnit: weightUnit)
    }
}

/// One record a checkup saves.
struct CheckupMeasurement: Equatable, Sendable {
    let type: MeasurementType
    let value: Double
    let unit: MeasurementUnit
}

/// Units remembered per person, then for the family as a whole. Keyed by the person's **local** id, the way `QuickAddDefaults` remembers the person: a local id is what every sheet has in hand, including for somebody still uploading.
struct UnitPrefs: Codable, Equatable, Sendable {
    var height: [String: CheckupHeightUnit] = [:]
    var weight: [String: CheckupWeightUnit] = [:]
    var lastHeight: CheckupHeightUnit?
    var lastWeight: CheckupWeightUnit?
}

/// A height and a weight taken together — a port of `frontend/lib/checkup.ts`, so a checkup validates, converts and remembers units the same way on both clients.
enum Checkup {

    // MARK: - Validation

    /// The records to save, or the first reason there are none. Mirrors `checkupMeasurements`, error wording included.
    static func measurements(_ entry: CheckupEntry) -> (measurements: [CheckupMeasurement], error: String?) {
        var measurements: [CheckupMeasurement] = []

        if entry.heightUnit == .feetInches {
            if !blank(entry.feet, entry.inches) {
                let feet = number(entry.feet)
                let inches = number(entry.inches)
                let total = feet * 12 + inches
                guard feet >= 0, inches >= 0, total > 0 else {
                    return ([], "Enter a height in feet and inches")
                }
                measurements.append(CheckupMeasurement(type: .height, value: total, unit: .inches))
            }
        } else if !blank(entry.height) {
            let value = number(entry.height)
            guard value > 0 else { return ([], "Enter a height above zero") }
            measurements.append(CheckupMeasurement(type: .height, value: value, unit: entry.heightUnit.savedUnit))
        }

        if entry.weightUnit == .poundsOunces {
            if !blank(entry.pounds, entry.ounces) {
                let pounds = number(entry.pounds)
                let ounces = number(entry.ounces)
                guard pounds >= 0, ounces >= 0, ounces < MeasurementConversion.ouncesPerPound, pounds + ounces > 0 else {
                    return ([], "Enter a weight in pounds and ounces under 16")
                }
                measurements.append(CheckupMeasurement(
                    type: .weight,
                    value: MeasurementConversion.pounds(pounds, ounces: ounces),
                    unit: .pounds
                ))
            }
        } else if !blank(entry.weight) {
            let value = number(entry.weight)
            guard value > 0 else { return ([], "Enter a weight above zero") }
            measurements.append(CheckupMeasurement(type: .weight, value: value, unit: entry.weightUnit.savedUnit))
        }

        if measurements.isEmpty {
            return ([], "Enter a height, a weight, or both")
        }
        return (measurements, nil)
    }

    private static func blank(_ values: String...) -> Bool {
        values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Blank is zero, anything unparseable is NaN — which fails every comparison, the way `Number("abc")` does on the web.
    private static func number(_ value: String) -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        return Double(trimmed) ?? .nan
    }

    // MARK: - Units

    static func latest(of records: [GrowthData], type: MeasurementType) -> GrowthData? {
        records
            .filter { $0.measurementType == type }
            .max { $0.date < $1.date }
    }

    /// The person's own choice, then the unit of their last height, then the family's last choice.
    static func defaultHeightUnit(_ prefs: UnitPrefs, personKey: String, personGrowth: [GrowthData]) -> CheckupHeightUnit {
        if let stored = prefs.height[personKey] { return stored }
        if let last = latest(of: personGrowth, type: .height) {
            return last.unit == .centimeters ? .centimeters : .inches
        }
        return prefs.lastHeight ?? .inches
    }

    /// The person's own choice, then pounds and ounces for a baby, then the family's last choice.
    static func defaultWeightUnit(_ prefs: UnitPrefs, personKey: String, ageMonths: Int?) -> CheckupWeightUnit {
        if let stored = prefs.weight[personKey] { return stored }
        if let ageMonths, MeasurementConversion.prefersPoundsAndOunces(0, unit: .pounds, ageMonths: Double(ageMonths)) {
            return .poundsOunces
        }
        return prefs.lastWeight ?? .pounds
    }

    /// Remembers only the units that were actually used: a checkup that only weighed somebody says nothing about how the family measures height.
    static func remember(_ prefs: UnitPrefs, personKey: String, measurements: [CheckupMeasurement], entry: CheckupEntry) -> UnitPrefs {
        var next = prefs
        if measurements.contains(where: { $0.type == .height }) {
            next.height[personKey] = entry.heightUnit
            next.lastHeight = entry.heightUnit
        }
        if measurements.contains(where: { $0.type == .weight }) {
            next.weight[personKey] = entry.weightUnit
            next.lastWeight = entry.weightUnit
        }
        return next
    }

    // MARK: - Helper text

    /// "today", "7 days ago", "5 weeks ago", "3 years ago" — `timeAgo`.
    static func timeAgo(_ date: Date, now: Date) -> String {
        let days = Int((now.timeIntervalSince(date) / 86_400).rounded(.down))
        if days < 1 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 14 { return "\(days) days ago" }
        if days < 60 { return "\(days / 7) weeks ago" }
        let months = Int((Double(days) / 30.4375).rounded(.down))
        if months < 24 { return "\(months) months ago" }
        return "\(months / 12) years ago"
    }

    /// "last: 3 ft 1.75 in, 4 months ago", or empty with nothing to show.
    static func describeLast(_ last: GrowthData?, ageMonthsThen: Double?, now: Date) -> String {
        guard let last else { return "" }
        let value = MeasurementConversion.formatLikeWeb(last.value, unit: last.unit, ageMonths: ageMonthsThen)
        return "last: \(value), \(timeAgo(last.date, now: now))"
    }
}
