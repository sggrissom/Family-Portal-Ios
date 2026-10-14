import Foundation

/// A kind of understanding a search can switch off. Removing a chip re-sends the query with its kind in `ignore`, and those words go back to being text.
nonisolated enum SearchIgnore: String, Sendable, CaseIterable {
    case person
    case age
    case date
    case category
    case tag
}

/// What a query was understood to mean — `parsedSearch` in backend/search_query.go.
struct ParsedSearch: Equatable {
    var personIds: [Int] = []
    /// One group per name in the query. A shared first name is a group of everyone with it; a photo must show someone from every group.
    var personGroups: [[Int]] = []
    /// Months of age, `[from, to)`.
    var ageFromMonth: Int?
    var ageToMonth: Int?
    var ageLabel = ""
    var year = 0
    var month = 0
    var category: MilestoneCategory?
    /// Recognised, but not consumed: their words stay in `text`.
    var tagIds: [Int] = []
    var text = ""
}

/// A Swift port of `parseSearchQuery` (backend/search_query.go). The server parses every query it runs; the phone parses only for the offline pass, and to keep the chips steady while a request is in flight.
/// `SearchQueryTests` holds a copy of the Go test table. When either side changes, change both.
/// Default (MainActor) isolation, because categories map onto `MilestoneCategory`.
enum SearchQuery {

    /// Who can be named in a query. Ids are server ids, as in `SearchUnderstoodDTO.personIds`.
    struct Person {
        let id: Int
        let name: String
        /// How this person relates to the viewer, worded by the server ("daughter").
        var relationship: String?
        var isPregnancy = false
    }

    struct Tag {
        let id: Int
        let name: String
    }

    static let relationAliases: [String: String] = [
        "mom": "mother", "mum": "mother", "mommy": "mother", "mummy": "mother", "mama": "mother", "momma": "mother",
        "dad": "father", "daddy": "father", "papa": "father",
        "grandma": "grandmother", "granny": "grandmother", "nana": "grandmother", "grandmom": "grandmother",
        "grandpa": "grandfather", "granddad": "grandfather", "grandad": "grandfather",
        "bro": "brother", "sis": "sister",
    ]

