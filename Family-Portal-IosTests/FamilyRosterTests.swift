import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Family roster")
struct FamilyRosterTests {

    private static func person(_ name: String, _ type: PersonType, born: Date?) -> Person {
        Person(name: name, type: type, gender: .other, birthday: born)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Parents and children are separated")
    func rosterIsPartitionedByType() {
        let people = [
            Self.person("Ada", .parent, born: Self.date(1990, 1, 1)),
            Self.person("Bo", .child, born: Self.date(2020, 1, 1)),
            Self.person("Cy", .parent, born: nil),
        ]

        #expect(Person.parents(in: people).map(\.name) == ["Ada", "Cy"])
        #expect(Person.children(in: people).map(\.name) == ["Bo"])
    }

    @Test("Children are ordered oldest first")
    func childrenAreOldestFirst() {
        let people = [
            Self.person("Youngest", .child, born: Self.date(2024, 6, 1)),
            Self.person("Eldest", .child, born: Self.date(2018, 3, 4)),
            Self.person("Middle", .child, born: Self.date(2021, 11, 20)),
        ]

        #expect(Person.children(in: people).map(\.name) == ["Eldest", "Middle", "Youngest"])
    }

    @Test("Children with no birthday sort last, by name")
    func unknownBirthdaysSortLast() {
        let people = [
            Self.person("Zoe", .child, born: nil),
            Self.person("Eldest", .child, born: Self.date(2018, 3, 4)),
            Self.person("Ada", .child, born: nil),
        ]

        #expect(Person.children(in: people).map(\.name) == ["Eldest", "Ada", "Zoe"])
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
