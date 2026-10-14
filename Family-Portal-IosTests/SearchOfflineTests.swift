import Foundation
import Testing
@testable import Family_Portal_Ios

/// The offline pass over the mirror (`SearchLocal`) and recent searches.
@MainActor
@Suite("Search offline")
struct SearchOfflineTests {

    private static func day(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string)!
    }

    private let ada = SearchLocal.Person(id: UUID(), serverId: 1, name: "Ada Grissom", relationship: "daughter", birthday: day("2020-03-15"))
    private let ben = SearchLocal.Person(id: UUID(), serverId: 2, name: "Ben Grissom", relationship: "son", birthday: day("2022-07-01"))
    private let grandma = SearchLocal.Person(id: UUID(), serverId: nil, name: "Mary Jones", relationship: "grandmother")

    private var people: [SearchLocal.Person] { [ada, ben, grandma] }

    private var queryPeople: [SearchQuery.Person] {
        people.compactMap { person in
            person.serverId.map { SearchQuery.Person(id: $0, name: person.name, relationship: person.relationship) }
        }
    }

    private func search(
        _ query: String,
        moments: [SearchLocal.Moment] = [],
        photos: [SearchLocal.Photo] = [],
        limit: Int = SearchLocal.momentLimit
    ) -> SearchLocal.Result {
        let parsed = SearchQuery.parse(query, people: queryPeople, tags: [])
        return SearchLocal.search(parsed, people: people, moments: moments, photos: photos, limit: limit)
    }

    private func moment(_ text: String, person: SearchLocal.Person, on date: String, category: MilestoneCategory = .development, context: String = "", tags: [String] = []) -> SearchLocal.Moment {
        SearchLocal.Moment(id: UUID(), personServerId: person.serverId, date: Self.day(date), category: category, text: text, context: context, tagNames: tags)
    }

    // MARK: - People

    @Test("People match by name or relationship prefix, named ones first")
    func people() {
        #expect(search("gran").people == [grandma.id])
        #expect(search("Gris").people == [ada.id, ben.id])
        #expect(search("ben").people == [ben.id])
        #expect(search("daugh").people == [ada.id])
        #expect(search("zzz").people.isEmpty)
    }

    @Test("Nothing to match and no filters finds nothing")
    func emptyQuery() {
        #expect(search("").isEmpty)
        #expect(search("the of").isEmpty)
    }

    // MARK: - Moments

    @Test("Every word must start a word of the moment, accents and case aside")
    func momentPrefixMatching() {
        let walked = moment("Walked to the café", person: ada, on: "2021-05-01")
        let ran = moment("Ran to the park", person: ben, on: "2023-05-01")

        #expect(search("walk", moments: [walked, ran]).moments == [walked.id])
        #expect(search("CAFE walk", moments: [walked, ran]).moments == [walked.id])
        #expect(search("alked", moments: [walked, ran]).moments.isEmpty)
        #expect(search("walk park", moments: [walked, ran]).moments.isEmpty)
    }

    @Test("Matches in the text rank ahead of matches in context or tags, each newest first")
    func momentRanking() {
        let older = moment("Beach day", person: ada, on: "2021-06-01")
        let newer = moment("Beach again", person: ada, on: "2022-06-01")
        let tagged = moment("Sandcastles", person: ada, on: "2023-06-01", tags: ["Beach"])
        let quoted = moment("Look at the waves!", person: ada, on: "2024-06-01", category: .quote, context: "At the beach")

        let result = search("beach", moments: [older, tagged, newer, quoted])

        #expect(result.moments == [newer.id, older.id, quoted.id, tagged.id])
        #expect(result.momentCount == 4)
    }

    @Test("Person, age, date and category filters apply as the server applies them")
    func momentFilters() {
        let adaAtOne = moment("First steps", person: ada, on: "2021-04-01")
        let adaAtThree = moment("First bike", person: ada, on: "2023-06-01")
        let benAtOne = moment("First steps", person: ben, on: "2023-08-01")
        let quote = moment("Moon is following us", person: ben, on: "2024-06-10", category: .quote)
        let all = [adaAtOne, adaAtThree, benAtOne, quote]

        #expect(search("ada", moments: all).moments == [adaAtThree.id, adaAtOne.id])
        #expect(search("ada first", moments: all).moments == [adaAtThree.id, adaAtOne.id])
        #expect(search("ben at 1", moments: all).moments == [quote.id, benAtOne.id])
        #expect(search("first steps 2023", moments: all).moments == [benAtOne.id])
        #expect(search("june", moments: all).moments == [quote.id, adaAtThree.id])
        #expect(search("quotes", moments: all).moments == [quote.id])
    }

    @Test("The limit caps the list but not the count")
    func momentLimit() {
        let moments = (1...5).map { moment("Swim \($0)", person: ada, on: "2022-0\($0)-01") }
        let result = search("swim", moments: moments, limit: 2)
        #expect(result.moments.count == 2)
        #expect(result.momentCount == 5)
    }

    // MARK: - Photos

    @Test("Photos match on title and description, with someone from every named group in them")
    func photos() {
        let both = SearchLocal.Photo(id: UUID(), date: Self.day("2024-07-04"), title: "Fireworks", peopleServerIds: [1, 2])
        let adaOnly = SearchLocal.Photo(id: UUID(), date: Self.day("2024-07-05"), title: "Lake", description: "Fireworks over the water", peopleServerIds: [1])
        let nobody = SearchLocal.Photo(id: UUID(), date: Self.day("2023-01-01"), title: "Snow")

        #expect(search("firework", photos: [both, adaOnly, nobody]).photos == [adaOnly.id, both.id])
        #expect(search("ada and ben", photos: [both, adaOnly, nobody]).photos == [both.id])
        #expect(search("ada 2024", photos: [both, adaOnly, nobody]).photos == [adaOnly.id, both.id])
        #expect(search("snow 2024", photos: [both, adaOnly, nobody]).photos.isEmpty)
    }

    @Test("A photo's age is the named person's, or anyone's in it when no one is named")
    func photoAges() {
        let benAtTwo = SearchLocal.Photo(id: UUID(), date: Self.day("2024-08-01"), title: "Party", peopleServerIds: [1, 2])

        #expect(search("ben 2 party", photos: [benAtTwo]).photos == [benAtTwo.id])
        #expect(search("ada 2 party", photos: [benAtTwo]).photos.isEmpty)
        #expect(search("age 4 party", photos: [benAtTwo]).photos == [benAtTwo.id])
    }

    @Test("More than a strip's worth says there are more")
    func morePhotos() {
        let photos = (0..<13).map { SearchLocal.Photo(id: UUID(), date: Self.day("2024-01-01").addingTimeInterval(Double($0) * 86_400), title: "Snow \($0)") }
        let result = search("snow", photos: photos)
        #expect(result.photos.count == SearchLocal.photoLimit)
        #expect(result.photos.first == photos.last?.id)
        #expect(result.morePhotos)
    }

    @Test("Age in months counts whole months by record day")
    func ageInMonths() {
        let born = Self.day("2020-03-15")
        #expect(SearchLocal.ageInMonths(birthday: born, at: Self.day("2020-04-14")) == 0)
        #expect(SearchLocal.ageInMonths(birthday: born, at: Self.day("2020-04-15")) == 1)
        #expect(SearchLocal.ageInMonths(birthday: born, at: Self.day("2022-03-15")) == 24)
    }

    // MARK: - Recent searches

    @Test("A search goes to the front, replacing a copy that differs only in case or accents")
    func recentOrder() {
        var recent = RecentSearches.adding("beach", to: [])
        recent = RecentSearches.adding("Ada at 2", to: recent)
        recent = RecentSearches.adding("  BEACH  ", to: recent)
        recent = RecentSearches.adding("café", to: recent)
        recent = RecentSearches.adding("Cafe", to: recent)
        #expect(recent == ["Cafe", "BEACH", "Ada at 2"])
        #expect(RecentSearches.adding("   ", to: recent) == recent)
    }

    @Test("Only the last eight are kept")
    func recentLimit() {
        let recent = (1...10).reduce([String]()) { RecentSearches.adding("query \($1)", to: $0) }
        #expect(recent.count == RecentSearches.limit)
        #expect(recent.first == "query 10")
        #expect(recent.last == "query 3")
    }

    @Test("Recent searches round-trip through defaults and clear")
    func recentStorage() throws {
        let defaults = try #require(UserDefaults(suiteName: "SearchOfflineTests-\(UUID().uuidString)"))
        #expect(RecentSearches.load(from: defaults).isEmpty)
        RecentSearches.save(["ada", "beach"], to: defaults)
        #expect(RecentSearches.load(from: defaults) == ["ada", "beach"])
        RecentSearches.clear(in: defaults)
        #expect(RecentSearches.load(from: defaults).isEmpty)
    }

    // MARK: - The model offline

    @Test("Offline, nothing is sent, and the signal coming back asks again")
    func offlineModel() async throws {
        var sent: [String] = []
        let model = SearchModel(debounce: .zero) { request in
            sent.append(request.query)
            return try APIClient.decode(SearchResponseDTO.self, from: Fixture.data(["query": request.query]))
        }
        model.isOffline = true

        await model.search("ada")
        #expect(sent.isEmpty)
        #expect(model.currentResponse == nil)
        #expect(!model.isCurrent)

        model.isOffline = false
        await model.retry()
        #expect(sent == ["ada"])
        #expect(model.currentResponse?.query == "ada")
    }
}
