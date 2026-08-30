import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Family groups")
struct FamilyGroupsTests {

    private static func person(_ name: String, id: Int?, born: (Int, Int, Int)? = nil) -> Person {
        let person = Person(
            name: name,
            gender: .other,
            birthday: born.map { date($0.0, $0.1, $0.2) }
        )
        person.remoteId = id.map(String.init)
        return person
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Steven and Ruth, their children Mia and Ben, and Ruth's mother Rose above them.
    private struct Household {
        let rose = FamilyGroupsTests.person("Rose", id: 1, born: (1958, 5, 5))
        let steven = FamilyGroupsTests.person("Steven", id: 2, born: (1984, 3, 3))
        let ruth = FamilyGroupsTests.person("Ruth", id: 3, born: (1986, 2, 2))
        let mia = FamilyGroupsTests.person("Mia", id: 4, born: (2016, 4, 11))
        let ben = FamilyGroupsTests.person("Ben", id: 5, born: (2019, 8, 1))

        var people: [Person] { [mia, rose, ben, steven, ruth] }

        var edges: [RelationEdge] {
            [
                RelationEdge(id: 1, fromId: 1, toId: 3, kind: .parent),
                RelationEdge(id: 2, fromId: 2, toId: 4, kind: .parent),
                RelationEdge(id: 3, fromId: 3, toId: 4, kind: .parent),
                RelationEdge(id: 4, fromId: 2, toId: 5, kind: .parent),
                RelationEdge(id: 5, fromId: 3, toId: 5, kind: .parent),
                RelationEdge(id: 6, fromId: 2, toId: 3, kind: .partner),
            ]
        }
    }

    /// One line per band — "Parents: Ruth, Steven" — so a whole layout can be asserted in one comparison.
    private static func summary(_ groups: [PersonGroup]) -> [String] {
        groups.map { "\($0.title): \($0.people.map(\.name).joined(separator: ", "))" }
    }

    // MARK: - Bands

    @Test("Generations are named from the youngest upward, oldest band first")
    func generationsAreNamedFromTheBottom() {
        let household = Household()

        let groups = FamilyGroups.group(people: household.people, relations: household.edges)

        #expect(groups.map(\.title) == ["Grandparents", "Parents", "Children"])
        // Ruth leads her band because she is the one Rose is linked to; Steven follows as her partner.
        #expect(groups.map { $0.people.map(\.name) } == [["Rose"], ["Ruth", "Steven"], ["Mia", "Ben"]])
    }

    @Test("Adding a generation above renames the bands rather than the people")
    func aGenerationAboveShiftsEveryTitle() {
        // Ruth's mother is the top band; drop her and the same people are Parents and Children.
        let household = Household()
        let people = household.people.filter { $0.name != "Rose" }
        let edges = household.edges.filter { $0.fromId != 1 }

        #expect(FamilyGroups.group(people: people, relations: edges).map(\.title)
                == ["Parents", "Children"])
    }

    @Test("Partners sit level with each other, whichever of them is linked upward")
    func partnersShareABand() throws {
        // Only Ruth is Rose's child; Steven is placed beside her by the partner edge alone.
        let household = Household()
        let groups = FamilyGroups.group(people: household.people, relations: household.edges)

        let parents = try #require(groups.first { $0.title == "Parents" })
        #expect(Set(parents.people.map(\.name)) == ["Steven", "Ruth"])
    }

    @Test("Siblings sit level even when only one of them names a parent")
    func siblingsShareABand() {
        let mia = Self.person("Mia", id: 1, born: (2016, 4, 11))
        let ben = Self.person("Ben", id: 2, born: (2019, 8, 1))
        let steven = Self.person("Steven", id: 3, born: (1984, 3, 3))
        let edges = [
            RelationEdge(id: 1, fromId: 3, toId: 1, kind: .parent),
            RelationEdge(id: 2, fromId: 1, toId: 2, kind: .sibling),
        ]

        let groups = FamilyGroups.group(people: [mia, ben, steven], relations: edges)

        #expect(Self.summary(groups) == ["Parents: Steven", "Children: Mia, Ben"])
    }

