import Foundation

/// What a family asserted about when a moment or photo happened, or which period of life it describes — the port of `RecordTime` in backend/record_time.go and frontend/lib/recordTime.ts.
///
/// `start`/`end` are the server's half-open range of civil days, both empty when the assertion can't be placed on the calendar. The milestone or photo date that comes with it is only a sort key unless `isExactDay`.
nonisolated struct RecordTime: Codable, Equatable, Hashable, Sendable {
    var version = 1
    var meaning = "occurrence"
    var basis = "calendar"
    var precision = "day"
    var estimated = false
    var from = ""
    var to = ""
    var around = ""
    var anchorPersonId = 0
    var ageYears = 0
    var ageMonths = 0
    var ageToYears = 0
    var source = "family"
    var note = ""
    var changedBy = 0
    /// Kept as the server's string: nothing here reads it, and Go writes the zero time for "never".
    var changedAt = "0001-01-01T00:00:00Z"
    var start = ""
    var end = ""
    var resolved = false
    var resolverVersion = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        version = try value(.version, 1)
        meaning = try value(.meaning, "occurrence")
        basis = try value(.basis, "calendar")
        precision = try value(.precision, "day")
        estimated = try value(.estimated, false)
        from = try value(.from, "")
        to = try value(.to, "")
        around = try value(.around, "")
        anchorPersonId = try value(.anchorPersonId, 0)
        ageYears = try value(.ageYears, 0)
        ageMonths = try value(.ageMonths, 0)
        ageToYears = try value(.ageToYears, 0)
        source = try value(.source, "family")
        note = try value(.note, "")
        changedBy = try value(.changedBy, 0)
        changedAt = try value(.changedAt, "0001-01-01T00:00:00Z")
        start = try value(.start, "")
        end = try value(.end, "")
        resolved = try value(.resolved, false)
        resolverVersion = try value(.resolverVersion, 0)
    }

    /// The only kind of record an anniversary can come from: a known occurrence on one calendar day.
    var isExactDay: Bool {
        meaning == "occurrence" && basis == "calendar" && precision == "day" && !estimated
    }

    /// An exact day, as a record created before approximate dates would carry.
    static func exact(day: String) -> RecordTime {
        var rt = RecordTime()
        rt.from = day
        let range = rt.range(birthday: nil)
        rt.start = range.start
        rt.end = range.end
        rt.resolved = range.resolved
        return rt
    }

    // MARK: Resolution

    struct Range: Equatable, Sendable {
        var start: String
        var end: String
        var resolved: Bool

        static let unresolved = Range(start: "", end: "", resolved: false)
    }

    /// The half-open civil range the assertion covers, computed the way the server does. Age steps clamp to the end of a short month and are always taken from the birthday itself.
    func range(birthday: String?) -> Range {
        switch basis {
        case "calendar":
            guard let first = Civil.parse(from) else { return .unresolved }
            let last = precision == "range" ? Civil.parse(to) : first
            guard let last else { return .unresolved }
            return Range(start: first.start.key, end: last.end.key, resolved: true)
        case "age":
            guard let birthday, let born = Civil.parse(String(birthday.prefix(10)))?.start else { return .unresolved }
            let start: Civil, end: Civil
            switch precision {
            case "month":
                let months = ageYears * 12 + ageMonths
                start = born.adding(months: months)
                end = born.adding(months: months + 1)
            case "range":
                start = born.adding(months: ageYears * 12)
                end = born.adding(months: (ageToYears + 1) * 12)
            default:
                start = born.adding(months: ageYears * 12)
                end = born.adding(months: (ageYears + 1) * 12)
            }
            return Range(start: start.key, end: end.key, resolved: true)
        default:
            return .unresolved
        }
    }

    // MARK: Labels

    /// "Oct 31, 2022", "October 2022", "Around 1970 (1968–1972)", "At age 4", "Sometime at age 4", "Date unknown".
    var label: String {
        switch basis {
        case "calendar":
            var base = Self.civilLabel(from)
            if precision == "range" { base = Self.joinRange(base, Self.civilLabel(to)) }
            guard estimated else { return base }
            return around.isEmpty ? "Around \(base)" : "Around \(Self.civilLabel(around)) (\(base))"
        case "age":
            let age: String
            switch precision {
            case "month": age = "age \(Self.plural(ageYears, "year")), \(Self.plural(ageMonths, "month"))"
            case "range": age = "ages \(ageYears)–\(ageToYears)"
            default: age = "age \(ageYears)"
            }
            if estimated { return around.isEmpty ? "Around \(age)" : "Around age \(around) (\(age))" }
            return meaning == "period" ? "At \(age)" : "Sometime at \(age)"
        default:
            return "Date unknown"
        }
    }

    /// The heading a group of these records sits under in History: "Sometime in October 2022" for a broad occurrence, otherwise the label.
    var groupLabel: String {
        guard basis == "calendar", !estimated, meaning != "period" else { return label }
        return precision == "range" ? "Sometime \(label)" : "Sometime in \(label)"
    }

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    private static func civilLabel(_ value: String) -> String {
        guard let parsed = Civil.parse(value) else { return value }
        let d = parsed.start
        switch parsed.precision {
        case "year": return String(d.year)
        case "month": return "\(monthNames[d.month - 1]) \(d.year)"
        default: return "\(monthNames[d.month - 1].prefix(3)) \(d.day), \(d.year)"
        }
    }

    private static func joinRange(_ from: String, _ to: String) -> String {
        from.contains(" ") || to.contains(" ") ? "\(from) – \(to)" : "\(from)–\(to)"
    }

    private static func plural(_ n: Int, _ unit: String) -> String {
        n == 1 ? "1 \(unit)" : "\(n) \(unit)s"
    }
}

/// A calendar day with no time zone.
nonisolated struct Civil: Equatable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func daysIn(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    func adding(months n: Int) -> Civil {
        let total = year * 12 + (month - 1) + n
        let y = total / 12, m = total % 12 + 1
        return Civil(year: y, month: m, day: min(day, Self.daysIn(y, m)))
    }

    func addingDay() -> Civil {
        if day < Self.daysIn(year, month) { return Civil(year: year, month: month, day: day + 1) }
        return month == 12 ? Civil(year: year + 1, month: 1, day: 1) : Civil(year: year, month: month + 1, day: 1)
    }

    /// "YYYY", "YYYY-MM" or "YYYY-MM-DD": the first day it names, the first day after it, and its precision.
    static func parse(_ value: String) -> (start: Civil, end: Civil, precision: String)? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), parts[0].count == 4, parts.dropFirst().allSatisfy({ $0.count == 2 }) else { return nil }
        let nums = parts.compactMap { Int($0) }
        guard nums.count == parts.count, nums[0] >= 1 else { return nil }
        switch nums.count {
        case 1:
            let start = Civil(year: nums[0], month: 1, day: 1)
            return (start, start.adding(months: 12), "year")
        case 2:
            guard (1...12).contains(nums[1]) else { return nil }
            let start = Civil(year: nums[0], month: nums[1], day: 1)
            return (start, start.adding(months: 1), "month")
        default:
            guard (1...12).contains(nums[1]), (1...daysIn(nums[0], nums[1])).contains(nums[2]) else { return nil }
            let start = Civil(year: nums[0], month: nums[1], day: nums[2])
            return (start, start.addingDay(), "day")
        }
    }
}
