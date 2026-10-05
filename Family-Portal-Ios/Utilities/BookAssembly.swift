import Foundation

// A port of the reading half of `frontend/lib/book.ts`: `assembleBook` and everything it calls, turning a saved book and its sources into chapters of designed blocks.
// The suggesting half (`suggestItems`, `additionsSince`) belongs to the editor and is not here yet. The server stores only references and order; how those become a cover, chapters and layouts is decided here exactly as the web decides it, so a book reads the same on both.
// Every date is the day its ISO string names, as `dayOf` reads it — `YYYY-MM-DD`, compared as strings, with no time zone.

/// Day-string arithmetic, mirroring the web's UTC `Date` helpers.
nonisolated enum BookDay {

    static func dayOf(_ iso: String) -> String {
        String(iso.prefix(10))
    }

    static func isRealDay(_ day: String) -> Bool {
        day.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil && day > "1000"
    }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static func parts(_ day: String) -> (year: Int, month: Int, day: Int) {
        let pieces = day.split(separator: "-").map { Int($0) ?? 0 }
        guard pieces.count == 3 else { return (0, 1, 1) }
        return (pieces[0], pieces[1], pieces[2])
    }

    /// The record date of the day: midnight UTC.
    static func date(_ day: String) -> Date {
        let p = parts(day)
        return utc.date(from: DateComponents(year: p.year, month: p.month, day: p.day)) ?? Date(timeIntervalSince1970: 0)
    }

    static func key(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `Date.UTC(year, month + months, day)`: the month's first day plus the day, so a 31st rolls into the next month and Feb 29 a year on is March 1.
    static func shifted(_ day: String, years: Int = 0, months: Int = 0) -> String {
        let p = parts(day)
        let index = p.year * 12 + (p.month - 1) + years * 12 + months
        let year = Int((Double(index) / 12).rounded(.down))
        let month = index - year * 12 + 1
        guard let first = utc.date(from: DateComponents(year: year, month: month, day: 1)),
              let shifted = utc.date(byAdding: .day, value: p.day - 1, to: first)
        else { return day }
        return key(shifted)
    }

    static func addYears(_ day: String, _ n: Int) -> String {
        shifted(day, years: n)
    }

    static func addDays(_ day: String, _ n: Int) -> String {
        guard let moved = utc.date(byAdding: .day, value: n, to: date(day)) else { return day }
        return key(moved)
    }

    static func daysBetween(_ from: String, _ to: String) -> Int {
        Int((date(to).timeIntervalSince(date(from)) / 86_400).rounded())
    }

    /// `monthsOld` over two days.
    static func monthsOld(_ birthday: String, _ at: String) -> Int {
        let born = parts(birthday)
        let then = parts(at)
        var months = (then.year - born.year) * 12 + then.month - born.month
        if then.day < born.day { months -= 1 }
        return months
    }

    /// "6 months, 8 days" — `photoAge` over two days.
    static func photoAge(_ birthday: String, _ at: String) -> String {
        AgeSteps.photoAge(birthday: date(birthday), at: date(at))
    }

    static func monthIndex(_ day: String) -> Int {
        let p = parts(day)
        return p.year * 12 + p.month - 1
    }

    static func firstOfMonth(_ day: String) -> String {
        String(day.prefix(8)) + "01"
    }

    private static func format(_ day: String, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = .gmt
        formatter.dateFormat = pattern
        return formatter.string(from: date(day))
    }

    /// "March 14, 2024"
    static func longDay(_ day: String) -> String { format(day, "MMMM d, yyyy") }

    /// "March 14"
    static func shortDay(_ day: String) -> String { format(day, "MMMM d") }

    static func monthName(_ day: String, year: Bool) -> String {
        format(day, year ? "MMMM yyyy" : "MMMM")
    }

    /// "March 2024", "March – May 2024", "November 2024 – January 2025".
    static func monthSpan(_ from: String, _ to: String) -> String {
        if from.prefix(7) == to.prefix(7) { return monthName(from, year: true) }
        if from.prefix(4) == to.prefix(4) { return "\(monthName(from, year: false)) – \(monthName(to, year: true))" }
        return "\(monthName(from, year: true)) – \(monthName(to, year: true))"
    }

    /// The inclusive dates a half-open range covers: "March 14, 2024 – March 13, 2025".
    static func bookDates(start: String, end: String) -> String {
        "\(longDay(dayOf(start))) – \(longDay(addDays(dayOf(end), -1)))"
    }
}

nonisolated enum BookPreset {
    static let firstYear = "first-year"
    static let year = "year"
    static let familyYear = "family-year"
    static let custom = "custom"
}

// MARK: - What the reader draws

nonisolated struct BookPhoto: Hashable, Sendable {
    let id: Int
    let width: Int
    let height: Int
    let day: String
    let caption: String
    /// How old the subject was, or in a book about several people who is in it.
    let detail: String

    var isTall: Bool { height > width }
}

nonisolated struct BookMoment: Hashable, Sendable {
    let id: Int
    let text: String
    let context: String
    let day: String
    let detail: String
    let first: Bool
}

nonisolated struct GrowthPoint: Hashable, Sendable {
    let day: String
    /// Fractional months since birth.
    let months: Double
    /// Fractional months since the book's first day, where the chart places the point.
    let position: Double
    let value: Double
    let label: String
}

/// The small fixed set of layouts a chapter is built from.
nonisolated enum BookBlock: Hashable, Sendable {
    case hero(BookPhoto)
    case photos([BookPhoto])
    case moment(BookMoment, photo: BookPhoto?)
    case quote(BookMoment)
    case artwork(BookMoment, photo: BookPhoto)
    case notes([BookMoment])
    case facts([String])
    case letter(text: String, signature: String)
    case growth(height: [GrowthPoint], weight: [GrowthPoint])
}

nonisolated struct BookChapter: Identifiable, Hashable, Sendable {
    let id: String
    /// Empty for an untitled stretch — an introduction or a closing letter — which the contents leave out.
    let title: String
    let dates: String
    let blocks: [BookBlock]
    /// Indices into the book's saved items, in the order the chapter shows them.
    let items: [Int]
}

struct AssembledBook {
    let name: String
    let title: String
    let dates: String
    let cover: BookPhoto?
    let chapters: [BookChapter]
    let ending: String
    /// Saved items whose record has been deleted or is no longer visible to the viewer, skipped.
    let missing: Int
    /// How long the growth chart's axis runs and what its ends are called.
    let growthAxis: GrowthAxis
}

/// The web's chart runs from birth to one year. A book about some other stretch runs from its own first day to its last, so a seven-year-old's year is not squeezed against the right edge.
nonisolated struct GrowthAxis: Hashable, Sendable {
    /// In months, from the book's first day.
    let span: Double
    let start: String
    let end: String
}

// MARK: - Assembly

struct BookAssembler {

    static let birthdaySlot = -1

    let book: BookDTO
    let sources: BookSourcesDTO

    let people: [BookPersonDTO]
    let person: [Int: BookPersonDTO]
    let start: String
    let end: String
    let limit: String
    let firstYear: Bool
    let months: Int
    /// Ready, dated photos only: the rest can be neither read nor chosen.
    let photos: [Int: BookImageDTO]
    let milestones: [Int: BookMilestoneDTO]
    /// The chosen kinds of content; every kind when the book names none.
    let categories: Set<String>
    /// "all": only photos with every one of the book's people in them.
    let match: String
    let untagged: Set<Int>

    init(book: BookDTO, sources: BookSourcesDTO) {
        self.book = book
        self.sources = sources

        var photos: [Int: BookImageDTO] = [:]
        for image in sources.photos where image.status == 0 && BookDay.isRealDay(BookDay.dayOf(image.photoDate)) {
            photos[image.id] = image
        }
        self.photos = photos
        var milestones: [Int: BookMilestoneDTO] = [:]
        for milestone in sources.milestones { milestones[milestone.id] = milestone }
        self.milestones = milestones

        people = sources.people
        var person: [Int: BookPersonDTO] = [:]
        for p in sources.people { person[p.id] = p }
        self.person = person

        categories = Set(book.categories.isEmpty ? BookCategory.all.map(\.value) : book.categories)
        match = book.match == "all" ? "all" : "any"
        untagged = Set(sources.untagged)

        start = BookDay.dayOf(book.startDate)
        end = BookDay.dayOf(book.endDate)
        firstYear = book.preset == BookPreset.firstYear
        limit = firstYear ? BookDay.addDays(end, 1) : end
        months = firstYear ? 12 : max(1, BookDay.monthIndex(BookDay.addDays(end, -1)) - BookDay.monthIndex(start) + 1)
    }

    var isMulti: Bool { people.count > 1 }

    func inRange(_ day: String) -> Bool {
        BookDay.isRealDay(day) && day >= start && day < limit
    }

    /// The month a record falls in: months of age in a first-year book (the birthday slot for the day itself), calendar months from the start otherwise.
    func slotOf(_ day: String) -> Int {
        if firstYear {
            if day >= end { return Self.birthdaySlot }
            if day < start { return 0 }
            return min(11, max(0, BookDay.monthsOld(start, day)))
        }
        return min(months - 1, max(0, BookDay.monthIndex(day) - BookDay.monthIndex(start)))
    }

    func itemDay(_ item: BookItemDTO) -> String? {
        switch item.itemKind {
        case .milestone: return milestones[item.sourceId].map { BookDay.dayOf($0.milestoneDate) }
        case .photo: return photos[item.sourceId].map { BookDay.dayOf($0.photoDate) }
        case nil: return nil
        }
    }

    /// Where an item belongs in a book about several people: shared moments together (0), everything about one person in that person's section.
    func sectionOf(_ item: BookItemDTO) -> Int {
        guard isMulti else { return 0 }
        if item.itemKind == .milestone {
            return milestones[item.sourceId]?.personId ?? 0
        }
        let tagged = sources.photoPeople[item.sourceId] ?? []
        return tagged.count == 1 ? tagged[0] : 0
    }

    // MARK: Words

    static func joinNames(_ names: [String]) -> String {
        if names.count <= 2 { return names.joined(separator: " and ") }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }

    private static let numberWords = [
        "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
        "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen",
    ]

    static func numberWord(_ n: Int) -> String {
        numberWords.indices.contains(n) ? numberWords[n] : String(n)
    }

    static func chapterTitle(from: Int, to: Int) -> String {
        if from == to { return from == 1 ? "One month" : "\(numberWord(from)) months" }
        return "\(numberWord(from)) to \(numberWord(to).lowercased()) months"
    }

    private static func isGeneratedTitle(_ image: BookImageDTO) -> Bool {
        let title = image.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty
            || title == image.originalFilename
            || title.range(of: "^(IMG|DSC|PXL|photo)[-_ ]?[0-9]", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func originalCaption(_ image: BookImageDTO) -> String {
        if !image.description.isEmpty { return image.description }
        return isGeneratedTitle(image) ? "" : image.title
    }

    func photoDetail(_ image: BookImageDTO) -> String {
        let day = BookDay.dayOf(image.photoDate)
        if isMulti {
            let names = (sources.photoPeople[image.id] ?? []).compactMap { person[$0]?.name }.filter { !$0.isEmpty }
            return names.count > 1 ? Self.joinNames(names) : ""
        }
        guard let subject = people.first else { return "" }
        let born = BookDay.dayOf(subject.birthday)
        return BookDay.isRealDay(born) && day >= born ? BookDay.photoAge(born, day) : ""
    }

    private func toPhoto(_ image: BookImageDTO, caption: String = "") -> BookPhoto {
        BookPhoto(
            id: image.id,
            width: image.width,
            height: image.height,
            day: BookDay.dayOf(image.photoDate),
            caption: caption.isEmpty ? Self.originalCaption(image) : caption,
            detail: photoDetail(image)
        )
    }

    private func toMoment(_ m: BookMilestoneDTO) -> BookMoment {
        let day = BookDay.dayOf(m.milestoneDate)
        let born = person[m.personId].map { BookDay.dayOf($0.birthday) } ?? ""
        return BookMoment(
            id: m.id,
            text: m.description.trimmingCharacters(in: .whitespacesAndNewlines),
            context: m.context.trimmingCharacters(in: .whitespacesAndNewlines),
            day: day,
            detail: BookDay.isRealDay(born) && day >= born ? BookDay.photoAge(born, day) : "",
            first: m.category == "first"
        )
    }

    // MARK: Blocks

    private struct Entry {
        let index: Int
        let item: BookItemDTO
        let day: String
    }

    private func chapterBlocks(_ entries: [Entry]) -> [BookBlock] {
        var blocks: [BookBlock] = []
        let loose = entries.filter { $0.item.itemKind == .photo }
        let hasMomentPhoto = entries.contains {
            $0.item.itemKind == .milestone && $0.item.photoId != 0 && photos[$0.item.photoId] != nil
        }
        var rest = entries[...]
        if let first = entries.first, first.item.itemKind == .photo, loose.count >= 3 || !hasMomentPhoto,
           let image = photos[first.item.sourceId] {
            blocks.append(.hero(toPhoto(image, caption: first.item.caption)))
            rest = entries.dropFirst()
        }

        var pendingPhotos: [BookPhoto] = []
        var pendingNotes: [BookMoment] = []
        func flushPhotos() {
            var i = 0
            while i < pendingPhotos.count {
                blocks.append(.photos(Array(pendingPhotos[i..<min(i + 4, pendingPhotos.count)])))
                i += 4
            }
            pendingPhotos = []
        }
        func flushNotes() {
            if !pendingNotes.isEmpty { blocks.append(.notes(pendingNotes)) }
            pendingNotes = []
        }

        for entry in rest {
            let item = entry.item
            if item.itemKind == .photo {
                flushNotes()
                if let image = photos[item.sourceId] {
                    pendingPhotos.append(toPhoto(image, caption: item.caption))
                }
                continue
            }
            guard let m = milestones[item.sourceId] else { continue }
            let moment = toMoment(m)
            let photo = item.photoId != 0 ? photos[item.photoId].map { toPhoto($0, caption: item.caption) } : nil
            var block: BookBlock?
            if m.category == "quote" {
                block = .quote(moment)
            } else if m.category == "artwork", let photo {
                block = .artwork(moment, photo: photo)
            } else if photo != nil || moment.first || moment.text.utf16.count > 160 || !moment.context.isEmpty || item.pinned {
                block = .moment(moment, photo: photo)
            }
            if let block {
                flushPhotos()
                flushNotes()
                blocks.append(block)
            } else {
                flushPhotos()
                pendingNotes.append(moment)
            }
        }
        flushPhotos()
        flushNotes()
        return blocks
    }

    // MARK: Growth

    private func growthPoints(type: Int, for subject: BookPersonDTO) -> [GrowthPoint] {
        let birthday = BookDay.dayOf(subject.birthday)
        let from = BookDay.isRealDay(birthday) ? birthday : start
        return sources.growthData
            .filter { $0.personId == subject.id && $0.measurementType == type && inRange(BookDay.dayOf($0.measurementDate)) }
            .map { g in
                let day = BookDay.dayOf(g.measurementDate)
                let months = BookDay.monthsOld(from, day)
                let exact = Double(BookDay.daysBetween(from, day)) / 30.4375
                return GrowthPoint(
                    day: day,
                    months: max(0, exact),
                    position: max(0, Double(BookDay.daysBetween(start, day)) / 30.4375),
                    value: g.value,
                    label: MeasurementConversion.formatLikeWeb(g.value, unit: unitFromString(g.unit), ageMonths: Double(months))
                )
            }
            .sorted { $0.day < $1.day }
    }

    private func growthBlock(for subject: BookPersonDTO) -> BookBlock? {
        let height = growthPoints(type: 0, for: subject)
        let weight = growthPoints(type: 1, for: subject)
        if height.count < 2 && weight.count < 2 { return nil }
        return .growth(height: height.count >= 2 ? height : [], weight: weight.count >= 2 ? weight : [])
    }

    /// Only a measurement taken on the birthday is "at birth"; one from a few days later says how many.
    private func birthFacts(for subject: BookPersonDTO) -> [String] {
        let birthDay = start
        var lines = ["Born \(BookDay.longDay(birthDay))"]
        func when(_ p: GrowthPoint) -> String {
            if p.day == birthDay { return "at birth" }
            let days = BookDay.daysBetween(birthDay, p.day)
            return "at \(days) \(days == 1 ? "day" : "days") old"
        }
        let cutoff = BookDay.addDays(birthDay, 3)
        if let weight = growthPoints(type: 1, for: subject).first(where: { $0.day <= cutoff }) {
            lines.append("Weighed \(weight.label) \(when(weight))")
        }
        if let height = growthPoints(type: 0, for: subject).first(where: { $0.day <= cutoff }) {
            lines.append("Measured \(height.label) long \(when(height))")
        }
        return lines
    }

    // MARK: Chapters

    /// Quiet months fold into their neighbours instead of standing alone as empty pages.
    static func groupMonths(_ weights: [Int], target: Int = 7, maxSpan: Int = 3) -> [[Int]] {
        var groups: [[Int]] = []
        var current: [Int] = []
        var weight = 0
        for month in weights.indices {
            if current.isEmpty && weights[month] == 0 { continue }
            current.append(month)
            weight += weights[month]
            if weight >= target || current.count >= maxSpan {
                groups.append(current)
                current = []
                weight = 0
            }
        }
        if !current.isEmpty {
            if weight < 2, let last = groups.last, last.count + current.count <= maxSpan + 1 {
                groups[groups.count - 1].append(contentsOf: current)
            } else {
                groups.append(current)
            }
        }
        return groups
            .map { group in
                var end = group.count
                while end > 0 && weights[group[end - 1]] == 0 { end -= 1 }
                return Array(group[0..<end])
            }
            .filter { !$0.isEmpty }
    }

    private func bySlot(_ entries: [Entry]) -> [Int: [Entry]] {
        var slots: [Int: [Entry]] = [:]
        for entry in entries {
            slots[slotOf(entry.day), default: []].append(entry)
        }
        return slots
    }

    private func slotWeights(_ slots: [Int: [Entry]], from: Int, count: Int) -> [Int] {
        (0..<count).map { i in
            let entries = slots[from + i] ?? []
            let milestones = entries.filter { $0.item.itemKind == .milestone }.count
            let weight = entries.reduce(0) { $0 + ($1.item.itemKind == .milestone ? 3 : 1) }
            return min(weight, milestones * 3 + 6)
        }
    }

    private func picked(_ group: [Int], offset: Int, from slots: [Int: [Entry]]) -> [Entry] {
        group.flatMap { slots[$0 + offset] ?? [] }.sorted { $0.index < $1.index }
    }

    private func calendarChapters(_ entries: [Entry], idPrefix: String) -> [BookChapter] {
        let slots = bySlot(entries)
        let base = BookDay.firstOfMonth(start)
        let maxSpan = max(3, Int((Double(months) / 12).rounded(.up)))
        return Self.groupMonths(slotWeights(slots, from: 0, count: months), target: 7, maxSpan: maxSpan).map { group in
            let from = group[0]
            let to = group[group.count - 1]
            let chosen = picked(group, offset: 0, from: slots)
            return BookChapter(
                id: "\(idPrefix)\(from)",
                title: BookDay.monthSpan(BookDay.shifted(base, months: from), BookDay.shifted(base, months: to)),
                dates: "",
                blocks: chapterBlocks(chosen),
                items: chosen.map(\.index)
            )
        }
    }

    private func ageLine(for subject: BookPersonDTO) -> String {
        let birthday = BookDay.dayOf(subject.birthday)
        guard BookDay.isRealDay(birthday), birthday <= start else { return "" }
        let from = BookDay.monthsOld(birthday, start) / 12
        let to = BookDay.monthsOld(birthday, BookDay.addDays(end, -1)) / 12
        if from == to { return from == 0 ? "Under one" : "Age \(from)" }
        return "Age \(from) to \(to)"
    }

    private func firstYearChapters(_ entries: [Entry]) -> [BookChapter] {
        guard let subject = people.first else { return [] }
        let slots = bySlot(entries)
        var chapters: [BookChapter] = []

        let welcomeEntries = slots[0] ?? []
        var welcome: [BookBlock] = []
        if !book.introduction.isEmpty {
            welcome.append(.letter(text: book.introduction, signature: ""))
        }
        welcome.append(.facts(birthFacts(for: subject)))
        welcome.append(contentsOf: chapterBlocks(welcomeEntries))
        chapters.append(BookChapter(
            id: "welcome",
            title: "Welcome to the world",
            dates: BookDay.monthSpan(start, BookDay.addDays(BookDay.shifted(start, months: 1), -1)),
            blocks: welcome,
            items: welcomeEntries.map(\.index)
        ))

        for group in Self.groupMonths(slotWeights(slots, from: 1, count: 11)) {
            let from = group[0] + 1
            let to = group[group.count - 1] + 1
            let chosen = picked(group, offset: 1, from: slots)
            chapters.append(BookChapter(
                id: "months-\(from)",
                title: Self.chapterTitle(from: from, to: to),
                dates: BookDay.monthSpan(BookDay.shifted(start, months: from), BookDay.addDays(BookDay.shifted(start, months: to + 1), -1)),
                blocks: chapterBlocks(chosen),
                items: chosen.map(\.index)
            ))
        }

        if book.showGrowth, let growth = growthBlock(for: subject) {
            chapters.append(BookChapter(id: "growth", title: "How you grew", dates: "", blocks: [growth], items: []))
        }

        let birthday = slots[Self.birthdaySlot] ?? []
        var closing = chapterBlocks(birthday)
        if !book.letter.isEmpty {
            closing.append(.letter(text: book.letter, signature: book.signature))
        }
        if !closing.isEmpty {
            chapters.append(BookChapter(
                id: "birthday",
                title: birthday.isEmpty ? "A letter for you" : "Turning one",
                dates: birthday.isEmpty ? "" : BookDay.longDay(end),
                blocks: closing,
                items: birthday.map(\.index)
            ))
        }
        return chapters
    }

    private func periodChapters(_ entries: [Entry]) -> [BookChapter] {
        var chapters: [BookChapter] = []
        if !book.introduction.isEmpty {
            chapters.append(BookChapter(id: "introduction", title: "", dates: "", blocks: [.letter(text: book.introduction, signature: "")], items: []))
        }
        let shared = entries.filter { sectionOf($0.item) == 0 }
        chapters.append(contentsOf: calendarChapters(shared, idPrefix: isMulti ? "together-" : "months-"))

        if isMulti {
            for subject in people {
                let own = entries.filter { sectionOf($0.item) == subject.id }.sorted { $0.index < $1.index }
                let growth = book.showGrowth ? growthBlock(for: subject) : nil
                if own.isEmpty && growth == nil { continue }
                var blocks = chapterBlocks(own)
                if let growth { blocks.append(growth) }
                chapters.append(BookChapter(
                    id: "person-\(subject.id)",
                    title: subject.name,
                    dates: ageLine(for: subject),
                    blocks: blocks,
                    items: own.map(\.index)
                ))
            }
        } else if book.showGrowth, let subject = people.first, let growth = growthBlock(for: subject) {
            chapters.append(BookChapter(id: "growth", title: "How \(subject.name) grew", dates: "", blocks: [growth], items: []))
        }

        if !book.letter.isEmpty {
            chapters.append(BookChapter(id: "letter", title: "", dates: "", blocks: [.letter(text: book.letter, signature: book.signature)], items: []))
        }
        return chapters
    }

    func assemble() -> AssembledBook {
        var missing = 0
        var entries: [Entry] = []
        for (index, item) in book.items.enumerated() {
            if let day = itemDay(item), BookDay.isRealDay(day) {
                entries.append(Entry(index: index, item: item, day: day))
            } else {
                missing += 1
            }
        }

        let isFirstYearBook = firstYear && people.count == 1
        let chapters = isFirstYearBook ? firstYearChapters(entries) : periodChapters(entries)
        let names = Self.joinNames(people.map(\.name))
        let title = book.title.isEmpty ? names : book.title
        return AssembledBook(
            name: names,
            title: title,
            dates: BookDay.bookDates(start: book.startDate, end: book.endDate),
            cover: photos[book.coverPhotoId].map { toPhoto($0) },
            chapters: chapters,
            ending: firstYear && !people.isEmpty ? "\(people[0].name), one year old" : title,
            missing: missing,
            growthAxis: isFirstYearBook
                ? GrowthAxis(span: 12, start: "birth", end: "one year")
                : GrowthAxis(span: max(1, Double(BookDay.daysBetween(start, end)) / 30.4375), start: BookDay.shortDay(start), end: BookDay.shortDay(BookDay.addDays(end, -1)))
        )
    }
}
