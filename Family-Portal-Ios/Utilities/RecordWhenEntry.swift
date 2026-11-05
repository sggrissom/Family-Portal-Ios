import Foundation

/// Every way a moment or photo can be dated once the server takes approximate dates — a port of `frontend/lib/recordWhen.ts`, so both clients offer the same choices, check them the same way and build the same `RecordTime`.
enum RecordWhenMode: String, CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case date
    case month
    case year
    case range
    case age
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return Copy.when.today
        case .yesterday: return Copy.when.yesterday
        case .date: return Copy.when.pickDate
        case .month: return Copy.recordWhen.month
        case .year: return Copy.recordWhen.year
        case .range: return Copy.recordWhen.range
        case .age: return Copy.when.byAge
        case .unknown: return Copy.recordWhen.unknown
        }
    }

    /// Today, Yesterday and a picked day: the only modes that name one exact day.
    var isDay: Bool { self == .today || self == .yesterday || self == .date }
}

struct RecordWhenEntry: Equatable, Sendable {
    var mode: RecordWhenMode = .today
    var date: Date?
    /// 1–12, with `monthYear`, for "A month…".
    var month = Calendar.current.component(.month, from: Date())
    var monthYear: Int?
    var year: Int?
    /// `YYYY`, `YYYY-MM` or `YYYY-MM-DD`, as typed.
    var rangeFrom = ""
    var rangeTo = ""
    var ageYears = 0
    /// `nil` is a whole year of age; a number, even 0, is that month of it.
    var ageMonths: Int?
    /// Set for an age range: "ages 6–9".
    var ageToYears: Int?
    /// "occurrence", "period", or empty until a moment's family has said which.
    var meaning = ""
    var estimated = false
    /// The best guess inside an estimated range, in the range's own terms: "1970", or "8" for an age.
    var around = ""
    /// The server id of whose age it is.
    var anchorPersonId = 0

    init() {}

    /// The editor's starting point for a record that already has a date.
    init(recordTime: RecordTime?, date: Date) {
        guard let rt = recordTime, !rt.isExactDay else {
            mode = .date
            self.date = date.displayDay()
            return
        }
        estimated = rt.estimated
        around = rt.around
        meaning = rt.meaning
        anchorPersonId = rt.anchorPersonId
        switch rt.basis {
        case "unknown":
            mode = .unknown
        case "age":
            mode = .age
            ageYears = rt.ageYears
            if rt.precision == "month" { ageMonths = rt.ageMonths }
            if rt.precision == "range" { ageToYears = rt.ageToYears }
        default:
            switch rt.precision {
            case "day":
                mode = .date
                self.date = Civil.parse(rt.from).flatMap { DaySummaries.date(of: $0.start.key) }?.displayDay()
            case "month":
                mode = .month
                if let parsed = Civil.parse(rt.from)?.start {
                    month = parsed.month
                    monthYear = parsed.year
                }
            case "year":
                mode = .year
                year = Int(rt.from)
            default:
                mode = .range
                rangeFrom = rt.from
                rangeTo = rt.to
            }
        }
    }

    /// Which of the shared rows the current mode shows — `recordWhenControls`. What's hidden is neither checked nor sent, so a choice left behind by another mode can't leak into this one.
    struct Controls: Equatable, Sendable {
        /// Happened then / describes that time.
        var meaning: Bool
        var estimate: Bool
        /// The best guess, inside an estimated range of dates or ages.
        var bestGuess: Bool
    }

    var controls: Controls {
        let editable = mode != .today && mode != .yesterday && mode != .unknown
        return Controls(
            meaning: editable,
            estimate: editable,
            bestGuess: mode == .range || (mode == .age && ageToYears != nil)
        )
    }

    /// Switches mode the way `setRecordWhenMode` does: a best guess never carries over, since a central age and a central date aren't interchangeable, and choices the new mode hides are cleared.
    mutating func setMode(_ newMode: RecordWhenMode) {
        guard mode != newMode else { return }
        mode = newMode
        around = ""
        if !controls.meaning { meaning = "" }
        if !controls.estimate { estimated = false }
    }

    /// Anything beyond one exact day — `isApproximateMode`.
    var isApproximate: Bool {
        !mode.isDay || (controls.estimate && estimated) || (controls.meaning && meaning == "period")
    }

