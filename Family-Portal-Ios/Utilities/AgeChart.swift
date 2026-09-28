import Foundation

/// A measurement plotted by age — a port of frontend/lib/ageChart.ts. Everything is drawn in inches and pounds, as on the web, whatever unit a record was entered in.
struct ChartPoint: Identifiable, Equatable {
    let id: UUID
    let ageMonths: Double
    let value: Double
}

/// One row of the percentile band in display units.
struct BandRow: Equatable {
    let ageMonths: Double
    let p3: Double
    let p15: Double
    let p50: Double
    let p85: Double
    let p97: Double
}

struct AgeRange: Equatable {
    var from: Double
    var to: Double
}

struct ChartDomain: Equatable {
    let minAge: Double
    let maxAge: Double
    let minValue: Double
    let maxValue: Double
    let band: [BandRow]
    let zoomed: Bool
}

enum AgeChart {

    static let minZoomMonths = 1.0
    private static let cmPerInch = 2.54
    private static let kgPerPound = 0.453592

    static func displayUnit(_ type: MeasurementType) -> String {
        type == .height ? "in" : "lb"
    }

    /// Inches and pounds — `toDisplay`.
    static func toDisplay(_ value: Double, unit: MeasurementUnit) -> Double {
        switch unit {
        case .centimeters: return value / cmPerInch
        case .kilograms: return value / kgPerPound
        case .inches, .pounds: return value
        }
    }

    /// One type's records by age, oldest first — `chartPoints`.
    static func chartPoints(_ records: [GrowthData], birthday: Date, type: MeasurementType) -> [ChartPoint] {
        records
            .filter { $0.measurementType == type }
            .map { record in
                ChartPoint(
                    id: record.id,
                    ageMonths: max(0, Double(AgeSteps.monthsOld(birthday: birthday, at: record.date)) + fractionOfMonth(birthday: birthday, date: record.date)),
                    value: toDisplay(record.value, unit: record.unit)
                )
            }
            .sorted { $0.ageMonths < $1.ageMonths }
    }

    private static func fractionOfMonth(birthday: Date, date: Date) -> Double {
        let born = birthday.calendarDay().day ?? 1
        let day = date.calendarDay().day ?? 1
        let diff = day >= born ? day - born : day + 30 - born
        return min(Double(diff) / 30.4375, 0.99)
    }

    /// The reference band between two ages, in display units — `percentileBand`. Monthly, or quarterly over spans past four years; nothing past twenty.
    static func percentileBand(gender: Gender, type: MeasurementType, from: Double, to: Double) -> [BandRow] {
        let start = Int(max(0, from.rounded(.down)))
        let end = Int(min(240, to.rounded(.up)))
        guard start <= end else { return [] }
        let step = end - start > 48 ? 3 : 1
        let convert = type == .height ? 1 / cmPerInch : 1 / kgPerPound
        return stride(from: start, through: end, by: step).compactMap { month in
            guard let row = GrowthPercentiles.percentileRow(ageMonths: Double(month), gender: gender, type: type) else { return nil }
            return BandRow(
                ageMonths: Double(month),
                p3: row.p3 * convert,
                p15: row.p15 * convert,
                p50: row.p50 * convert,
                p85: row.p85 * convert,
                p97: row.p97 * convert
            )
        }
    }

    /// Round tick values — `niceTicks`.
    static func niceTicks(min: Double, max: Double, target: Double = 5) -> [Double] {
        guard min.isFinite, max.isFinite else { return [] }
        if min == max { return [min] }
        let rough = (max - min) / target
        let magnitude = pow(10, (log10(rough)).rounded(.down))
        let norm = rough / magnitude
        let step = (norm >= 7.5 ? 10 : norm >= 3.5 ? 5 : norm >= 1.5 ? 2 : 1) * magnitude
        var ticks: [Double] = []
        var value = (min / step).rounded(.up) * step
        while value <= max + 1e-9 {
            ticks.append((value * 1e6).rounded() / 1e6)
            value += step
        }
        return ticks
    }