    @Test("A household with one generation is just the family")
    func oneGenerationIsNotCalledChildren() {
        let steven = Self.person("Steven", id: 1, born: (1984, 3, 3))
        let ruth = Self.person("Ruth", id: 2, born: (1986, 2, 2))
        let edges = [RelationEdge(id: 1, fromId: 1, toId: 2, kind: .partner)]

        #expect(Self.summary(FamilyGroups.group(people: [steven, ruth], relations: edges))
                == ["Family: Steven, Ruth"])
    }

    @Test("Five generations run out of names and fall back")
    func deepTreesFallBackToOneTitle() {
        var people: [Person] = []
        var edges: [RelationEdge] = []
        for generation in 1...5 {
            people.append(Self.person("G\(generation)", id: generation, born: (1900 + generation * 20, 1, 1)))
            if generation > 1 {
                edges.append(RelationEdge(id: generation, fromId: generation - 1, toId: generation, kind: .parent))
            }
        }

        #expect(FamilyGroups.group(people: people, relations: edges).map(\.title)
                == ["Earlier generations", "Great-grandparents", "Grandparents", "Parents", "Children"])
    }

    // MARK: - People the graph does not reach

    @Test("People no relationship reaches go last, in their own band")
    func unlinkedPeopleGoLast() {
        let household = Household()
        let stranger = Self.person("Ada", id: 9, born: (2001, 1, 1))

        let groups = FamilyGroups.group(
            people: household.people + [stranger],
            relations: household.edges
        )

        #expect(groups.last?.title == "Not linked yet")
        #expect(groups.last?.people.map(\.name) == ["Ada"])
    }

    @Test("Somebody still uploading has no server id, so nothing can band them")
    func unsyncedPeopleAreUnlinked() {
        let household = Household()
        let pending = Self.person("New", id: nil, born: (2026, 1, 1))

        let groups = FamilyGroups.group(
            people: household.people + [pending],
            relations: household.edges
        )

        #expect(groups.last?.people.map(\.name) == ["New"])
    }

    @Test("An edge to somebody who is not here is ignored")
    func edgesToMissingPeopleAreDropped() {
        let steven = Self.person("Steven", id: 1, born: (1984, 3, 3))
        // Person 99 is in another family the viewer cannot see.
        let edges = [RelationEdge(id: 1, fromId: 1, toId: 99, kind: .parent)]

        // Nothing reaches Steven once that edge is dropped, so he is not in a generation at all.
        #expect(Self.summary(FamilyGroups.group(people: [steven], relations: edges))
                == ["Not linked yet: Steven"])
    }

    @Test("A family with no relationships at all is one band")
    func noEdgesIsOneBand() {
        let people = [
            Self.person("Ada", id: 1, born: (1990, 1, 1)),
            Self.person("Bo", id: 2, born: (2020, 1, 1)),
        ]

        let groups = FamilyGroups.group(people: people, relations: [])

        #expect(groups.count == 1)
        #expect(groups.first?.people.map(\.name) == ["Ada", "Bo"])
    }

    // MARK: - Order within a band

    @Test("A band is oldest first, and children follow whichever parent came first")
    func childrenFollowTheirParents() {
        // Two couples, each with a child. Each child sits under its own parents rather than sorted purely by age.
        let elder = Self.person("Elder", id: 1, born: (1980, 1, 1))
        let younger = Self.person("Younger", id: 2, born: (1990, 1, 1))
        let eldersKid = Self.person("EldersKid", id: 3, born: (2020, 1, 1))
        let youngersKid = Self.person("YoungersKid", id: 4, born: (2010, 1, 1))
        let edges = [
            RelationEdge(id: 1, fromId: 1, toId: 3, kind: .parent),
            RelationEdge(id: 2, fromId: 2, toId: 4, kind: .parent),
            RelationEdge(id: 3, fromId: 1, toId: 2, kind: .sibling),
        ]

        let groups = FamilyGroups.group(
            people: [younger, elder, youngersKid, eldersKid],
            relations: edges
        )

        #expect(Self.summary(groups) == [
            "Parents: Elder, Younger",
            // Not "YoungersKid, EldersKid", which is what sorting the band by age alone would give.
            "Children: EldersKid, YoungersKid",
        ])
    }

    @Test("A person with no birthday sorts last in their band, by name")
    func unknownBirthdaysSortLast() {
        let known = Self.person("Known", id: 1, born: (1984, 3, 3))
        let zoe = Self.person("Zoe", id: 2)
        let ada = Self.person("Ada", id: 3)
        let edges = [
            RelationEdge(id: 1, fromId: 1, toId: 2, kind: .sibling),
            RelationEdge(id: 2, fromId: 1, toId: 3, kind: .sibling),
        ]

        #expect(FamilyGroups.group(people: [zoe, ada, known], relations: edges)
            .first?.people.map(\.name) == ["Known", "Ada", "Zoe"])
    }

    @Test("A cycle in the parent edges still terminates")
    func parentCyclesTerminate() {
        // Nothing stops the server storing A→B and B→A; the layout must not spin on it.
        let a = Self.person("A", id: 1, born: (1980, 1, 1))
        let b = Self.person("B", id: 2, born: (1990, 1, 1))
        let edges = [
            RelationEdge(id: 1, fromId: 1, toId: 2, kind: .parent),
            RelationEdge(id: 2, fromId: 2, toId: 1, kind: .parent),
        ]

        let groups = FamilyGroups.group(people: [a, b], relations: edges)

        #expect(groups.flatMap { $0.people.map(\.name) }.sorted() == ["A", "B"])
    }
}
