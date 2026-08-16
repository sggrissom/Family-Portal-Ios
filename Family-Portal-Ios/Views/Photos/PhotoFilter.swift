import Foundation

/// What the gallery is currently showing, as a value: which people a photo must
/// be tagged with, which tags it must carry, the date window it must fall in, and
/// free text matched against its title and description.
///
/// The three panel filters mirror `frontend/hooks/usePhotoFilter.ts`: choices
/// *within* a category are OR (any selected person, any selected tag), and the
/// categories AND together. Search is the one thing the web has no equivalent
/// for; it is here because a phone-sized grid runs out of scroll long before a
/// desktop one does.
///
/// A value type rather than state on the view so the whole rule is testable
/// without a `View` — filtering is the part of this screen that can be wrong in a
/// way nobody notices, since a photo wrongly excluded simply isn't there.
struct PhotoFilter: Equatable {

    /// Local ids, not remote ones: a person created on this device and still
    /// syncing has no remote id, and their photos are exactly the ones most
    /// likely to be looked at right now.
    var personLocalIds: Set<UUID> = []

    /// Remote ids, because that is what a `Photo` carries — the tag vocabulary is
    /// the server's, and `Photo.tagRemoteIds` never holds anything local.
    var tagRemoteIds: Set<Int> = []

    var dateFrom: Date?
    var dateTo: Date?
    var searchText: String = ""

    /// Everything the filter sheet controls. Kept apart from `isActive` because
    /// the sheet's toolbar button reflects this and not the search field, which
    /// has its own visible state in the search bar.
    var hasPanelFilters: Bool {
        !personLocalIds.isEmpty || !tagRemoteIds.isEmpty || dateFrom != nil || dateTo != nil
    }

    var isActive: Bool {
        hasPanelFilters || !trimmedSearch.isEmpty
    }

    mutating func clearPanelFilters() {
        personLocalIds = []
        tagRemoteIds = []
        dateFrom = nil
        dateTo = nil
    }

    var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The range actually applied. A `to` of the 3rd means "through the end of the
    /// 3rd" — a photo dated that day carries a time and would otherwise fall
    /// outside a window that names its own date — and a range entered backwards is
    /// swapped rather than matching nothing, both as `normalizeDateRange` does on
    /// the web.
    var normalizedDateRange: (from: Date?, to: Date?) {
        guard let dateFrom else {
            return (nil, dateTo.map(Self.endOfDay))
        }
        guard let dateTo else {
            return (Self.startOfDay(dateFrom), nil)
        }
        if dateFrom <= dateTo {
            return (Self.startOfDay(dateFrom), Self.endOfDay(dateTo))
        }
        return (Self.startOfDay(dateTo), Self.endOfDay(dateFrom))
    }

    func apply(to photos: [Photo]) -> [Photo] {
        guard isActive else { return photos }

        // Normalised once rather than per photo: both ends go through `Calendar`,
        // and a gallery is the one list here with no upper bound on length.
        let range = normalizedDateRange
        let search = trimmedSearch
        return photos.filter { matches($0, range: range, search: search) }
    }

    private func matches(_ photo: Photo, range: (from: Date?, to: Date?), search: String) -> Bool {
        if !personLocalIds.isEmpty {
            guard photo.taggedPeople.contains(where: { personLocalIds.contains($0.id) }) else {
                return false
            }
        }

        if !tagRemoteIds.isEmpty {
            guard photo.tagRemoteIds.contains(where: { tagRemoteIds.contains($0) }) else {
                return false
            }
        }

        if let from = range.from, photo.photoDate < from {
            return false
        }
        if let to = range.to, photo.photoDate > to {
            return false
        }

        if !search.isEmpty {
            // `localizedStandardContains` is the Finder-style comparison:
            // case- and diacritic-insensitive, so "jose" finds "José".
            guard photo.title.localizedStandardContains(search)
                    || photo.descriptionText.localizedStandardContains(search) else {
                return false
            }
        }

        return true
    }

    /// Names the active panel filters for the toolbar button, in the web's
    /// wording. Search is left out — the search bar is already showing it.
    func summary(peopleNames: (UUID) -> String?) -> String {
        var parts: [String] = []

        if personLocalIds.count == 1 {
            // A person deleted between opening the panel and reading this is
            // still excluding photos, so the summary has to say so somehow.
            parts.append(personLocalIds.first.flatMap(peopleNames) ?? "1 person")
        } else if !personLocalIds.isEmpty {
            parts.append("\(personLocalIds.count) people")
        }

        if !tagRemoteIds.isEmpty {
            parts.append(tagRemoteIds.count == 1 ? "1 tag" : "\(tagRemoteIds.count) tags")
        }

        let range = normalizedDateRange
        switch (range.from, range.to) {
        case let (from?, to?):
            parts.append("\(Self.shortDate(from)) – \(Self.shortDate(to))")
        case let (from?, nil):
            parts.append("from \(Self.shortDate(from))")
        case let (nil, to?):
            parts.append("until \(Self.shortDate(to))")
        case (nil, nil):
            break
        }

        return parts.joined(separator: ", ")
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        // Not `startOfDay + 86400 - 1`: days are not all 86400 seconds long where
        // daylight saving applies.
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            return date
        }
        return next.addingTimeInterval(-0.001)
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
