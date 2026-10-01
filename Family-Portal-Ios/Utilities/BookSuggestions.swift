import Foundation

// The suggesting half of `frontend/lib/book.ts` and `frontend/lib/bookPlans.ts`: drafting a new book, re-picking photos when the length or the kinds of content change, and spotting records added since the book was last saved.
// Deterministic, like the web's: the same records and the same choices always give the same book, so a re-pick never shuffles what is already there.

nonisolated enum BookDensity: String, CaseIterable, Identifiable, Sendable {
    case brief, balanced, detailed

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Photos per month, or per person per month in a book about several people.
    var photoBudget: Int {
        switch self {
        case .brief: return 3
        case .balanced: return 7
        case .detailed: return 14
        }
    }

    /// Photos from any one day, so one busy afternoon cannot fill a month.
    var perDay: Int {
        switch self {
        case .brief: return 1
        case .balanced: return 2
        case .detailed: return 4
        }
    }

    init(_ raw: String) {
        self = BookDensity(rawValue: raw) ?? .balanced
    }
}

nonisolated struct BookCategory: Hashable, Sendable, Identifiable {
    let value: String
    let label: String

    var id: String { value }

    static let all = [
        BookCategory(value: "milestones", label: "Milestones"),
        BookCategory(value: "quotes", label: "Quotes"),
        BookCategory(value: "artwork", label: "Artwork"),
        BookCategory(value: "photos", label: "Photos"),
    ]
}

nonisolated extension BookItemDTO {
    static func milestone(_ id: Int, photoId: Int = 0) -> BookItemDTO {
        BookItemDTO(kind: .milestone, sourceId: id, photoId: photoId)
    }

    static func photo(_ id: Int) -> BookItemDTO {
        BookItemDTO(kind: .photo, sourceId: id)
    }
}

extension BookAssembler {

    // MARK: - Candidates

    func categoryOf(_ item: BookItemDTO) -> String {
        if item.itemKind == .photo { return "photos" }
        switch milestones[item.sourceId]?.category {
        case "quote": return "quotes"
        case "artwork": return "artwork"
        default: return "milestones"
        }
    }

    /// Tagged with one of the book's people — or, asked for "all", with every one of them. A photo with nobody tagged never matches; it is offered for adding by hand.
    func photoMatches(_ id: Int) -> Bool {
        let tagged = sources.photoPeople[id] ?? []
        if tagged.isEmpty { return false }
        return match == "all" ? tagged.count == people.count : true
    }

    /// Everything in the book's dates, oldest first.
    func candidates() -> (milestones: [BookMilestoneDTO], photos: [BookImageDTO]) {
        let milestones = self.milestones.values
            .filter { inRange(BookDay.dayOf($0.milestoneDate)) }
            .sorted { ($0.milestoneDate, $0.id) < ($1.milestoneDate, $1.id) }
        let photos = self.photos.values
            .filter { inRange(BookDay.dayOf($0.photoDate)) }
            .sorted { ($0.photoDate, $0.id) < ($1.photoDate, $1.id) }
        return (milestones, photos)
    }

    private func bucketOf(_ item: BookItemDTO) -> String {
        "\(sectionOf(item)):\(slotOf(itemDay(item) ?? ""))"
    }

    /// Picks spread across distinct days: one from each day first, evenly spaced through the month, then a second from each, up to `perDay`.
    static func spreadPick<T>(_ items: [T], day: (T) -> String, budget: Int, perDay: Int = .max) -> [T] {
        var byDay: [String: [T]] = [:]
        for item in items { byDay[day(item), default: []].append(item) }
        let days = byDay.keys.sorted()
        var picked: [T] = []
        var round = 0
        while round < perDay && picked.count < budget {
            let available = days.filter { (byDay[$0]?.count ?? 0) > round }
            if available.isEmpty { break }
            let want = min(budget - picked.count, available.count)
            for k in 0..<want {
                let index = Int((Double(k) + 0.5) * Double(available.count) / Double(want))
                picked.append(byDay[available[index]]![round])
            }
            round += 1
        }
        return picked.enumerated()
            .sorted { (day($0.element), $0.offset) < (day($1.element), $1.offset) }
            .map(\.element)
    }

