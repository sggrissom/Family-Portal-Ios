import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// Two screens show the same household — the Family tab and Settings' family
/// management — and each used to carry its own copy of the partition and the
/// four-case birthday comparison. A roster that reads one way in one place and
/// another way in the other is a bug nobody would think to look for, so the
/// ordering is pinned here rather than left to whichever copy was edited last.
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

    /// A person can be added before anyone knows or bothers to enter a birthday,
    /// and there is no sensible place to guess. They collect at the end rather
    /// than sorting to the top, where they would displace the eldest child.
    @Test("Children with no birthday sort last, by name")
    func unknownBirthdaysSortLast() {
        let people = [
            Self.person("Zoe", .child, born: nil),
            Self.person("Eldest", .child, born: Self.date(2018, 3, 4)),
            Self.person("Ada", .child, born: nil),
        ]

        #expect(Person.children(in: people).map(\.name) == ["Eldest", "Ada", "Zoe"])
    }

    /// `PreviewData` used to write out its own model list, and left `ChatMessage`
    /// out of it — so every preview that touched a chat model crashed, and
    /// nothing said so, because a schema is data rather than a type. This is
    /// what stops a model added later from reaching the app's store and not the
    /// other two.
    @Test("Previews and tests build the same store the app does")
    func schemaIsSharedWithPreviewsAndTests() throws {
        let context = try TestStore.makeContext()

        // A chat message is the one that was missing. Inserting and reading it
        // back is what proves the test store really carries the app's schema
        // rather than a lookalike.
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
        // Zero is the right answer; the point is that the fetch does not trap on
        // a model the preview container never declared.
        #expect(previewMessages >= 0)
    }
}
