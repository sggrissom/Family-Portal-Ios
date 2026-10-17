import Foundation
import Testing
@testable import Family_Portal_Ios

/// A copy of `TestParseSearchQuery` in backend/search_query_test.go, so the phone understands a query the way the server does. When a case changes there, change it here too.
@MainActor
@Suite("Search query")
struct SearchQueryTests {

    private let people: [SearchQuery.Person] = [
        .init(id: 1, name: "Ada Grissom", relationship: "daughter"),
        .init(id: 2, name: "Ben Grissom", relationship: "son"),
        .init(id: 3, name: "Ada Smith", relationship: "niece"),
        .init(id: 4, name: "Mary Jones", relationship: "grandmother"),
        .init(id: 5, name: "Ruth Jones", relationship: "grandmother"),
        .init(id: 6, name: "Joe Grissom", relationship: "father"),
        .init(id: 7, name: "Zoë Martin"),
        .init(id: 8, name: "Baby Grissom", isPregnancy: true),
        .init(id: 9, name: "May Lee"),
    ]

    private let tags: [SearchQuery.Tag] = [
        .init(id: 10, name: "Beach"),
        .init(id: 11, name: "First day of school"),
        .init(id: 12, name: "Disney World"),
        .init(id: 13, name: "Ben"),
    ]