    /// Age ticks, labelled in months for babies and years after — `ageTicks`.
    static func ageTicks(minMonths: Double, maxMonths: Double) -> [(months: Double, label: String)] {
        let span = maxMonths - minMonths
        let step: Double = span <= 8 ? 1 : span <= 24 ? 3 : span <= 72 ? 12 : span <= 144 ? 24 : 60
        var ticks: [(Double, String)] = []
        var month = (minMonths / step).rounded(.up) * step
        while month <= maxMonths {
            ticks.append((month, step >= 12 ? "\(Int((month / 12).rounded()))y" : ageLabel(Int(month))))
            month += step
        }
        return ticks
    }

    private static func ageLabel(_ months: Int) -> String {
        if months < 24 { return "\(months)m" }
        let rest = months % 12
        return rest == 0 ? "\(months / 12)y" : "\(months / 12)y \(rest)m"
    }

    /// The axes for these series, fitted to the zoom when there is one — `chartDomain`. Values refit to the zoomed ages, including where lines cross its edges.
    static func chartDomain(series: [[ChartPoint]], band: [BandRow], zoom: AgeRange?) -> ChartDomain? {
        let points = series.flatMap { $0 }
        guard let youngest = points.map(\.ageMonths).min(), let oldest = points.map(\.ageMonths).max() else { return nil }

        var minAge = max(0, youngest - 1)
        var maxAge = max(oldest, minAge + 6) + 1
        let range = zoom.flatMap { clampRange($0, min: minAge, max: maxAge) }
        if let range {
            minAge = range.from
            maxAge = range.to
        }

        var values = series.flatMap { visibleValues($0, from: minAge, to: maxAge) }
        let inRange = bandWithin(band, from: minAge, to: maxAge)
        values += inRange
            .filter { $0.ageMonths >= minAge && $0.ageMonths <= maxAge }
            .flatMap { [$0.p3, $0.p97] }
        guard let low = values.min(), let high = values.max() else { return nil }

        let pad = max((high - low) * 0.06, 0.5)
        return ChartDomain(
            minAge: minAge,
            maxAge: maxAge,
            minValue: max(0, low - pad),
            maxValue: high + pad,
            band: inRange,
            zoomed: range != nil
        )
    }

    /// Ordered and clamped to the data, widened to at least a month; nil when it covers everything — `clampRange`.
    static func clampRange(_ range: AgeRange, min lower: Double, max upper: Double) -> AgeRange? {
        var from = max(lower, min(range.from, range.to))
        var to = min(upper, max(range.from, range.to))
        if to - from < minZoomMonths {
            let mid = (from + to) / 2
            from = max(lower, mid - minZoomMonths / 2)
            to = min(upper, from + minZoomMonths)
            from = max(lower, to - minZoomMonths)
        }
        if to <= from || (from == lower && to == upper) { return nil }
        return AgeRange(from: from, to: to)
    }

    private static func visibleValues(_ points: [ChartPoint], from: Double, to: Double) -> [Double] {
        var values = points.filter { $0.ageMonths >= from && $0.ageMonths <= to }.map(\.value)
        for edge in [from, to] {
            if let after = points.firstIndex(where: { $0.ageMonths > edge }), after > 0 {
                let a = points[after - 1]
                let b = points[after]
                values.append(a.value + ((edge - a.ageMonths) / (b.ageMonths - a.ageMonths)) * (b.value - a.value))
            }
        }
        return values
    }

    private static func bandWithin(_ band: [BandRow], from: Double, to: Double) -> [BandRow] {
        guard let start = band.firstIndex(where: { $0.ageMonths >= from }) else { return [] }
        let first = max(0, start - 1)
        let past = band.firstIndex(where: { $0.ageMonths > to })
        let end = past.map { $0 + 1 } ?? band.count
        return Array(band[first..<min(end, band.count)])
    }
}
