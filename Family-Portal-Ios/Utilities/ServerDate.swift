import Foundation

nonisolated extension Date {

    /// Whether this is Go's zero `time.Time` rather than a date anybody meant. The activities dates encode "not known yet" as `"0001-01-01T00:00:00Z"`, which decodes to the year 1.
    /// The cutoff is 1900 rather than an equality check, which would pass until a timezone got involved. Nothing this app records predates it.
    var isServerZero: Bool {
        self < Self.serverZeroCutoff
    }

    var serverDate: Date? {
        isServerZero ? nil : self
    }

    private static let serverZeroCutoff = Date(timeIntervalSince1970: -2_208_988_800)
}

nonisolated enum ServerDateFormat {

    /// `nil` in, `nil` out, and that is meaningful: an absent key on a write **clears** the date rather than leaving it alone.
    static func requestString(_ date: Date?) -> String? {
        guard let date = date?.serverDate else { return nil }

        // Built per call rather than cached: `DateFormatter` is not `Sendable`, and this one has to read the device's *current* time zone, which a competition weekend is exactly when a phone changes.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

nonisolated extension Date {

    /// The calendar day this date *names*, which is not always the day it falls on locally.
    /// A date the server sent is midnight UTC of its day (Go parses `YYYY-MM-DD` as UTC), and read in a US zone it would land on the evening before. A date made on this device — now, a picked day, a birthday normalised to local midnight — is an instant inside the family's own day. So an exact UTC midnight is read in UTC and anything else in `timeZone`.
    /// The one ambiguous instant is local midnight at UTC+0, where both readings agree.
    func calendarDay(in timeZone: TimeZone = .current) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = isUTCMidnight ? .gmt : timeZone
        return calendar.dateComponents([.year, .month, .day], from: self)
    }

    /// `YYYY-MM-DD` of `calendarDay` — what a write sends, and the key records are grouped into days by.
    func dayKey(in timeZone: TimeZone = .current) -> String {
        let day = calendarDay(in: timeZone)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// The same day as local midnight, for display and for `Calendar.current` arithmetic: a UTC-midnight server date formatted as-is shows the day before anywhere west of Greenwich.
    func localDay(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: calendarDay(in: timeZone)) ?? self
    }

    var isUTCMidnight: Bool {
        timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) == 0
    }
}
