import Foundation

/// The age grid the Same age page steps along — a port of `frontend/lib/sameAge.ts`, matching `sameAgeStep` in backend/same_age.go: a month at a time under two, a season until six, half a year after that.
/// Only the stepping and the wording live here. Which records count as "at this age" is the server's (`GetSameAge`), and the app never re-derives it.
nonisolated enum AgeSteps {

    static func ageStep(_ ageMonths: Int) -> Int {
        if ageMonths < 24 { return 1 }
        if ageMonths < 72 { return 3 }
        return 6
    }

    static func onAgeGrid(_ ageMonths: Int) -> Bool {
        ageMonths % ageStep(ageMonths) == 0
    }

    /// One step older, snapped onto the grid, and never past the oldest age anyone has reached.
    static func nextAge(_ ageMonths: Int, maxMonths: Int) -> Int {
        var age = ageMonths + 1
        while !onAgeGrid(age) { age += 1 }
        return min(age, max(maxMonths, ageMonths))
    }

    /// One step younger, snapped onto the grid, stopping at birth.
    static func prevAge(_ ageMonths: Int) -> Int {
        var age = ageMonths - 1
        while age > 0 && !onAgeGrid(age) { age -= 1 }
        return max(age, 0)
    }

    /// Reads `40m`, `3y4m`, `3y` or a bare `40` (months). Anything else is nil.
    static func parseAgeParam(_ value: String?) -> Int? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        var years: Int?
        var months: Int?
        var rest = Substring(value)

        if let y = rest.firstIndex(of: "y") {
            guard let parsed = Int(rest[rest.startIndex..<y]), rest[rest.startIndex..<y].allSatisfy(\.isNumber) else { return nil }
            years = parsed
            rest = rest[rest.index(after: y)...]
        }
        if !rest.isEmpty {
            let digits = rest.hasSuffix("m") ? rest.dropLast() : rest
            guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let parsed = Int(digits) else { return nil }
            months = parsed
        }
        guard years != nil || months != nil else { return nil }
        return (years ?? 0) * 12 + (months ?? 0)
    }

    /// The same-age link's path, as `sameAgePath` writes it.
    static func sameAgePath(ageMonths: Int?, fromPersonId: Int) -> String {
        var items: [String] = []
        if let ageMonths, ageMonths >= 0 { items.append("age=\(ageMonths)m") }
        if fromPersonId > 0 { items.append("from=\(fromPersonId)") }
        return items.isEmpty ? "/same-age" : "/same-age?" + items.joined(separator: "&")
    }

    /// "3 years 4 months", "8 months", "Newborn".
    static func ageTitle(_ ageMonths: Int) -> String {
        if ageMonths <= 0 { return "Newborn" }
        let years = ageMonths / 12
        let months = ageMonths % 12
        let y = years == 1 ? "1 year" : "\(years) years"
        let m = months == 1 ? "1 month" : "\(months) months"
        if years == 0 { return m }
        return months == 0 ? y : "\(y) \(m)"
    }

    /// Whole months from `birthday` to `at`, as `monthsOld` counts them, over the days two record dates name.
    static func monthsOld(birthday: Date, at date: Date) -> Int {
        let born = birthday.recordDay
        let then = date.recordDay
        var months = ((then.year ?? 0) - (born.year ?? 0)) * 12 + (then.month ?? 0) - (born.month ?? 0)
        if (then.day ?? 0) < (born.day ?? 0) { months -= 1 }
        return months
    }

    /// How old someone actually was in a photo — "6 months, 8 days" — to the day under two, as `photoAge` words it. Empty for a photo before the birthday.
    static func photoAge(birthday: Date, at date: Date) -> String {
        let months = monthsOld(birthday: birthday, at: date)
        if months < 0 { return "" }
        if months >= 24 { return ageTitle(months) }

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let born = birthday.recordDay
        // The month's first day plus the birthday's day, so a 31st rolls into the next month the way `Date.UTC` does.
        let monthIndex = (born.month ?? 1) - 1 + months
        guard let monthStart = utc.date(from: DateComponents(year: (born.year ?? 0) + monthIndex / 12, month: monthIndex % 12 + 1, day: 1)),
              let anchor = utc.date(byAdding: .day, value: (born.day ?? 1) - 1, to: monthStart),
              let then = utc.date(from: date.recordDay),
              let days = utc.dateComponents([.day], from: anchor, to: then).day
        else { return ageTitle(months) }

        if days <= 0 { return ageTitle(months) }
        let d = days == 1 ? "1 day" : "\(days) days"
        return months == 0 ? d : "\(ageTitle(months)), \(d)"
    }
}