    static let months: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7,
        "august": 8, "september": 9, "sept": 9, "october": 10, "november": 11, "december": 12,
    ]

    static let categoryWords: [String: MilestoneCategory] = [
        "development": .development,
        "behavior": .behavior, "behaviour": .behavior,
        "health": .health,
        "achievement": .achievement, "achievements": .achievement,
        "quote": .quote, "quotes": .quote, "saying": .quote, "sayings": .quote,
        "artwork": .artwork, "artworks": .artwork, "drawing": .artwork, "drawings": .artwork,
        "interview": .interview, "interviews": .interview,
    ]

    private static let ageYearUnits: Set<String> = ["y", "yo", "y/o", "yr", "yrs", "year", "years"]
    private static let ageMonthUnits: Set<String> = ["m", "mo", "mos", "month", "months"]

    /// Pulls people, an age, a date and a category out of a search, leaving the rest as free text. Tag names are recognised but stay in the text, since text matching already covers tag names. Kinds in `ignore` are left as text.
    static func parse(
        _ query: String,
        people: [Person],
        tags: [Tag],
        now: Date = .now,
        calendar: Calendar = .current,
        ignore: Set<SearchIgnore> = []
    ) -> ParsedSearch {
        let raw = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let tokens = raw.map(token)
        var used = Array(repeating: false, count: tokens.count)
        var keep = Array(repeating: false, count: tokens.count)
        var out = ParsedSearch()

        let phrases = self.phrases(people: people, tags: tags)
        var i = 0
        while i < tokens.count {
            defer { i += 1 }
            guard !tokens[i].isEmpty, let phrase = longestPhrase(at: i, in: phrases, tokens: tokens, used: used, ignore: ignore) else {
                continue
            }
            for j in phrase.words.indices {
                used[i + j] = true
                keep[i + j] = phrase.tag
            }
            if phrase.tag {
                for id in phrase.ids where !out.tagIds.contains(id) {
                    out.tagIds.append(id)
                }
            } else {
                out.personGroups.append(phrase.ids)
                for id in phrase.ids where !out.personIds.contains(id) {
                    out.personIds.append(id)
                }
            }
            i += phrase.words.count - 1
        }

        var haveAge = false
        for i in tokens.indices where !used[i] {
            let token = tokens[i]
            let next = i + 1 < tokens.count && !used[i + 1] ? tokens[i + 1] : ""

            if !ignore.contains(.date), out.year == 0 {
                if (token == "this" || token == "last"), next == "year" {
                    out.year = calendar.component(.year, from: now) - (token == "last" ? 1 : 0)
                    used[i] = true
                    used[i + 1] = true
                    continue
                }
                if let year = yearOf(token) {
                    out.year = year
                    used[i] = true
                    continue
                }
            }
            if !ignore.contains(.date), out.month == 0, let month = months[token] {
                out.month = month
                used[i] = true
                if out.year == 0, let year = yearOf(next) {
                    out.year = year
                    used[i + 1] = true
                }
                continue
            }
            if !ignore.contains(.age), !haveAge,
               case let (found, span)? = age(at: i, tokens: tokens, used: used, personNamed: !out.personIds.isEmpty) {
                out.ageFromMonth = found.from
                out.ageToMonth = found.to
                out.ageLabel = found.label
                haveAge = true
                for j in i..<(i + span) {
                    used[j] = true
                }
                continue
            }
            if !ignore.contains(.category), out.category == nil, let category = categoryWords[token] {
                out.category = category
                used[i] = true
                continue
            }
        }

        var text: [String] = []
        for (i, word) in raw.enumerated()
        where (!used[i] || keep[i]) && !tokens[i].isEmpty && !SearchText.fillerWords.contains(tokens[i]) {
            text.append(word)
        }
        out.text = text.joined(separator: " ")
        return out
    }

    // MARK: - Tokens

    private static let edgePunctuation = CharacterSet(charactersIn: ".,!?;:()[]{}\"'“”‘’")

    /// A word of the query, folded, without surrounding punctuation or a possessive.
    static func token(_ word: String) -> String {
        var w = SearchText.fold(word).trimmingCharacters(in: edgePunctuation)
        for suffix in ["'s", "’s"] where w.hasSuffix(suffix) {
            w.removeLast(suffix.count)
        }
        return w.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
    }

    private static func yearOf(_ token: String) -> Int? {
        guard token.utf8.count == 4, let n = Int(token), (1900...2100).contains(n) else { return nil }
        return n
    }

    // MARK: - Names

    private struct Phrase {
        let words: [String]
        var ids: [Int]
        let tag: Bool
    }

    /// Every way a person or a tag can be named: a person's full name and first name, and a relationship label (or an alias of one) that fits exactly one person.
    private static func phrases(people: [Person], tags: [Tag]) -> [Phrase] {
        var out: [Phrase] = []
        var index: [String: Int] = [:]
        func add(_ name: String, _ id: Int, tag: Bool) {
            let words = SearchText.fold(name).split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { return }
            let key = "\(tag)|\(words.joined(separator: " "))"
            if let at = index[key] {
                if !out[at].ids.contains(id) {
                    out[at].ids.append(id)
                }
            } else {
                index[key] = out.count
                out.append(Phrase(words: words, ids: [id], tag: tag))
            }
        }

        var byRelation: [String: [Int]] = [:]
        for person in people where !person.isPregnancy {
            guard let first = person.name.split(whereSeparator: \.isWhitespace).first else { continue }
            add(person.name, person.id, tag: false)
            add(String(first), person.id, tag: false)
            let label = SearchText.fold(person.relationship ?? "")
            if !label.isEmpty, !byRelation[label, default: []].contains(person.id) {
                byRelation[label, default: []].append(person.id)
            }
        }
        for (label, ids) in byRelation.sorted(by: { $0.key < $1.key }) where ids.count == 1 {
            add(label, ids[0], tag: false)
            for (alias, canonical) in relationAliases.sorted(by: { $0.key < $1.key }) where canonical == label {
                add(alias, ids[0], tag: false)
            }
        }
        for tag in tags {
            add(tag.name, tag.id, tag: true)
        }
        return out
    }

    /// The longest name starting at token `i`. At equal length a person beats a tag, and otherwise the first listed wins.
    private static func longestPhrase(at i: Int, in phrases: [Phrase], tokens: [String], used: [Bool], ignore: Set<SearchIgnore>) -> Phrase? {
        var best: Phrase?
        for phrase in phrases {
            if ignore.contains(phrase.tag ? .tag : .person) {
                continue
            }
            let bestCount = best?.words.count ?? 0
            if i + phrase.words.count > tokens.count || phrase.words.count < bestCount {
                continue
            }
            if let best, phrase.words.count == best.words.count, phrase.tag || !best.tag {
                continue
            }
            let matches = phrase.words.indices.allSatisfy { j in !used[i + j] && tokens[i + j] == phrase.words[j] }
            if matches {
                best = phrase
            }
        }
        return best
    }

    // MARK: - Ages

    private struct Age {
        let from: Int
        let to: Int
        let label: String

        static func years(_ n: Int) -> Age {
            Age(from: n * 12, to: n * 12 + 12, label: "age \(n)")
        }

        static func months(_ n: Int) -> Age {
            Age(from: n, to: n + 1, label: n == 1 ? "1 month" : "\(n) months")
        }
    }

    /// An age starting at token `i`, and how many tokens it spans. A number with no unit is an age only after "age", or when a person is named and the number is under 25.
    private static func age(at i: Int, tokens: [String], used: [Bool], personNamed: Bool) -> (Age, Int)? {
        func free(_ j: Int) -> Bool { j < tokens.count && !used[j] }
        switch tokens[i] {
        case "newborn", "newborns":
            return (Age(from: 0, to: 1, label: "newborn"), 1)
        case "baby", "babies":
            return (Age(from: 0, to: 12, label: "baby"), 1)
        default:
            break
        }

        let start = i
        var at = i
        var explicit = false
        switch tokens[at] {
        case "age", "aged":
            explicit = true
            at += 1
        case "at":
            at += 1
        default:
            break
        }
        guard free(at) else { return nil }

        let age: Age
        var end = at + 1
        if let n = Int(tokens[at]) {
            if free(end), ageYearUnits.contains(tokens[end]), n <= 120 {
                age = .years(n)
                end += 1
            } else if free(end), ageMonthUnits.contains(tokens[end]), n <= 1500 {
                age = .months(n)
                end += 1
            } else if n < 25, explicit || personNamed {
                age = .years(n)
            } else {
                return nil
            }
        } else if case let (n, unit)? = numberWithUnit(tokens[at]) {
            if ageYearUnits.contains(unit), n <= 120 {
                age = .years(n)
            } else if ageMonthUnits.contains(unit), n <= 1500 {
                age = .months(n)
            } else {
                return nil
            }
        } else {
            return nil
        }
        if free(end), tokens[end] == "old" {
            end += 1
        }
        return (age, end - start)
    }

    /// `2yo`, `18mo`: one to four ASCII digits, then a unit of `a`–`z` and `/` (`^(\d{1,4})([a-z/]+)$`).
    private static func numberWithUnit(_ token: String) -> (Int, String)? {
        let scalars = Array(token.unicodeScalars)
        let digits = scalars.prefix { ("0"..."9").contains($0) }
        let unit = scalars.dropFirst(digits.count)
        guard (1...4).contains(digits.count), !unit.isEmpty,
              unit.allSatisfy({ ("a"..."z").contains($0) || $0 == "/" }),
              let n = Int(String(String.UnicodeScalarView(digits))) else { return nil }
        return (n, String(String.UnicodeScalarView(unit)))
    }
}