    /// The assertion to store and send. Its range is filled for the device's own sorting; the server recomputes it.
    func recordTime(now: Date = Date(), isMoment: Bool, birthday: Date? = nil, calendar: Calendar = .current) -> RecordTime {
        var rt = RecordTime()
        let controls = controls
        rt.meaning = isMoment && controls.meaning && meaning == "period" ? "period" : "occurrence"
        rt.estimated = controls.estimate && estimated
        rt.around = rt.estimated && controls.bestGuess ? around.trimmingCharacters(in: .whitespaces) : ""
        switch mode {
        case .today:
            rt.from = WhenEntry.localDateString(now, calendar: calendar)
        case .yesterday:
            rt.from = WhenEntry.localDateString(calendar.date(byAdding: .day, value: -1, to: now) ?? now, calendar: calendar)
        case .date:
            rt.from = date.map { WhenEntry.localDateString($0, calendar: calendar) } ?? ""
        case .month:
            rt.precision = "month"
            rt.from = String(format: "%04d-%02d", monthYear ?? 0, month)
        case .year:
            rt.precision = "year"
            rt.from = year.map { String(format: "%04d", $0) } ?? ""
        case .range:
            rt.precision = "range"
            rt.from = rangeFrom.trimmingCharacters(in: .whitespaces)
            rt.to = rangeTo.trimmingCharacters(in: .whitespaces)
        case .age:
            rt.basis = "age"
            rt.precision = ageToYears != nil ? "range" : ageMonths != nil ? "month" : "year"
            rt.anchorPersonId = anchorPersonId
            rt.ageYears = ageYears
            rt.ageMonths = ageToYears == nil ? (ageMonths ?? 0) : 0
            rt.ageToYears = ageToYears ?? 0
        case .unknown:
            rt.meaning = "occurrence"
            rt.basis = "unknown"
            rt.precision = "unknown"
        }
        let range = rt.range(birthday: birthday?.recordDayKey)
        rt.start = range.start
        rt.end = range.end
        rt.resolved = range.resolved
        return rt
    }

    /// Where the record sorts on this device until the server answers: the start of its range, or the zero date for an undated one.
    static func sortDate(_ rt: RecordTime) -> Date {
        DaySummaries.date(of: rt.resolved ? rt.start : "0001-01-01") ?? Date(timeIntervalSince1970: 0)
    }

    /// Why it can't be saved yet, or `nil` — `recordWhenProblem`, wording included.
    func problem(isMoment: Bool, birthday: Date?, now: Date = Date()) -> String? {
        switch mode {
        case .date:
            if date == nil { return "Pick a date" }
        case .month:
            if (monthYear ?? 0) < 1 { return "Pick a month" }
        case .year:
            if (year ?? 0) < 1 { return "Enter a year, like 1970" }
        case .range:
            guard let from = Civil.parse(rangeFrom.trimmingCharacters(in: .whitespaces)),
                  let to = Civil.parse(rangeTo.trimmingCharacters(in: .whitespaces)) else {
                return "Enter both ends, like 1968 and 1972"
            }
            if to.end.key < from.end.key { return "The range ends before it starts" }
        case .age:
            if let months = ageMonths, !(0...11).contains(months) { return "Months should be 0 to 11" }
            if let to = ageToYears, to < ageYears { return "The age range ends before it starts" }
            if anchorPersonId == 0 { return "Choose whose age this is" }
            if isMoment && meaning.isEmpty { return "Choose whether it happened then or describes that age" }
        case .today, .yesterday, .unknown:
            break
        }
        let rt = recordTime(now: now, isMoment: isMoment, birthday: birthday)
        if !rt.around.isEmpty {
            let ok = mode == .age ? Int(rt.around).map { $0 >= 0 } ?? false : Civil.parse(rt.around) != nil
            if !ok { return mode == .age ? "The best guess should be an age in years" : "Check the best guess" }
        }
        guard mode != .unknown else { return nil }
        if rt.resolved, rt.start > WhenEntry.localDateString(now) {
            return mode == .age ? "That age hasn't happened yet" : "That date hasn't happened yet"
        }
        return nil
    }

    /// "At age 4 · Based on birthday: Jun 15, 2024 – Jun 14, 2025", for under the control.
    func preview(isMoment: Bool, birthday: Date?, now: Date = Date()) -> (label: String, bounds: String)? {
        guard isApproximate else { return nil }
        var check = self
        check.meaning = "occurrence"
        check.anchorPersonId = max(anchorPersonId, 1)
        guard check.problem(isMoment: false, birthday: nil, now: now) == nil else { return nil }
        let rt = recordTime(now: now, isMoment: isMoment, birthday: birthday)
        guard rt.resolved, let start = DaySummaries.date(of: rt.start), let end = DaySummaries.date(of: rt.end) else {
            return (rt.label, "")
        }
        let last = end.addingTimeInterval(-86_400)
        let format: (Date) -> String = { $0.displayDay().formatted(date: .abbreviated, time: .omitted) }
        let span = rt.start == last.recordDayKey ? format(start) : "\(format(start)) – \(format(last))"
        return (rt.label, rt.basis == "age" ? "Based on birthday: \(span)" : "Matches \(span)")
    }
}
