import Foundation

extension Date {

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
