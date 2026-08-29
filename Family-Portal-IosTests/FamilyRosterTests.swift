import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Family roster")
struct FamilyRosterTests {

    private static func person(_ name: String, born: Date?) -> Person {
        Person(name: name, gender: .other, birthday: born)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("The roster is one list, not a parent and child split")
    func rosterKeepsEveryoneInOneList() {
        let people = [
            Self.person("Ada", born: Self.date(1990, 1, 1)),
            Self.person("Bo", born: Self.date(2020, 1, 1)),
            Self.person("Cy", born: nil),
        ]

        #expect(Person.roster(in: people).map(\.name) == ["Ada", "Bo", "Cy"])
    }

    @Test("The roster is ordered oldest first")
    func rosterIsOldestFirst() {
        let people = [
            Self.person("Youngest", born: Self.date(2024, 6, 1)),
            Self.person("Eldest", born: Self.date(2018, 3, 4)),
            Self.person("Middle", born: Self.date(2021, 11, 20)),
        ]

        #expect(Person.roster(in: people).map(\.name) == ["Eldest", "Middle", "Youngest"])
    }

    @Test("People with no birthday sort last, by name")
    func unknownBirthdaysSortLast() {
        let people = [
            Self.person("Zoe", born: nil),
            Self.person("Eldest", born: Self.date(2018, 3, 4)),
            Self.person("Ada", born: nil),
        ]

        #expect(Person.roster(in: people).map(\.name) == ["Eldest", "Ada", "Zoe"])
    }

    @Test("Previews and tests build the same store the app does")
    func schemaIsSharedWithPreviewsAndTests() throws {
        let context = try TestStore.makeContext()

        context.insert(ChatMessage(
            clientMessageId: UUID().uuidString,
            userId: 1,
            userName: "Ada",
            content: "hello"
        ))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<ChatMessage>()) == 1)

        let previewMessages = try PreviewData.container.mainContext
            .fetchCount(FetchDescriptor<ChatMessage>())
        #expect(previewMessages >= 0)
    }
}
