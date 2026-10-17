import Foundation

/// The last few searches, newest first, shown when the search field is empty — `addRecent`/`loadRecent` in frontend/lib/search.ts.
/// On the device only, and erased with the account's other local data.
nonisolated enum RecentSearches {
    static let limit = 8
    static let key = "com.familyrecord.recentSearches"

    /// `query` first, without an earlier copy that differs only in case or accents.
    static func adding(_ query: String, to recent: [String]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return recent }
        let folded = SearchText.fold(trimmed)
        return Array(([trimmed] + recent.filter { SearchText.fold($0) != folded }).prefix(limit))
    }

    static func load(from defaults: UserDefaults = .standard) -> [String] {
        Array((defaults.stringArray(forKey: key) ?? []).prefix(limit))
    }

    static func save(_ recent: [String], to defaults: UserDefaults = .standard) {
        defaults.set(recent, forKey: key)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
