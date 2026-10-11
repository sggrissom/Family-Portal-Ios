import Foundation

/// The widgets' words, kept apart from `Copy` because the extension does not compile the app's utilities.
nonisolated enum WidgetCopy {
    static let onThisDayName = "On This Day"
    static let onThisDayDescription = "A photo or milestone from this day in an earlier year."
    static let onThisDay = "On this day"
    static let aroundThisDay = "Around this day"
    static let memoryName = "Memory"
    static let memoryDescription = "A photo, milestone or quote from your family's record, changing through the day."
    static let shuffle = "Shuffle"
    static let quoteName = "Quote"
    static let quoteDescription = "Something your family said, changing through the day."
    static let noQuotes = "No quotes yet"
    static let noQuotesDetail = "Quotes saved in Family Record appear here."
    static let agesName = "Family Ages"
    static let agesDescription = "How old everyone is, and whose birthday is coming up."
    static let family = "Family"
    static let noAges = "No birthdays yet"
    static let noAgesDetail = "Add birthdays in Family Record."

    /// How far ahead a birthday is mentioned.
    static let birthdayLookaheadDays = 14

    /// "Theo turns 5 today", "Theo turns 5 tomorrow", "Theo turns 5 in 5 days".
    static func birthday(_ name: String, turning: Int, inDays days: Int) -> String {
        switch days {
        case 0: "\(name) turns \(turning) today"
        case 1: "\(name) turns \(turning) tomorrow"
        default: "\(name) turns \(turning) in \(days) days"
        }
    }
    static let nothingMatches = "Nothing to show yet"
    static let nothingMatchesDetail = "Nothing in the record matches this widget's choices."
    static let memory = "A memory"
    static let signedOut = "Sign in to Family Record"
    static let signedOutDetail = "Your family's memories will appear here."
    static let nothing = "Nothing here yet"
    static let stale = "Open Family Record to refresh"
    static let nothingDetail = "Add photos and milestones in Family Record."

    static func yearsAgo(_ n: Int) -> String {
        n == 1 ? "1 year ago" : "\(n) years ago"
    }

    /// "Clara", "Clara & Mia", "Clara, Mia & Theo", "Clara, Mia +2".
    static func names(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) & \(names[1])"
        case 3: "\(names[0]), \(names[1]) & \(names[2])"
        default: "\(names[0]), \(names[1]) +\(names.count - 2)"
        }
    }

    /// "Oct 13, 2023" for a `YYYY-MM-DD` day. The day is a calendar day, not an instant, so it is formatted in UTC where it was built.
    static func date(_ day: String, locale: Locale = .current) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return day }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar)
        style.timeZone = .gmt
        return date.formatted(style)
    }

    /// "Clara · Oct 13, 2023": who and when, either of which may be missing.
    static func attribution(_ names: [String], _ when: String) -> String {
        [Self.names(names), when].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Whether stored words already carry their own quotation marks (`Quotes.display` adds them), so a widget does not add a decorative pair.
    static func isQuoted(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return "\"“„«‘'".contains(first)
    }
}