    /// The profile photo when it falls in the book, else a wide photo — past the first two months in a first year, of several people in a family book.
    private func chooseCover(_ picked: [BookImageDTO]) -> Int {
        if !isMulti, let profile = photos[people.first?.profilePhotoId ?? 0] {
            let day = BookDay.dayOf(profile.photoDate)
            if inRange(day) && slotOf(day) != Self.birthdaySlot { return profile.id }
        }
        let pool = isMulti
            ? picked.filter { (sources.photoPeople[$0.id] ?? []).count > 1 }
            : picked.filter { slotOf(BookDay.dayOf($0.photoDate)) != Self.birthdaySlot }
        let wide: (BookImageDTO) -> Bool = { $0.width >= $0.height }
        let settled = firstYear ? pool.filter { BookDay.monthsOld(start, BookDay.dayOf($0.photoDate)) >= 2 } : pool
        return (settled.first(where: wide) ?? pool.first(where: wide) ?? pool.first ?? picked.first)?.id ?? 0
    }

    // MARK: - Suggesting

    /// Milestones in the chosen categories are always offered; photos are budgeted per month, and per person in a book about several people. Kept items survive, excluded ones never return, and a re-pick keeps the order the book already had.
    func suggest(density: BookDensity, current: [BookItemDTO] = [], excluded: [BookItemDTO] = [], coverPhotoId: Int = 0) -> (items: [BookItemDTO], coverPhotoId: Int) {
        let excludedKeys = Set(excluded.map(\.key))
        var currentByKey: [String: BookItemDTO] = [:]
        for item in current where currentByKey[item.key] == nil { currentByKey[item.key] = item }
        let (milestones, photos) = candidates()
        let budget = density.photoBudget
        func room(_ section: Int) -> Int {
            guard isMulti else { return budget }
            return section == 0 ? (budget + 1) / 2 : (budget + 2) / 3
        }

        let matching = photos.filter { photoMatches($0.id) && !excludedKeys.contains(BookItemDTO.photo($0.id).key) }
        let cover = coverPhotoId != 0 && self.photos[coverPhotoId] != nil ? coverPhotoId : chooseCover(matching)

        var used: Set<Int> = [cover]
        var chosen: [BookItemDTO] = []
        var seen: Set<String> = []
        for item in current where seen.insert(item.key).inserted {
            if item.itemKind == .milestone && item.photoId != 0 { used.insert(item.photoId) }
            if item.pinned && itemDay(item) != nil {
                if item.itemKind == .photo { used.insert(item.sourceId) }
                chosen.append(item)
            }
        }

        for m in milestones {
            let key = BookItemDTO.milestone(m.id).key
            let kept = currentByKey[key]
            var item = kept ?? .milestone(m.id)
            if excludedKeys.contains(key) || item.pinned || !categories.contains(categoryOf(item)) { continue }
            if kept == nil {
                item.photoId = m.photoIds.first { self.photos[$0] != nil && !used.contains($0) } ?? 0
                if item.photoId != 0 { used.insert(item.photoId) }
            }
            chosen.append(item)
        }

        if categories.contains("photos") {
            var bucketOrder: [String] = []
            var buckets: [String: [BookImageDTO]] = [:]
            for image in matching where !used.contains(image.id) {
                let key = bucketOf(.photo(image.id))
                if buckets[key] == nil { bucketOrder.append(key) }
                buckets[key, default: []].append(image)
            }
            var pinnedIn: [String: Int] = [:]
            for item in chosen where item.itemKind == .photo {
                pinnedIn[bucketOf(item), default: 0] += 1
            }
            for key in bucketOrder {
                let section = Int(key.split(separator: ":").first ?? "0") ?? 0
                let space = max(0, room(section) - (pinnedIn[key] ?? 0))
                let picks = Self.spreadPick(buckets[key] ?? [], day: { BookDay.dayOf($0.photoDate) }, budget: space, perDay: density.perDay)
                for image in picks {
                    chosen.append(currentByKey[BookItemDTO.photo(image.id).key] ?? .photo(image.id))
                }
            }
        }

        let items = current.isEmpty ? heroFirst(chosen) : mergeInOrder(current: current, chosen: chosen)
        return (items, cover)
    }

    private func byDay(_ a: BookItemDTO, _ b: BookItemDTO) -> Bool {
        ((itemDay(a) ?? ""), a.kind, a.sourceId) < ((itemDay(b) ?? ""), b.kind, b.sourceId)
    }

