import Foundation
import Testing
@testable import Family_Portal_Ios

/// The `chipOrder` and `chipLabels` cases from frontend/lib/familyGroups.test.ts.
@MainActor
@Suite("Chip order")
struct ChipOrderTests {

    private static func person(_ id: Int, _ name: String, _ born: String, familyId: Int = 1, isPregnancy: Bool = false) -> Person {
        let person = Person(
            name: name,
            gender: .other,
            birthday: ISO8601DateFormatter().date(from: born + "T00:00:00Z"),
            isPregnancy: isPregnancy
        )
        person.remoteId = String(id)
        person.familyRemoteId = familyId
        return person
    }

    private static func parent(_ from: Int, _ to: Int) -> RelationEdge {
        RelationEdge(fromId: from, toId: to, kind: .parent)
    }

    @Test("Children first, then older generations, then the unlinked, then linked households")
    func order() {
        let dad = Self.person(1, "Dad", "1984-01-01")
        let mom = Self.person(2, "Mom", "1985-01-01")
        let ann = Self.person(3, "Ann", "2014-01-01")
        let ben = Self.person(4, "Ben", "2016-01-01")
        let gran = Self.person(5, "Gran", "1958-01-01")
        let cousin = Self.person(6, "Cousin", "2011-01-01", familyId: 2)
        let due = Self.person(7, "Due", "2027-01-01", isPregnancy: true)
        let loner = Self.person(8, "Loner", "1990-01-01")

        let order = FamilyGroups.chipOrder(
            people: [dad, mom, ann, ben, gran, cousin, due, loner],
            relations: [
                Self.parent(5, 1), Self.parent(1, 3), Self.parent(2, 3), Self.parent(1, 4), Self.parent(2, 4),
                RelationEdge(fromId: 1, toId: 2, kind: .partner),
            ],
            ownFamilyId: 1
        )

        #expect(order.map(\.name) == ["Ann", "Ben", "Dad", "Mom", "Gran", "Loner", "Cousin"])
    }

    @Test("Somebody added offline has no household yet and counts as ours")
    func offlinePersonIsOurs() {
        let cousin = Self.person(6, "Cousin", "2011-01-01", familyId: 2)
        let new = Person(name: "New", gender: .other)

        let order = FamilyGroups.chipOrder(people: [cousin, new], relations: [], ownFamilyId: 1)

        #expect(order.map(\.name) == ["New", "Cousin"])
    }

    @Test("First names, unless two people share one")
    func labels() {
        let people = [
            Self.person(1, "Ann Smith", "2010-01-01"),
            Self.person(2, "Ben Smith", "2012-01-01"),
            Self.person(3, "Ben Jones", "2011-01-01"),
        ]
        let labels = FamilyGroups.chipLabels(people)

        #expect(people.map { labels[$0.id] } == ["Ann", "Ben Smith", "Ben Jones"])
    }
}
