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
