import Foundation
import Testing
@testable import Family_Portal_Ios

/// Payloads shaped field for field on `SearchResponse` in backend/search.go.
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
}
