import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/interviewQuestions.test.ts.
@MainActor
@Suite("Interview question list")
struct InterviewQuestionListTests {

    private static func q(_ id: Int, _ text: String, _ section: String, key: String = "", archived: Bool = false) -> InterviewQuestionDTO {
        try! APIClient.decode(InterviewQuestionDTO.self, from: Fixture.data([
            "id": id, "text": text, "section": section, "defaultKey": key, "archived": archived,
        ] as [String: Any]))
    }

    private static func sample() -> QuestionListDraft {
        QuestionListDraft([
            q(1, "Color", "Favorites"),
            q(2, "Food", "Favorites"),
            q(3, "Snack", "Favorites", archived: true),
            q(4, "Best friend", "People"),
            q(5, "Teacher", "People"),
        ])
    }

    private static func texts(_ rows: [QuestionRow]) -> [String] { rows.map(\.text) }

    private static func key(_ draft: QuestionListDraft, _ text: String) -> Int {
        draft.rows.first { $0.text == text }!.key
    }

    @Test("Groups by section in first-seen order and keeps retired questions apart")
    func groups() {
        let draft = Self.sample()
        #expect(draft.sections == ["Favorites", "People"])
        #expect(Self.texts(draft.active(in: "Favorites")) == ["Color", "Food"])
        #expect(Self.texts(draft.retired) == ["Snack"])
    }

    @Test("Steps within a section, then across the section edge")
    func steps() {
        var draft = Self.sample()
        draft.step(Self.key(draft, "Food"), by: -1)
        #expect(Self.texts(draft.active(in: "Favorites")) == ["Food", "Color"])

        draft.step(Self.key(draft, "Color"), by: 1)
        #expect(Self.texts(draft.active(in: "Favorites")) == ["Food"])
        #expect(Self.texts(draft.active(in: "People")) == ["Color", "Best friend", "Teacher"])

        draft.step(Self.key(draft, "Color"), by: -1)
        #expect(Self.texts(draft.active(in: "Favorites")) == ["Food", "Color"])

        draft.step(Self.key(draft, "Teacher"), by: 1)
        #expect(Self.texts(draft.active(in: "People")) == ["Best friend", "Teacher"])
    }

    @Test("Moving before a question takes that question's section")
    func moveBefore() {
        var draft = Self.sample()
        draft.move(Self.key(draft, "Teacher"), before: Self.key(draft, "Food"))
        #expect(Self.texts(draft.active(in: "Favorites")) == ["Color", "Teacher", "Food"])
        #expect(Self.texts(draft.active(in: "People")) == ["Best friend"])
    }

    @Test("Moves a question to the end of another section, even an empty one")
    func moveToSection() {
        var draft = Self.sample()
        draft.addSection("Just for fun")
        draft.move(Self.key(draft, "Color"), toSection: "Just for fun")
        draft.move(Self.key(draft, "Food"), toSection: "People")
        #expect(Self.texts(draft.active(in: "People")) == ["Best friend", "Teacher", "Food"])
        #expect(Self.texts(draft.active(in: "Just for fun")) == ["Color"])
        #expect(draft.questionsForSave.map(\.text) == ["Snack", "Best friend", "Teacher", "Food", "Color"])
    }

    @Test("Renames a section, merging into one that already has the name")
    func rename() {
        var draft = Self.sample()
        draft.rename(section: "People", to: "Friends")
        #expect(draft.sections == ["Favorites", "Friends"])
        draft.rename(section: "Friends", to: "Favorites")
        #expect(draft.sections == ["Favorites"])
        #expect(Self.texts(draft.active(in: "Favorites")) == ["Color", "Food", "Best friend", "Teacher"])
    }

    @Test("Refuses a blank or duplicate section name")
    func addSection() {
        var draft = Self.sample()
        let blank = draft.addSection("  ")
        let duplicate = draft.addSection("People")
        let added = draft.addSection("This year")
        #expect(!blank)
        #expect(!duplicate)
        #expect(added)
    }

    @Test("Reset restores retired built-ins and adds missing ones, keeping the family's own")
    func reset() {
        var draft = QuestionListDraft([
            Self.q(1, "Color", "Favorites", key: "fav-color", archived: true),
            Self.q(2, "Dinosaur", "Favorites", archived: true),
        ])
        draft.resetToDefaults([
            Self.q(0, "Color", "Favorites", key: "fav-color"),
            Self.q(0, "Food", "Favorites", key: "fav-food"),
            Self.q(0, "Best friend", "People", key: "best-friend"),
        ])
        #expect(Self.texts(draft.active(in: "Favorites")) == ["Color", "Food"])
        #expect(Self.texts(draft.active(in: "People")) == ["Best friend"])
        #expect(Self.texts(draft.retired) == ["Dinosaur"])
    }

    @Test("Saves in section order with every field")
    func save() {
        var draft = Self.sample()
        draft.sections.reverse()
        let saved = draft.questionsForSave
        #expect(saved.map(\.text) == ["Best friend", "Teacher", "Color", "Food", "Snack"])
        #expect(saved[4] == InterviewQuestionInputDTO(id: 3, text: "Snack", section: "Favorites", minAgeYears: 0, maxAgeYears: 0, defaultKey: "", archived: true))
    }

    @Test("Usage arrives keyed by question id as a string")
    func usage() throws {
        let response = try APIClient.decode(InterviewQuestionsResponseDTO.self, from: Fixture.data([
            "familyId": 7, "revision": 4,
            "questions": [["id": 1, "text": "Color", "section": "Favorites"]],
            "usage": ["1": ["interviews": 2, "answers": 2]],
        ] as [String: Any]))
        #expect(response.usage(of: 1)?.inUse == true)
        #expect(response.usage(of: 2) == nil)
        #expect(response.revision == 4)
    }
}