    /// Moves each month's best opening photo to the front of that month.
    private func heroFirst(_ items: [BookItemDTO]) -> [BookItemDTO] {
        let sorted = items.sorted(by: byDay)
        var groups: [String: [BookItemDTO]] = [:]
        for item in sorted { groups[bucketOf(item), default: []].append(item) }
        var heroes: [String: BookItemDTO] = [:]
        for (key, group) in groups {
            let loose = group.filter { $0.itemKind == .photo }
            let momentPhoto = group.contains { $0.itemKind == .milestone && $0.photoId != 0 }
            if loose.count >= 3 || (!loose.isEmpty && !momentPhoto) {
                heroes[key] = loose.first { item in
                    guard let p = photos[item.sourceId] else { return false }
                    return p.width >= p.height
                } ?? loose[0]
            }
        }
        var out: [BookItemDTO] = []
        var placed: Set<String> = []
        for item in sorted {
            let key = bucketOf(item)
            let hero = heroes[key]
            if let hero, !placed.contains(key) {
                placed.insert(key)
                out.append(hero)
            }
            if item.key != hero?.key { out.append(item) }
        }
        return out
    }

    private func mergeInOrder(current: [BookItemDTO], chosen: [BookItemDTO]) -> [BookItemDTO] {
        let chosenKeys = Set(chosen.map(\.key))
        var out = current.filter { chosenKeys.contains($0.key) }
        var present = Set(out.map(\.key))
        for item in chosen.sorted(by: byDay) where !present.contains(item.key) {
            insertByDay(&out, item)
            present.insert(item.key)
        }
        return out
    }

    /// Before the first item dated later, so an item added by hand lands where its day says.
    func insertByDay(_ items: inout [BookItemDTO], _ item: BookItemDTO) {
        let day = itemDay(item) ?? ""
        if let at = items.firstIndex(where: { (itemDay($0) ?? "") > day }) {
            items.insert(item, at: at)
        } else {
            items.append(item)
        }
    }

    /// Records the editor has not seen: created after the book was last reviewed, and neither in the book nor left out.
    func additions(since reviewedAt: String, items: [BookItemDTO], excluded: [BookItemDTO]) -> [BookItemDTO] {
        guard let since = BookTime.parse(reviewedAt) else { return [] }
        func isNew(_ createdAt: String) -> Bool {
            BookTime.parse(createdAt).map { $0 > since } ?? false
        }
        let known = Set((items + excluded).map(\.key))
        let usedPhotos = Set(items.map(\.photoId).filter { $0 != 0 })
        let (milestones, photos) = candidates()
        var out: [BookItemDTO] = []
        for m in milestones {
            var item = BookItemDTO.milestone(m.id)
            if isNew(m.createdAt) && !known.contains(item.key) {
                item.photoId = m.photoIds.first { self.photos[$0] != nil } ?? 0
                out.append(item)
            }
        }
        for p in photos {
            let item = BookItemDTO.photo(p.id)
            let relevant = photoMatches(p.id) || untagged.contains(p.id)
            if isNew(p.createdAt) && relevant && !known.contains(item.key) && !usedPhotos.contains(p.id) {
                out.append(item)
            }
        }
        return out
    }

    // MARK: - The editor's words

