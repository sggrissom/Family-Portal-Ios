import Foundation

/// What the gallery is currently showing, as a value. Within a category the choices are OR; the categories AND together.
struct PhotoFilter: Equatable {

    /// Local ids, not remote ones: a person created on this device and still syncing has no remote id.
    var personLocalIds: Set<UUID> = []

    /// Remote ids, because that is what a `Photo` carries.
    var tagRemoteIds: Set<Int> = []

    var dateFrom: Date?
    var dateTo: Date?
    var searchText: String = ""

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

    /// A `to` of the 3rd means through the end of the 3rd, and a range entered backwards is swapped rather than matching nothing.
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
            // `localizedStandardContains` is the Finder-style comparison: case- and diacritic-insensitive, so "jose" finds "José".
            guard photo.title.localizedStandardContains(search)
                    || photo.descriptionText.localizedStandardContains(search) else {
                return false
            }
        }

        return true
    }

    func summary(peopleNames: (UUID) -> String?) -> String {
        var parts: [String] = []

        if personLocalIds.count == 1 {
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

    private nonisolated static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private nonisolated static func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        // Not `startOfDay + 86400 - 1`: days are not all 86400 seconds long where daylight saving applies.
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            return date
        }
        return next.addingTimeInterval(-0.001)
    }

    private nonisolated static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
