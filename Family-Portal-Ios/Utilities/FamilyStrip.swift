import Foundation

/// The family strip's short ages — a port of frontend/lib/familyStrip.ts.
enum FamilyStrip {

    /// "3d", "3w", "8m", "3y 4m", "41y"; blank for a date that has not come yet.
    static func compactAge(birthday: Date, today: Date, timeZone: TimeZone = .current) -> String {
        guard let days = days(from: birthday, to: today, timeZone: timeZone), days >= 0 else { return "" }
        let months = AgeSteps.monthsOld(birthday: birthday, at: today, timeZone: timeZone)
        if months < 1 { return days < 7 ? "\(days)d" : "\(days / 7)w" }
        if months < 24 { return "\(months)m" }
        let years = months / 12
        let rest = months % 12
        if years >= 18 || rest == 0 { return "\(years)y" }
        return "\(years)y \(rest)m"
    }

    /// "Due in 5w 2d", "Due today", "Due date passed 1 day ago".
    static func dueSummary(dueDate: Date, today: Date, timeZone: TimeZone = .current) -> String {
        guard let days = days(from: today, to: dueDate, timeZone: timeZone) else { return "" }
        if days < 0 { return "Due date passed \(-days) day\(days == -1 ? "" : "s") ago" }
        if days == 0 { return "Due today" }
        let weeks = days / 7
        if weeks > 0 { return days % 7 == 0 ? "Due in \(weeks)w" : "Due in \(weeks)w \(days % 7)d" }
        return "Due in \(days) day\(days == 1 ? "" : "s")"
    }

    /// Whole calendar days between the days two dates name.
    private static func days(from start: Date, to end: Date, timeZone: TimeZone) -> Int? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        guard let a = utc.date(from: start.calendarDay(in: timeZone)),
              let b = utc.date(from: end.calendarDay(in: timeZone)) else { return nil }
        return utc.dateComponents([.day], from: a, to: b).day
    }
}

/// Which Home nudges this device has dismissed, by the server's stable key. Capped at the newest 100, as on the web, and per device: a nudge dismissed here comes back on the web.
struct NudgeDismissals {
    private static let key = "com.familyrecord.home.dismissedNudges"
    static let cap = 100

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var keys: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    func dismiss(_ nudgeKey: String) {
        var next = keys.filter { $0 != nudgeKey }
        next.append(nudgeKey)
        defaults.set(Array(next.suffix(Self.cap)), forKey: Self.key)
    }

    /// At most two of the server's nudges, minus the dismissed ones, in the server's order.
    func visible(_ nudges: [DashboardNudgeDTO], limit: Int = 2) -> [DashboardNudgeDTO] {
        let dismissed = Set(keys)
        return Array(nudges.filter { !dismissed.contains($0.key) }.prefix(limit))
    }
}