    /// "May 4 · Theo · 3 years 2 months" — when an item is from, and whose it is.
    func detailOf(_ item: BookItemDTO) -> String {
        let day = itemDay(item) ?? ""
        var parts = [BookDay.shortDay(day)]
        if item.itemKind == .milestone {
            if let m = milestones[item.sourceId], let owner = person[m.personId] {
                if isMulti { parts.append(owner.name) }
                let born = BookDay.dayOf(owner.birthday)
                if BookDay.isRealDay(born) && born <= day {
                    let age = BookDay.photoAge(born, day)
                    if !age.isEmpty { parts.append(age) }
                }
            }
        } else if let photo = photos[item.sourceId] {
            let detail = photoDetail(photo)
            if !detail.isEmpty {
                parts.append(detail)
            } else if isMulti {
                let tagged = (sources.photoPeople[item.sourceId] ?? []).compactMap { person[$0]?.name }
                parts.append(tagged.isEmpty ? "Nobody tagged" : Self.joinNames(tagged))
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Drafting

    /// A new book's first draft: its items and cover, suggested from the sources, as `draftSelection` makes one.
    static func draft(_ book: BookDTO, sources: BookSourcesDTO, density: BookDensity) -> BookDTO {
        var draft = book
        draft.items = []
        let suggestion = BookAssembler(book: draft, sources: sources).suggest(density: density)
        draft.items = suggestion.items
        draft.coverPhotoId = suggestion.coverPhotoId
        return draft
    }
}

/// The server's times — `createdAt`, `reviewedAt`, `now` — as Go writes them: RFC 3339 with up to nine fractional digits, which `ISO8601DateFormatter` will not read, so the fraction is dropped first. A second is finer than anything compared here.
nonisolated enum BookTime {
    static func parse(_ value: String) -> Date? {
        let trimmed = value.replacingOccurrences(of: "\\.[0-9]+", with: "", options: .regularExpression)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}

// MARK: - Plans

/// A port of `frontend/lib/bookPlans.ts`: the concrete dates a new book covers and the title it starts with.
enum BookPlans {

    enum YearKind: String, CaseIterable, Identifiable, Sendable {
        case calendar, past, age

        var id: String { rawValue }

        var label: String {
            switch self {
            case .calendar: return "Calendar year"
            case .past: return "Past 12 months"
            case .age: return "Year of age"
            }
        }
    }

    /// Half-open: `end` is the day after the last one covered.
    struct Period: Equatable, Sendable {
        let start: String
        let end: String
    }

    struct Preset: Identifiable, Sendable {
        let value: String
        let label: String
        let blurb: String
        let symbol: String

        var id: String { value }

        /// One person; the others are about any number.
        var isSingle: Bool { value == BookPreset.firstYear || value == BookPreset.year }
    }

    static let presets = [
        Preset(value: BookPreset.firstYear, label: "First year", blurb: "Birth to the first birthday, month by month.", symbol: "birthday.cake"),
        Preset(value: BookPreset.year, label: "A year of one person", blurb: "A calendar year, the past twelve months, or a year of age.", symbol: "person.crop.square"),
        Preset(value: BookPreset.familyYear, label: "Family yearbook", blurb: "Shared moments through the year, then a section for each person.", symbol: "person.3"),
        Preset(value: BookPreset.custom, label: "Custom", blurb: "Any people, any dates.", symbol: "calendar"),
    ]

    static func calendarYear(_ year: Int) -> Period {
        Period(start: String(format: "%04d-01-01", year), end: String(format: "%04d-01-01", year + 1))
    }

    /// Ends tomorrow, so that today is the last day covered.
    static func pastYear(today: String) -> Period {
        Period(start: BookDay.addDays(BookDay.addYears(today, -1), 1), end: BookDay.addDays(today, 1))
    }

    static func yearOfAge(birthday: String, age: Int) -> Period {
        let born = BookDay.dayOf(birthday)
        return Period(start: BookDay.addYears(born, age), end: BookDay.addYears(born, age + 1))
    }

    static func firstYear(birthday: String) -> Period {
        let born = BookDay.dayOf(birthday)
        return Period(start: born, end: BookDay.addYears(born, 1))
    }

    static func ageNow(birthday: String, today: String) -> Int {
        max(0, BookDay.monthsOld(BookDay.dayOf(birthday), today) / 12)
    }

    private static func possessive(_ name: String) -> String {
        name.hasSuffix("s") ? "\(name)'" : "\(name)'s"
    }

    static func defaultTitle(preset: String, names: [String], period: Period, yearKind: YearKind, age: Int) -> String {
        let first = names.first ?? ""
        switch preset {
        case BookPreset.firstYear:
            return "\(possessive(first)) first year"
        case BookPreset.year:
            switch yearKind {
            case .calendar: return "\(possessive(first)) \(period.start.prefix(4))"
            case .age: return age == 0 ? "\(possessive(first)) first year" : "\(first) at \(BookAssembler.numberWord(age).lowercased())"
            case .past: return "\(possessive(first)) year"
            }
        case BookPreset.familyYear:
            return "Our \(period.start.prefix(4))"
        default:
            return "\(BookAssembler.joinNames(names)), \(BookDay.monthSpan(period.start, BookDay.addDays(period.end, -1)))"
        }
    }
}
