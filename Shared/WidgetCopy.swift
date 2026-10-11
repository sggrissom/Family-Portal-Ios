import Foundation

/// The widgets' words, kept apart from `Copy` because the extension does not compile the app's utilities.
nonisolated enum WidgetCopy {
    static let onThisDayName = "On This Day"
    static let onThisDayDescription = "A photo or milestone from this day in an earlier year."
    static let onThisDay = "On this day"
    static let memoryName = "Memory"
    static let memoryDescription = "A photo, milestone or quote from your family's record, changing through the day."
    static let shuffle = "Shuffle"
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

    /// The line that dates an item: "3 years ago" on this day, or the year it happened for a memory.
    static func when(_ item: WidgetItem) -> String {
        if let years = item.yearsAgo { return yearsAgo(years) }
        return String(item.date.prefix(4))
    }
}
