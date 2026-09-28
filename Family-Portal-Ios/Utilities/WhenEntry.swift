import Foundation

/// The four ways a record's date is given — a port of `frontend/lib/when.ts`, so the "Today ▾" control offers the same choices and validates them the same way on both clients.
enum WhenMode: String, CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case date
    case age

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return Copy.when.today
        case .yesterday: return Copy.when.yesterday
        case .date: return Copy.when.pickDate
        case .age: return Copy.when.byAge
        }
    }
}

/// What the user has chosen so far. `date` and the age fields only mean something in their own mode, and are kept while another mode is showing so switching back does not lose them.
struct WhenEntry: Equatable, Sendable {
    var mode: WhenMode = .today
    var date: Date?
    var ageYears: Int?
    var ageMonths: Int?

    /// What `when.ts` sends. The app does not send `"age"` itself — see `resolvedDate` — but the request is ported so the two clients can be compared case by case.
    struct Request: Equatable, Sendable {
        let inputType: String
        let date: String?
        let ageYears: Int?
        let ageMonths: Int?
    }

    /// Why the entry cannot be saved yet, or `nil`. Mirrors `whenProblem`, including its wording.
    var problem: String? {
        switch mode {
        case .today, .yesterday:
            return nil
        case .date:
            return date == nil ? "Pick a date" : nil
        case .age:
            guard let ageYears, ageYears >= 0 else { return "Enter an age in years" }
            let months = ageMonths ?? 0
            return (0...11).contains(months) ? nil : "Months should be 0 to 11"
        }
    }

    /// The label on the menu: the mode's own name for Today and Yesterday, the chosen date or age once there is one.
    var menuLabel: String {
        switch mode {
        case .today: return Copy.when.today
        case .yesterday: return Copy.when.yesterday
        case .date:
            return date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? Copy.when.pickDate
        case .age:
            guard let years = ageYears else { return Copy.when.byAge }
            return AgeSteps.ageTitle((years * 12) + (ageMonths ?? 0))
        }
    }

    /// Mirrors `whenRequest`: Today and Yesterday are the **device's** calendar days, never the server's — its "today" is a UTC day and can be one off for the family.
    func request(now: Date, calendar: Calendar = .current) -> Request {
        switch mode {
        case .today:
            return Request(inputType: "date", date: Self.localDateString(now, calendar: calendar), ageYears: nil, ageMonths: nil)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return Request(inputType: "date", date: Self.localDateString(yesterday, calendar: calendar), ageYears: nil, ageMonths: nil)
        case .date:
            return Request(inputType: "date", date: date.map { Self.localDateString($0, calendar: calendar) }, ageYears: nil, ageMonths: nil)
        case .age:
            return Request(inputType: "age", date: nil, ageYears: ageYears, ageMonths: ageMonths ?? 0)
        }
    }

    /// The day to store and send. An age is resolved here against the birthday rather than sent as `inputType: "age"`: the record has to exist locally before the server answers, and Go's `AddDate` and Foundation's `Calendar` disagree about month overflow, so a server-resolved age could land on a different day from the one already on screen.
    /// `nil` when the entry has a problem, or is an age with no birthday to count from.
    func resolvedDate(birthday: Date?, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard problem == nil else { return nil }
        switch mode {
        case .today:
            return now
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: now)
        case .date:
            return date
        case .age:
            guard let birthday else { return nil }
            return calendar.date(
                byAdding: DateComponents(year: ageYears ?? 0, month: ageMonths ?? 0),
                to: birthday
            )
        }
    }

    /// `localDateString` in when.ts: the calendar day in the device's zone.
    static func localDateString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
