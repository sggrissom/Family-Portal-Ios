import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Quick-add defaults")
struct QuickAddDefaultsTests {

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

    /// Steven and Ruth, their children Mia and Ben, and Ruth's mother Rose above them — the same household `FamilyGroupsTests` uses.
    private struct Household {
        let rose = QuickAddDefaultsTests.person("Rose", id: 1, born: (1958, 5, 5))
        let steven = QuickAddDefaultsTests.person("Steven", id: 2, born: (1984, 3, 3))
        let ruth = QuickAddDefaultsTests.person("Ruth", id: 3, born: (1986, 2, 2))
        let mia = QuickAddDefaultsTests.person("Mia", id: 4, born: (2016, 4, 11))
        let ben = QuickAddDefaultsTests.person("Ben", id: 5, born: (2019, 8, 1))

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

    /// A scratch suite per test, so one test's memory is never another's default.
    private static func scratch() -> UserDefaults {
        UserDefaults(suiteName: "quick-add-defaults-\(UUID().uuidString)")!
    }

    // MARK: - Who a sheet opens on

    @Test("The person last written for wins")
    func rememberedPersonWins() {
        let household = Household()

        let resolved = QuickAddDefaults.person(
            in: household.people,
            remembered: household.steven.id,
            relations: household.edges
        )

        #expect(resolved?.name == "Steven")
    }

    /// A local id outlives an account erase. Landing the record on whoever inherited the slot would be silent and wrong.
    @Test("A remembered person the roster no longer holds is not substituted for")
    func forgottenPersonFallsBackRatherThanGuessing() {
        let household = Household()

        let resolved = QuickAddDefaults.person(
            in: household.people,
            remembered: UUID(),
            relations: household.edges
        )

        // The fallback, not "somebody near the id we were given".
        #expect(resolved?.name == "Mia")
    }

    @Test("With nothing remembered, the youngest generation leads")
    func youngestGenerationIsTheFallback() {
        let household = Household()

        let resolved = QuickAddDefaults.person(
            in: household.people,
            remembered: nil,
            relations: household.edges
        )

        // Mia and Ben are the Children band; Mia is the elder of the two.
        #expect(resolved?.name == "Mia")
    }

    /// Reading generations off the bottom of the tree is what makes this hold: adding Rose does not turn the parents into the youngest band.
    @Test("A generation above does not change who is youngest")
    func aGenerationAboveDoesNotMoveTheDefault() {
        let household = Household()
        let withoutRose = household.people.filter { $0.name != "Rose" }
        let edges = household.edges.filter { $0.fromId != 1 }

        let withRose = QuickAddDefaults.person(in: household.people, remembered: nil, relations: household.edges)
        let without = QuickAddDefaults.person(in: withoutRose, remembered: nil, relations: edges)

        #expect(withRose?.name == "Mia")
        #expect(without?.name == "Mia")
    }

    @Test("One person needs no choosing")
    func aLoneRosterResolvesToItsOnlyMember() {
        let only = Self.person("Ada", id: 1, born: (2020, 1, 1))

        #expect(QuickAddDefaults.person(in: [only], remembered: nil, relations: [])?.name == "Ada")
    }

    /// A household that has stated no relationships has no youngest band, and nothing else says who to pick. The sheet asks, and remembers the answer.
    @Test("An unlinked household is asked rather than guessed at")
    func unlinkedHouseholdHasNoDefault() {
        let people = [
            Self.person("Ada", id: 1, born: (1990, 1, 1)),
            Self.person("Bo", id: 2, born: (2020, 1, 1)),
        ]

        #expect(QuickAddDefaults.person(in: people, remembered: nil, relations: []) == nil)
    }

    @Test("An empty roster resolves to nobody")
    func emptyRoster() {
        #expect(QuickAddDefaults.person(in: [], remembered: nil, relations: []) == nil)
    }

    // MARK: - Storage

    @Test("Nothing is remembered until something is saved")
    func nothingRememberedInitially() {
        let defaults = QuickAddDefaults(defaults: Self.scratch())

        #expect(defaults.rememberedPersonId == nil)
        #expect(defaults.rememberedMeasurementType == nil)
    }

    @Test("The person and the measurement last saved come back")
    func roundTrip() {
        let defaults = QuickAddDefaults(defaults: Self.scratch())
        let id = UUID()

        defaults.rememberPerson(id)
        defaults.rememberMeasurement(type: .weight, unit: .pounds)

        #expect(defaults.rememberedPersonId == id)
        #expect(defaults.rememberedMeasurementType == .weight)
        #expect(defaults.unit(for: .weight) == .pounds)
    }

    /// A height last taken in inches says nothing about how this family weighs anybody, and "12 inches" is not a weight the sheet should ever open on.
    @Test("A remembered unit is not carried across to a type it cannot measure")
    func rememberedUnitIsIgnoredForTheOtherType() {
        let defaults = QuickAddDefaults(defaults: Self.scratch())

        defaults.rememberMeasurement(type: .height, unit: .inches)

        #expect(defaults.unit(for: .height) == .inches)
        #expect(defaults.unit(for: .weight) == MeasurementType.weight.defaultUnit)
    }

    @Test("With nothing remembered, a type opens on its own default unit")
    func unitFallsBackToTheTypeDefault() {
        let defaults = QuickAddDefaults(defaults: Self.scratch())

        #expect(defaults.unit(for: .height) == MeasurementType.height.defaultUnit)
        #expect(defaults.unit(for: .weight) == MeasurementType.weight.defaultUnit)
    }
}
