import Foundation

/// Global search over the SwiftData mirror, for when there is no signal. The server's search is the real one (meaning, access rules, activities, books); this is its word matching over what the phone holds.
/// The same understood filters as the server applies them (`matchPeople`, `matchMoments`, `matchPhotos` in backend/search.go), then prefix-of-word matching with every term required: people on name and relationship, moments on their text, photos on title and description.
/// Works on plain values rather than models, so it is tested without a store; ids are the records' local ids.
enum SearchLocal {
    static let peopleLimit = 8
    static let momentLimit = 20
    static let photoLimit = 12

    struct Person {
        let id: UUID
        var serverId: Int?
        let name: String
        var relationship: String?
        var birthday: Date?
    }

    struct Moment {
        let id: UUID
        /// The server id of who it's about. Someone still uploading has none, and can't be named in a query either.
        var personServerId: Int?
        let date: Date
        let category: MilestoneCategory
        let text: String
        var context = ""
        var tagNames: [String] = []
    }

    struct Photo {
        let id: UUID
        let date: Date
        let title: String
        var description = ""
        var peopleServerIds: [Int] = []
    }

    struct Result: Equatable {
        var people: [UUID] = []
        var moments: [UUID] = []
        /// Every moment that matched; `moments` holds the first `limit`.
        var momentCount = 0
        var photos: [UUID] = []
        var morePhotos = false

        var isEmpty: Bool { people.isEmpty && moments.isEmpty && photos.isEmpty }
    }

    static func search(
        _ parsed: ParsedSearch,
        people: [Person],
        moments: [Moment],
        photos: [Photo],
        limit: Int = momentLimit
    ) -> Result {
        let terms = SearchText.terms(parsed.text)
        let hasFilters = !parsed.personIds.isEmpty || parsed.ageFromMonth != nil || parsed.year != 0 || parsed.month != 0 || parsed.category != nil
        guard !terms.isEmpty || hasFilters else { return Result() }

        var birthdays: [Int: Date] = [:]
        for person in people {
            if let id = person.serverId, let birthday = person.birthday {
                birthdays[id] = birthday
            }
        }
        func ageMatches(_ personId: Int, at date: Date) -> Bool {
            guard let from = parsed.ageFromMonth, let to = parsed.ageToMonth else { return true }
            guard let birthday = birthdays[personId] else { return false }
            return (from..<to).contains(ageInMonths(birthday: birthday, at: date))
        }

        var result = Result()

        // People: those named, then those whose name or relationship the words start.
        var addedPeople = Set<UUID>()
        func addPerson(_ person: Person) {
            guard result.people.count < peopleLimit, addedPeople.insert(person.id).inserted else { return }
            result.people.append(person.id)
        }
        for id in parsed.personIds {
            if let person = people.first(where: { $0.serverId == id }) {
                addPerson(person)
            }
        }
        if !terms.isEmpty {
            for person in people where SearchText.matches(terms, words: SearchText.words(person.name, person.relationship ?? "")) {
                addPerson(person)
            }
        }

        // Moments: the filters, then text matches in the description ahead of matches elsewhere, each newest first.
        let candidates = moments.filter { moment in
            if !parsed.personIds.isEmpty {
                guard let id = moment.personServerId, parsed.personIds.contains(id) else { return false }
            }
            if parsed.ageFromMonth != nil {
                guard let id = moment.personServerId, ageMatches(id, at: moment.date) else { return false }
            }
            if let category = parsed.category, moment.category != category {
                return false
            }
            return dateMatches(parsed, moment.date)
        }
        var ranked: [Moment]
        if terms.isEmpty {
            ranked = newestFirst(candidates)
        } else {
            var inText: [Moment] = []
            var elsewhere: [Moment] = []
            for moment in candidates {
                if SearchText.matches(terms, words: SearchText.words(moment.text)) {
                    inText.append(moment)
                } else if SearchText.matches(terms, words: SearchText.words(of: [moment.text, moment.context, moment.category.rawValue] + moment.tagNames)) {
                    elsewhere.append(moment)
                }
            }
            ranked = newestFirst(inText) + newestFirst(elsewhere)
        }
        result.momentCount = ranked.count
        result.moments = ranked.prefix(limit).map(\.id)

        // Photos: the filters, someone from every named group in it, then the words in its title or description, newest first.
        var groups = parsed.personGroups
        if groups.isEmpty, !parsed.personIds.isEmpty {
            groups = [parsed.personIds]
        }
        let matchingPhotos = photos.filter { photo in
            guard dateMatches(parsed, photo.date) else { return false }
            guard groups.allSatisfy({ group in group.contains { photo.peopleServerIds.contains($0) } }) else { return false }
            if parsed.ageFromMonth != nil {
                let subjects = parsed.personIds.isEmpty ? photo.peopleServerIds : photo.peopleServerIds.filter { parsed.personIds.contains($0) }
                guard subjects.contains(where: { ageMatches($0, at: photo.date) }) else { return false }
            }
            return terms.isEmpty || SearchText.matches(terms, words: SearchText.words(photo.title, photo.description))
        }
        .sorted { $0.date > $1.date }
        result.photos = matchingPhotos.prefix(photoLimit).map(\.id)
        result.morePhotos = matchingPhotos.count > photoLimit

        return result
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// Whole months from `birthday` to `date`, by their record days — `ageInMonths` in backend/milestone_analysis.go.
    static func ageInMonths(birthday: Date, at date: Date) -> Int {
        let born = utc.dateComponents([.year, .month, .day], from: birthday)
        let at = utc.dateComponents([.year, .month, .day], from: date)
        var months = ((at.year ?? 0) - (born.year ?? 0)) * 12 + (at.month ?? 0) - (born.month ?? 0)
        if (at.day ?? 0) < (born.day ?? 0) {
            months -= 1
        }
        return months
    }

    private static func dateMatches(_ parsed: ParsedSearch, _ date: Date) -> Bool {
        let day = utc.dateComponents([.year, .month], from: date)
        return (parsed.year == 0 || day.year == parsed.year) && (parsed.month == 0 || day.month == parsed.month)
    }

    private static func newestFirst(_ moments: [Moment]) -> [Moment] {
        moments.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset }
            .map(\.element)
    }
}
