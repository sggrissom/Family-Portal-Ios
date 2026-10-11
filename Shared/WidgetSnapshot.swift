import Foundation

/// What the app hands the widgets: everything they show, chosen and with its images already downsampled. The widget reads this and the files beside it and nothing else — no network, keychain or SwiftData — so it renders when the app has not run for days and cannot outlive a sign-out (`WidgetStore.removeAll`).
///
/// Shared by the app and the extension. `nonisolated` because the app target defaults to main-actor isolation and the extension does not.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {

    /// Bumped on any change the previous reader could misread. A widget holding a snapshot of another version treats it as absent rather than guessing.
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var generatedAt: Date
    /// For diagnostics only: the widget has no account to check it against.
    var ownerUserId: Int
    /// The site a tap opens, e.g. `https://familyrecord.app`. The widget joins it to an item's `link`; the app answers that URL like any universal link.
    var siteURL: String
    var people: [WidgetPerson]
    /// Local calendar day (`YYYY-MM-DD`) → that day's on-this-day items, from the day the snapshot was made through `horizonDays` ahead. A day with nothing is absent.
    var onThisDay: [String: [WidgetItem]]
    /// The last day `onThisDay` was computed for. Past it the widget can only fall back to the pool.
    var horizon: String
    /// Memories for when a day has nothing on this day, in a fixed order the widget walks by time slot so a reload never reshuffles what is on screen.
    var pool: [WidgetItem]
    /// Every quote, for the Quote widget — words cost nothing to carry, so it is not limited to the pool's share. Optional so a snapshot from before it existed still reads.
    var quotes: [WidgetItem]? = nil
    /// The Home strip's people with their ages worked out for each day of the horizon, for the Family ages widget.
    var family: [WidgetFamilyMember]? = nil

    func person(_ id: Int) -> WidgetPerson? {
        people.first { $0.id == id }
    }

    /// The first names an item is about, in the order the item lists them.
    func names(for item: WidgetItem) -> [String] {
        item.personIds.compactMap { person($0)?.name }
    }

    func url(for item: WidgetItem) -> URL? {
        URL(string: siteURL + item.link)
    }
}

nonisolated struct WidgetPerson: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// The server id, the one a deep link names. A person added offline has none and is left out.
    var id: Int
    /// First name only: a widget is small, and this is what a caption reads.
    var name: String
}

/// One person on the Family ages widget. Ages are computed by the app for each day ahead, so the widget only looks one up.
nonisolated struct WidgetFamilyMember: Codable, Equatable, Hashable, Sendable {
    /// The server id when there is one: what the widget's person filter matches.
    var personId: Int?
    var name: String
    /// Local day → "3y 4m", or for a pregnancy "Due in 5w 2d".
    var ageByDay: [String: String]
    /// Local day → the birthday ahead, only on the days leading up to one.
    var birthdayByDay: [String: WidgetBirthday] = [:]
}

nonisolated struct WidgetBirthday: Codable, Equatable, Hashable, Sendable {
    var inDays: Int
    /// "Theo turns 5 in 5 days".
    var text: String
    /// The age the birthday brings, so a widget can lay it out rather than reading it back out of `text`. Optional: a snapshot from before it existed has only the sentence.
    var turning: Int? = nil
}

nonisolated struct WidgetItem: Codable, Equatable, Hashable, Sendable, Identifiable {

    enum Kind: String, Codable, Sendable {
        case photo
        case milestone
        case quote
        case artwork
    }

    /// `photo:123` / `milestone:45`, so a photo and a milestone sharing a server id are still two items.
    var id: String
    var kind: Kind
    /// The record's own day, `YYYY-MM-DD`.
    var date: String
    /// Set on on-this-day items: how many years before the day it is shown on.
    var yearsAgo: Int?
    /// The milestone or quote as it reads ("First steps", “Bye bye moon”), or the photo's title, which may be empty.
    var title: String
    var personIds: [Int]
    /// A file name inside `WidgetStore`'s images directory. `nil` for an item with nothing to show but words.
    var imageFile: String?
    /// Site-relative path a tap opens, e.g. `/dashboard`.
    var link: String

    var hasImage: Bool { imageFile != nil }
}

/// Calendar days as `YYYY-MM-DD` keys, the way the snapshot names them.
nonisolated enum WidgetDay {

    /// The local calendar day `date` falls on — the day a person looking at the widget would call today.
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Whether a record from `recordDay` has its anniversary on `day`, both `YYYY-MM-DD`. A 29 February record's anniversary is 1 March in a common year, as the server's `AddDate` makes it.
    static func isAnniversary(of recordDay: String, on day: String) -> Bool {
        let record = recordDay.split(separator: "-").compactMap { Int($0) }
        let shown = day.split(separator: "-").compactMap { Int($0) }
        guard record.count == 3, shown.count == 3 else { return false }
        var month = record[1], dayOfMonth = record[2]
        let year = shown[0]
        let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        if month == 2, dayOfMonth == 29, !isLeap {
            month = 3
            dayOfMonth = 1
        }
        return month == shown[1] && dayOfMonth == shown[2]
    }

    /// Local midnight of the day after `date`.
    static func nextMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }
}
