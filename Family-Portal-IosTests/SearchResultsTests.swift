import Foundation
import Testing
@testable import Family_Portal_Ios

/// Payloads shaped field for field on `SearchResponse` in backend/search.go, and what the search screen makes of them.
@MainActor
@Suite("Search results")
struct SearchResultsTests {

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try APIClient.decode(T.self, from: Fixture.data(object))
    }

    @Test("A full response decodes")
    func fullResponse() throws {
        let payload: [String: Any] = [
            "query": "ada beach 2024",
            "understood": [
                "personIds": [4],
                "ageFromMonth": 24,
                "ageToMonth": 36,
                "ageLabel": "age 2",
                "year": 2024,
                "month": 6,
                "category": "quote",
                "tagIds": [10],
                "text": "beach",
            ],
            "people": [Fixture.person(id: 4, name: "Ada")],
            "moments": [Fixture.milestone(id: 60, personId: 4, description: "Beach day")],
            "momentCount": 31,
            "interviews": [["id": 5, "personId": 4, "date": "2025-06-01T00:00:00Z", "status": "complete"]],
            "photos": [["image": Fixture.image(id: 51), "people": [Fixture.person(id: 4)]]],
            "morePhotos": true,
            "tags": [Fixture.tag(id: 10, name: "Beach")],
            "places": [["key": "f3", "name": "Beach house", "familyPlaceId": 3, "latitude": 1.5, "longitude": -2.5]],
            "activities": [
                ["kind": "activity", "id": 1, "name": "Swim", "detail": "", "date": "0001-01-01T00:00:00Z"],
                ["kind": "season", "id": 1, "name": "Summer swim", "detail": "Swim", "date": "2024-06-01T00:00:00Z"],
            ],
            "books": [["id": 8, "title": "Beach summers", "personIds": [4], "personNames": ["Ada"]]],
            "searchMode": "semantic",
        ]

        let response = try decode(SearchResponseDTO.self, payload)

        #expect(response.query == "ada beach 2024")
        #expect(response.understood.personIds == [4])
        #expect(response.understood.ageFromMonth == 24)
        #expect(response.understood.ageToMonth == 36)
        #expect(response.understood.ageLabel == "age 2")
        #expect(response.understood.year == 2024)
        #expect(response.understood.month == 6)
        #expect(response.understood.category == "quote")
        #expect(response.understood.tagIds == [10])
        #expect(response.understood.text == "beach")
        #expect(response.people.map(\.id) == [4])
        #expect(response.moments.map(\.descriptionText) == ["Beach day"])
        #expect(response.momentCount == 31)
        #expect(response.interviews.map(\.id) == [5])
        #expect(response.photos.map(\.image.id) == [51])
        #expect(response.morePhotos)
        #expect(response.tags.map(\.name) == ["Beach"])
        #expect(response.places.map(\.key) == ["f3"])
        #expect(response.activities.map(\.key) == ["activity-1", "season-1"])
        #expect(response.activities[0].startDate == nil)
        #expect(response.activities[1].startDate != nil)
        #expect(response.books.map(\.title) == ["Beach summers"])
        #expect(!response.isTextOnly)
        #expect(!response.isEmpty)
    }

    @Test("Missing and null groups read as empty")
    func missingGroups() throws {
        let response = try decode(SearchResponseDTO.self, [
            "query": "zzz",
            "understood": ["personIds": NSNull(), "text": "zzz"],
            "people": NSNull(),
            "moments": [],
            "searchMode": "text",
        ] as [String: Any])

        #expect(response.understood.personIds == [])
        #expect(response.understood.tagIds == [])
        #expect(response.understood.ageFromMonth == nil)
        #expect(response.understood.text == "zzz")
        #expect(response.people.isEmpty)
        #expect(response.photos.isEmpty)
        #expect(response.activities.isEmpty)
        #expect(response.books.isEmpty)
        #expect(response.momentCount == 0)
        #expect(response.isTextOnly)
        #expect(response.isEmpty)
    }

    @Test("An empty object decodes, for a server without the proc's newer fields")
    func emptyObject() throws {
        let response = try decode(SearchResponseDTO.self, [String: Any]())

        #expect(response.understood == SearchUnderstoodDTO())
        #expect(response.isEmpty)
    }

    @Test("A group this build doesn't know is ignored")
    func unknownGroup() throws {
        let response = try decode(SearchResponseDTO.self, [
            "query": "ada",
            "people": [Fixture.person(id: 4, name: "Ada")],
            "chats": [["id": 1]],
        ] as [String: Any])

        #expect(response.people.map(\.id) == [4])
    }

    @Test("The request leaves out what isn't set")
    func request() throws {
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SearchRequestDTO(query: "ada"))) as? [String: Any]
        #expect(plain?["query"] as? String == "ada")
        #expect(plain?["ignore"] == nil)
        #expect(plain?["limit"] == nil)

        let ignoring = SearchRequestDTO(query: "ada at 2", ignore: [SearchIgnore.age.rawValue], limit: 100)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ignoring)) as? [String: Any]
        #expect(object?["ignore"] as? [String] == ["age"])
        #expect(object?["limit"] as? Int == 100)
    }

    // MARK: - Chips

    @Test("Chips name each understood filter, people by first name")
    func chips() {
        var understood = SearchUnderstoodDTO()
        understood.personIds = [1, 3]
        understood.ageLabel = "age 2"
        understood.year = 2024
        understood.month = 6
        understood.category = "quote"
        understood.tagIds = [10]

        let chips = SearchResults.chips(understood, names: [1: "Ada Grissom", 3: "Ada Smith"])

        #expect(chips.map(\.kind) == [.person, .age, .date, .category])
        #expect(chips.map(\.label) == ["Ada or Ada", "age 2", "June 2024", "Quotes"])
    }

    @Test("Date and category labels read as the web's do")
    func labels() {
        #expect(SearchResults.dateLabel(year: 2024, month: 0) == "2024")
        #expect(SearchResults.dateLabel(year: 0, month: 12) == "December")
        #expect(SearchResults.dateLabel(year: 0, month: 0) == "")
        #expect(SearchResults.categoryLabel("artwork") == "Artwork")
        #expect(SearchResults.categoryLabel("interview") == "Interview answers")
        #expect(SearchResults.categoryLabel("health") == "Health")
    }

    @Test("The phone's own parse gives the same chips as the server's answer")
    func parsedChips() {
        let parsed = SearchQuery.parse(
            "ben at 2 quotes",
            people: [SearchQuery.Person(id: 2, name: "Ben Grissom")],
            tags: []
        )
        let chips = SearchResults.chips(parsed, names: [2: "Ben Grissom"])
        #expect(chips.map(\.label) == ["Ben", "age 2", "Quotes"])
    }

    @Test("No understanding, no chips")
    func noChips() {
        #expect(SearchResults.chips(SearchUnderstoodDTO(), names: [:]).isEmpty)
    }

    // MARK: - Moments

    @Test("An interview's answers fold into one item where the first one ranked")
    func momentFolding() throws {
        var answerA = Fixture.milestone(id: 2, personId: 4, description: "Blue", category: "interview")
        answerA["interviewId"] = 9
        var answerB = Fixture.milestone(id: 1, personId: 4, description: "Pizza", category: "interview")
        answerB["interviewId"] = 9
        let response = try decode(SearchResponseDTO.self, [
            "moments": [
                Fixture.milestone(id: 5, personId: 4, description: "First steps"),
                answerA,
                Fixture.milestone(id: 6, personId: 4, description: "Lost a tooth"),
                answerB,
            ],
        ] as [String: Any])

        let items = SearchResults.momentItems(response.moments)

        #expect(items.count == 3)
        guard items.count == 3 else { return }
        if case .moment(let moment) = items[0] { #expect(moment.id == 5) } else { Issue.record("expected a moment first") }
        if case .interview(let group) = items[1] {
            #expect(group.interviewId == 9)
            #expect(group.answers.map(\.id) == [1, 2])
        } else {
            Issue.record("expected the interview second")
        }
        if case .moment(let moment) = items[2] { #expect(moment.id == 6) } else { Issue.record("expected a moment third") }
    }

    // MARK: - Photos

    @Test("Photo ids keep the server's order, resolved against the mirror where it can")
    func photoResolution() {
        let resolved = SearchResults.resolve([30, 10, 20], in: [10: "ten", 20: "twenty"])
        #expect(resolved.map { $0.id } == [30, 10, 20])
        #expect(resolved.map { $0.local } == [nil, "ten", "twenty"])
    }

    @Test("See all photos carries people, the month and the words to the gallery")
    func seeAllPhotos() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let ada = UUID()
        var understood = SearchUnderstoodDTO()
        understood.personIds = [4, 99]
        understood.year = 2024
        understood.month = 2
        understood.text = "beach"

        let filter = SearchResults.photoFilter(understood, localIds: [4: ada], calendar: utc)

        #expect(filter.personLocalIds == [ada])
        #expect(filter.searchText == "beach")
        #expect(filter.dateFrom.map { utc.dateComponents([.year, .month, .day], from: $0) } == DateComponents(year: 2024, month: 2, day: 1))
        #expect(filter.dateTo.map { utc.dateComponents([.year, .month, .day], from: $0) } == DateComponents(year: 2024, month: 2, day: 29))
    }

    @Test("A year alone spans the whole year, and no year sets no dates")
    func seeAllPhotosYear() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        var understood = SearchUnderstoodDTO()
        understood.year = 2023
        let filter = SearchResults.photoFilter(understood, localIds: [:], calendar: utc)
        #expect(filter.dateTo.map { utc.dateComponents([.year, .month, .day], from: $0) } == DateComponents(year: 2023, month: 12, day: 31))

        understood.year = 0
        understood.month = 6
        let monthOnly = SearchResults.photoFilter(understood, localIds: [:], calendar: utc)
        #expect(monthOnly.dateFrom == nil)
        #expect(monthOnly.dateTo == nil)
    }

    // MARK: - Stale responses

    private func answer(_ query: String) throws -> SearchResponseDTO {
        try decode(SearchResponseDTO.self, ["query": query])
    }

    @Test("A slow answer to an older query never replaces a newer one")
    func staleResponseDropped() async throws {
        let gate = Gate()
        let model = SearchModel(debounce: .zero) { request in
            if request.query == "slow" {
                await gate.enter()
            }
            return try self.answer(request.query)
        }

        let slow = Task { await model.search("slow") }
        await gate.waitUntilEntered()
        await model.search("fast")
        #expect(model.response?.query == "fast")

        gate.open()
        await slow.value
        #expect(model.response?.query == "fast")
        #expect(model.isCurrent)
        #expect(!model.isLoading)
    }

    @Test("Removing a chip re-asks with that kind ignored, and typing starts over")
    func ignoreAndReset() async throws {
        var requests: [SearchRequestDTO] = []
        let model = SearchModel(debounce: .zero) { request in
            requests.append(request)
            return try self.answer(request.query)
        }

        await model.search("ben at 2")
        await model.remove(.age)
        await model.showAllMoments()

        #expect(requests.map(\.ignore) == [nil, ["age"], ["age"]])
        #expect(requests.map(\.limit) == [nil, nil, SearchResults.showAllMomentsLimit])

        await model.search("ben")
        #expect(requests.last?.ignore == nil)
        #expect(requests.last?.limit == nil)
    }

    @Test("A failure is reported, and an empty query clears the answer without asking")
    func failureAndEmpty() async {
        struct Offline: Error {}
        var calls = 0
        let model = SearchModel(debounce: .zero) { _ in
            calls += 1
            throw Offline()
        }

        await model.search("ada")
        #expect(model.failed)
        #expect(model.response == nil)

        await model.search("   ")
        #expect(!model.failed)
        #expect(model.currentResponse == nil)
        #expect(calls == 1)
    }
}

/// Holds one fetch open until the test lets it go.
@MainActor
private final class Gate {
    private var hasEntered = false
    private var entered: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func enter() async {
        hasEntered = true
        entered?.resume()
        entered = nil
        await withCheckedContinuation { release = $0 }
    }

    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { entered = $0 }
    }

    func open() {
        release?.resume()
        release = nil
    }
}
