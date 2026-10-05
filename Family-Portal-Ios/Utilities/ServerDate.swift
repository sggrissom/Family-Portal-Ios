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
        date?.serverDate?.recordDayKey
    }
}

/// A day is held as a *record date*: midnight UTC of the day it names, which is how the server stores and sends one. A photo date is the capture's local wall-clock time labelled UTC. Either way the UTC components are the day, whatever zone the device is in now.
/// Device instants (`Date()`, a `DatePicker` selection) are converted at the edge with `localRecordDay` and shown with `displayDay`.
nonisolated extension Date {

    var recordDay: DateComponents {
        Self.utcCalendar.dateComponents([.year, .month, .day], from: self)
    }

    var recordDayKey: String {
        let day = recordDay
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// The record's day as local midnight, for formatting, a `DatePicker`, and `Calendar.current` arithmetic.
    func displayDay(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: recordDay) ?? self
    }

    /// The record date for the day this instant falls on in `timeZone`.
    func localRecordDay(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return Self.utcCalendar.date(from: calendar.dateComponents([.year, .month, .day], from: self)) ?? self
    }

    /// A photo date for an instant captured on this device: its wall-clock time in `timeZone`, labelled UTC.
    func localWallClock(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return Self.utcCalendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: self)) ?? self
    }

    /// Midnight UTC of this date's UTC day: a server value that carries a time is still read as its UTC day.
    var recordDate: Date {
        Self.utcCalendar.date(from: recordDay) ?? self
    }

    var isUTCMidnight: Bool {
        timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) == 0
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
}