    private var now: Date {
        Date(timeIntervalSince1970: 1_791_936_000) // 2026-10-14 UTC
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    struct Want: Equatable, CustomStringConvertible {
        var people: [Int] = []
        var groups: [[Int]] = []
        var age: [Int]? = nil
        var ageLabel = ""
        var year = 0
        var month = 0
        var category: String = ""
        var tags: [Int] = []
        var text = ""

        var description: String {
            "people=\(people) groups=\(groups) age=\(age.map(\.description) ?? "nil") ageLabel=\(ageLabel) year=\(year) month=\(month) category=\(category) tags=\(tags) text=\(text)"
        }
    }

    struct Case {
        let query: String
        var ignore: Set<SearchIgnore> = []
        let want: Want
    }

    private let cases: [Case] = [
        Case(query: "", want: Want()),
        Case(query: "first steps", want: Want(text: "first steps")),
        Case(query: "walk", want: Want(text: "walk")),

        Case(query: "ben", want: Want(people: [2], groups: [[2]])),
        Case(query: "Ben's first steps", want: Want(people: [2], groups: [[2]], text: "first steps")),
        Case(query: "ben grissom", want: Want(people: [2], groups: [[2]])),
        Case(query: "ada", want: Want(people: [1, 3], groups: [[1, 3]])),
        Case(query: "ada grissom", want: Want(people: [1], groups: [[1]])),
        Case(query: "ada and ben", want: Want(people: [1, 3, 2], groups: [[1, 3], [2]])),
        Case(query: "zoe", want: Want(people: [7], groups: [[7]])),
        Case(query: "Zoë's bike", want: Want(people: [7], groups: [[7]], text: "bike")),
        Case(query: "baby grissom", want: Want(age: [0, 12], ageLabel: "baby", text: "grissom")),

        Case(query: "dad", want: Want(people: [6], groups: [[6]])),
        Case(query: "daddy's birthday", want: Want(people: [6], groups: [[6]], text: "birthday")),
        Case(query: "daughter", want: Want(people: [1], groups: [[1]])),
        Case(query: "grandma", want: Want(text: "grandma")),

        Case(query: "ben at 2", want: Want(people: [2], groups: [[2]], age: [24, 36], ageLabel: "age 2")),
        Case(query: "ben 2", want: Want(people: [2], groups: [[2]], age: [24, 36], ageLabel: "age 2")),
        Case(query: "ben age 2", want: Want(people: [2], groups: [[2]], age: [24, 36], ageLabel: "age 2")),
        Case(query: "ben 2 years", want: Want(people: [2], groups: [[2]], age: [24, 36], ageLabel: "age 2")),
        Case(query: "ben 2yo", want: Want(people: [2], groups: [[2]], age: [24, 36], ageLabel: "age 2")),
        Case(query: "ben 2 years old", want: Want(people: [2], groups: [[2]], age: [24, 36], ageLabel: "age 2")),
        Case(query: "ben when he was 3 years old", want: Want(people: [2], groups: [[2]], age: [36, 48], ageLabel: "age 3", text: "he")),
        Case(query: "ben 18 months", want: Want(people: [2], groups: [[2]], age: [18, 19], ageLabel: "18 months")),
        Case(query: "ben 18mo", want: Want(people: [2], groups: [[2]], age: [18, 19], ageLabel: "18 months")),
        Case(query: "ben 18m", want: Want(people: [2], groups: [[2]], age: [18, 19], ageLabel: "18 months")),
        Case(query: "1 month", want: Want(age: [1, 2], ageLabel: "1 month")),
        Case(query: "newborn ben", want: Want(people: [2], groups: [[2]], age: [0, 1], ageLabel: "newborn")),
        Case(query: "baby bath", want: Want(age: [0, 12], ageLabel: "baby", text: "bath")),
        Case(query: "age 4 party", want: Want(age: [48, 60], ageLabel: "age 4", text: "party")),
        Case(query: "3 years", want: Want(age: [36, 48], ageLabel: "age 3")),

        Case(query: "2", want: Want(text: "2")),
        Case(query: "at 2", want: Want(text: "2")),
        Case(query: "25 pumpkins", want: Want(text: "25 pumpkins")),
        Case(query: "ben 25 pumpkins", want: Want(people: [2], groups: [[2]], text: "25 pumpkins")),
        Case(query: "ben 2 3", want: Want(people: [2], groups: [[2]], age: [24, 36], ageLabel: "age 2", text: "3")),

        Case(query: "beach 2024", want: Want(year: 2024, tags: [10], text: "beach")),
        Case(query: "1899", want: Want(text: "1899")),
        Case(query: "ben 2024", want: Want(people: [2], groups: [[2]], year: 2024)),
        Case(query: "june", want: Want(month: 6)),
        Case(query: "june 2024", want: Want(year: 2024, month: 6)),
        Case(query: "Christmas December 2023", want: Want(year: 2023, month: 12, text: "Christmas")),
        Case(query: "this year", want: Want(year: 2026)),
        Case(query: "last year", want: Want(year: 2025)),
        Case(query: "may", want: Want(people: [9], groups: [[9]])),

        Case(query: "quote", want: Want(category: "quote")),
        Case(query: "ben quotes", want: Want(people: [2], groups: [[2]], category: "quote")),
        Case(query: "drawing of a dog", want: Want(category: "artwork", text: "dog")),
        Case(query: "interview answers", want: Want(category: "interview", text: "answers")),

        Case(query: "first day of school", want: Want(tags: [11], text: "first day school")),
        Case(query: "disney world 2023", want: Want(year: 2023, tags: [12], text: "disney world")),
        Case(query: "disney", want: Want(text: "disney")),
        Case(query: "photos of the beach", want: Want(tags: [10], text: "beach")),

        Case(query: "ben at 2", ignore: [.age], want: Want(people: [2], groups: [[2]], text: "2")),
        Case(query: "ben at 2", ignore: [.person], want: Want(tags: [13], text: "ben 2")),
        Case(query: "ben at 2", ignore: [.person, .tag], want: Want(text: "ben 2")),
        Case(query: "beach 2024", ignore: [.date], want: Want(tags: [10], text: "beach 2024")),
        Case(query: "beach 2024", ignore: [.tag], want: Want(year: 2024, text: "beach")),
        Case(query: "quotes", ignore: [.category], want: Want(text: "quotes")),
    ]

    @Test("Every case in the Go table parses the same way")
    func goTable() {
        for c in cases {
            let parsed = SearchQuery.parse(c.query, people: people, tags: tags, now: now, calendar: utc, ignore: c.ignore)
            let age = parsed.ageFromMonth.flatMap { from in parsed.ageToMonth.map { [from, $0] } }
            let got = Want(
                people: parsed.personIds, groups: parsed.personGroups, age: age, ageLabel: parsed.ageLabel,
                year: parsed.year, month: parsed.month, category: parsed.category?.rawValue ?? "",
                tags: parsed.tagIds, text: parsed.text
            )
            #expect(got == c.want, "\(c.query) ignore=\(c.ignore.map(\.rawValue).sorted())")
        }
    }

    @Test("A token is folded, with punctuation and a possessive removed")
    func tokens() {
        #expect(SearchQuery.token("Zoë's") == "zoe")
        #expect(SearchQuery.token("“Ben’s”") == "ben")
        #expect(SearchQuery.token("(beach),") == "beach")
        #expect(SearchQuery.token("...") == "")
    }
}
