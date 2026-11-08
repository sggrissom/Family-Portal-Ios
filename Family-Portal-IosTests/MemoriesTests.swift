import Foundation
import Testing
@testable import Family_Portal_Ios

/// `GetMemories` decoding and how a memory reads — frontend/lib/memories.test.ts.
@Suite("Memories")
struct MemoriesTests {

    static func memory(_ fields: [String: Any] = [:]) -> [String: Any] {
        [
            "key": "m1",
            "kind": "moment",
            "personIds": [1],
            "photoIds": [],
            "text": "Walked",
            "context": "",
            "category": "first",
            "date": "2021-06-04T00:00:00Z",
            "createdAt": "2026-11-01T00:00:00Z",
            "milestoneId": 9,
        ].merging(fields) { $1 }
    }

    static func decode(_ object: [String: Any]) throws -> MemoryDTO {
        try APIClient.decode(MemoryDTO.self, from: Fixture.data(object))
    }

    static let birthday = ISO8601DateFormatter().date(from: "2019-03-04T00:00:00Z")!
    static let people: [Int: (name: String, birthday: Date?)] = [
        1: ("Clara Whitfield", birthday),
        2: ("Rowan Whitfield", nil),
        3: ("Jake Whitfield", nil),
    ]

    @Test("A response decodes, with null lists as empty")
    func decodes() throws {
        let payload: [String: Any] = [
            "memories": [Self.memory(["photoIds": [5], "interviewId": 0])],
            "recentlyAdded": NSNull(),
        ]
        let response = try APIClient.decode(GetMemoriesResponseDTO.self, from: Fixture.data(payload))
        #expect(response.memories.map(\.key) == ["m1"])
        #expect(response.memories.first?.photoIds == [5])
        #expect(response.memories.first?.milestoneId == 9)
        #expect(response.recentlyAdded.isEmpty)
    }

    @Test("An exact memory gives its date and one person's age then")
    func exactWhen() throws {
        let when = Memories.when(try Self.decode(Self.memory()), people: Self.people)
        #expect(when.contains("2021"))
        #expect(when.hasSuffix(" · 2 years 3 months"))
    }

    @Test("Several people leave the age out")
    func sharedWhen() throws {
        let when = Memories.when(try Self.decode(Self.memory(["personIds": [1, 2]])), people: Self.people)
        #expect(!when.contains("·"))
    }

    @Test("An approximate memory keeps its own wording")
    func approximateWhen() throws {
        let recordTime: [String: Any] = [
            "meaning": "occurrence", "basis": "calendar", "precision": "year",
            "estimated": true, "from": "2019", "start": "2019-01-01", "end": "2020-01-01", "resolved": true,
        ]
        let when = Memories.when(try Self.decode(Self.memory(["recordTime": recordTime])), people: Self.people)
        #expect(when == "Around 2019")
    }

    @Test("First names join as the web joins them")
    func names() throws {
        #expect(Memories.names(try Self.decode(Self.memory(["personIds": [1]])), people: Self.people) == "Clara")
        #expect(Memories.names(try Self.decode(Self.memory(["personIds": [1, 2]])), people: Self.people) == "Clara & Rowan")
        #expect(Memories.names(try Self.decode(Self.memory(["personIds": [1, 2, 3]])), people: Self.people) == "Clara, Rowan & Jake")
    }

    @MainActor
    @Test("A visit keeps its seed and freezes what was seen when it began")
    func visit() throws {
        let defaults = try #require(UserDefaults(suiteName: "memories-\(UUID())"))
        let first = MemoryVisit(seed: 7, defaults: defaults)
        first.markSeen("m1")
        #expect(first.seen.isEmpty)
        let second = MemoryVisit(seed: 8, defaults: defaults)
        #expect(second.seen == ["m1"])

        let memories = [try Self.decode(Self.memory()), try Self.decode(Self.memory(["key": "m2"]))]
        #expect(second.featured(memories)?.key == "m1")
        second.advance(count: memories.count)
        #expect(second.featured(memories)?.key == "m2")
        second.advance(count: memories.count)
        #expect(second.featured(memories)?.key == "m1")
    }
}

@Suite("Explore previews")
struct ExplorePreviewTests {

    @Test("Only childhood ages on a friendly grid are suggested")
    func invitingAges() {
        #expect(AgeSteps.invitingAge(6))
        #expect(AgeSteps.invitingAge(18))
        #expect(AgeSteps.invitingAge(24))
        #expect(!AgeSteps.invitingAge(30))
        #expect(!AgeSteps.invitingAge(0))
        #expect(AgeSteps.invitingAge(17 * 12))
        #expect(!AgeSteps.invitingAge(66 * 12 + 6))
    }

    @Test("Through the years takes one photo memory per year, oldest first")
    func throughTheYears() throws {
        let memories = try [
            MemoriesTests.memory(["key": "a", "date": "2023-05-01T00:00:00Z", "photoIds": [1]]),
            MemoriesTests.memory(["key": "b", "date": "2021-05-01T00:00:00Z", "photoIds": [2]]),
            MemoriesTests.memory(["key": "c", "date": "2023-09-01T00:00:00Z", "photoIds": [3]]),
            MemoriesTests.memory(["key": "d", "date": "2019-05-01T00:00:00Z", "photoIds": []]),
        ].map(MemoriesTests.decode)

        #expect(Memories.throughTheYears(memories).map(\.key) == ["b", "a"])
        #expect(Memories.yearLabel(memories[0]) == "2023")
    }
}
