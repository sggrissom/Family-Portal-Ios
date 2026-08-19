import Foundation

nonisolated extension Date {

    /// Whether this is Go's zero `time.Time` rather than a date anybody meant.
    ///
    /// The activities tables store `StartDate`, `EndDate` and `OccurredAt` as
    /// non-pointer `time.Time` (backend/activity.go), and "not known yet" is an
    /// explicitly normal state — `parseActivityDate` turns an absent or empty
    /// `YYYY-MM-DD` into the zero time rather than an error. Encoded, that is
    /// `"0001-01-01T00:00:00Z"`, which `APIClient`'s ISO8601 decoder accepts
    /// happily and hands back as a `Date` in the year 1. Formatting it prints
    /// *Jan 1, 1* everywhere the web prints nothing.
    ///
    /// The cutoff is 1900 rather than an equality check against the exact
    /// instant: the wire value is the zero time in UTC, and comparing an
    /// instant that has been through a decoder and a calendar for equality is
    /// the kind of test that passes until a timezone is involved. Nothing this
    /// app records predates 1900, so everything below the line is a marshalled
    /// zero.
    var isServerZero: Bool {
        self < Self.serverZeroCutoff
    }

    /// The date, or `nil` when the server was saying it does not have one.
    /// Every activities date should be read through this or `isServerZero`.
    var serverDate: Date? {
        isServerZero ? nil : self
    }

    /// 1900-01-01T00:00:00Z.
    private static let serverZeroCutoff = Date(timeIntervalSince1970: -2_208_988_800)
}

/// The one date format the activities write procs accept.
///
/// `parseActivityDate` (backend/activity_procs.go) reads `YYYY-MM-DD` and
/// nothing else, and answers "Dates must be in YYYY-MM-DD format" for anything
/// else. The calendar and locale are pinned because the format is numeric and
/// fixed: a device on a Japanese calendar would otherwise send an era year the
/// server cannot parse, and a locale with non-Western digits would send digits
/// it cannot read either.
nonisolated enum ServerDateFormat {

    /// `nil` in, `nil` out, and that is meaningful: an absent key on a write
    /// **clears** the date rather than leaving it alone (see the write requests
    /// in `ActivityDTOs`). A screen showing no date means "unknown", which is
    /// exactly what clearing it says.
    static func requestString(_ date: Date?) -> String? {
        guard let date = date?.serverDate else { return nil }

        // Built per call rather than cached in a `static let`. A `DateFormatter`
        // is not `Sendable`, and this one has to read the device's *current*
        // time zone: a `DatePicker` hands back midnight local, so formatting in
        // a zone fixed at launch would move a competition to the day before —
        // and a competition weekend is exactly when a phone changes zone. This
        // is a save path, called once per write, so building one costs nothing.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
