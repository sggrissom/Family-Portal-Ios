import Foundation
import Testing
@testable import Family_Portal_Ios

/// The "over-time views" and `compareByAge` cases from frontend/lib/interviews.test.ts, over the same fixture.
@MainActor
@Suite("Interviews over time")
struct InterviewOverTimeTests {

    private static func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try APIClient.decode(T.self, from: Fixture.data(object))
    }

    private static func q(_ id: Int, _ section: String, _ position: Int, oneOff: Bool = false, archived: Bool = false) -> [String: Any] {
        ["id": id, "text": "Q\(id)", "section": section, "position": position, "oneOff": oneOff, "archived": archived]
    }

    private static func iv(_ id: Int, _ date: String, _ questionIds: [Int], _ skippedIds: [Int] = []) -> [String: Any] {
        ["id": id, "date": date, "questionIds": questionIds, "skippedIds": skippedIds]
    }

    private static func a(_ id: Int, _ interviewId: Int, _ questionId: Int, _ description: String) -> [String: Any] {
        Fixture.milestone(id: id, personId: 1, description: description, category: "interview", context: "Asked Q\(questionId)")
            .merging(["interviewId": interviewId, "questionId": questionId]) { _, new in new }
    }

    private static func bundle() throws -> GetPersonInterviewsResponseDTO {
        try decode(GetPersonInterviewsResponseDTO.self, [
            "person": Fixture.person(id: 1, name: "Clara", birthday: "2018-05-10T00:00:00Z"),
            "interviews": [
                iv(1, "2023-05-10T00:00:00Z", [10, 11, 12]),
                iv(2, "2024-05-10T00:00:00Z", [10, 11], [11]),
                iv(3, "2025-05-10T00:00:00Z", [10, 11, 13]),
            ],
            "questions": [
                q(13, "Fun", 0, oneOff: true),
                q(10, "Favorites", 1),
                q(11, "Favorites", 2),
                q(12, "People", 3, archived: true),
            ],
            "answers": [
                a(1, 1, 10, "Pizza"),
                a(2, 2, 10, "pizza!"),
                a(3, 3, 10, "Tacos"),
                a(4, 1, 11, "blue"),
                a(5, 3, 11, "Blue"),
                a(6, 1, 12, "Sam"),
                a(7, 3, 13, "a dragon"),
            ],
        ] as [String: Any])
    }

    @Test("The grid lays questions out by section, one-offs last, and marks changes")
    func grid() throws {
        let sections = Interviews.grid(try Self.bundle())
        #expect(sections.map(\.name) == ["Favorites", "People", Interviews.alsoAsked])
        let food = sections[0].rows[0]
        #expect(food.cells.map(\.trend) == [.first, .same, .changed])
        let color = sections[0].rows[1]
        #expect(color.cells.map(\.trend) == [.first, .none, .same])
        #expect(color.cells.map(\.skipped) == [false, true, false])
        #expect(sections[1].rows[0].cells.map(\.asked) == [true, false, false])
        #expect(food.label == "Asked Q10")
    }

    @Test("Timelines follow each question by age and sort by consistency or change")
    func timelines() throws {
        let timelines = Interviews.timelines(try Self.bundle())
        #expect(timelines[0].points.map(\.age) == [5, 6, 7])
        #expect(timelines[0].points.map(\.answer.descriptionText) == ["Pizza", "pizza!", "Tacos"])
        #expect(timelines.map(\.streak) == [2, 2, 1, 1])
        #expect(timelines.map(\.distinct) == [2, 1, 1, 1])
        #expect(Interviews.sorted(timelines, by: .changed).first?.question.id == 10)
        #expect(Interviews.sorted(timelines, by: .consistent).first?.question.id == 10)
        #expect(Interviews.sorted(timelines, by: .list).map(\.question.id) == timelines.map(\.question.id))
        #expect(Interviews.filtered(timelines, query: "TACO").map(\.question.id) == [10])
        #expect(Interviews.filtered(timelines, query: "q12").map(\.question.id) == [12])
    }

    @Test("A column is the age and year it was asked")
    func columnLabel() throws {
        let bundle = try Self.bundle()
        #expect(Interviews.columnLabel(bundle.interviews[2], birthday: bundle.person.birthday) == "Age 7 · 2025")
        #expect(Interviews.columnLabel(bundle.interviews[2], birthday: nil) == "2025")
    }

    @Test("Comparing lines each person's answers up by age")
    func byAge() throws {
        func row(_ id: Int, _ name: String, _ answers: [(Int, String)]) -> [String: Any] {
            [
                "person": Fixture.person(id: id, name: name),
                "answers": answers.enumerated().map { i, answer in
                    ["ageYears": answer.0, "text": answer.1, "milestoneId": id * 10 + i, "date": "2025-05-10T00:00:00Z"] as [String: Any]
                },
            ]
        }
        let response = try Self.decode(CompareInterviewAnswersResponseDTO.self, [
            "question": Self.q(10, "Favorites", 1),
            "rows": [row(1, "Clara", [(6, "pizza"), (7, "tacos")]), row(2, "Ben", [(6, "sushi")])],
        ] as [String: Any])
        let groups = Interviews.byAge(response.rows)
        #expect(groups.map(\.age) == [6, 7])
        #expect(groups.map { $0.answers.map { "\($0.person.name): \($0.text)" } } == [["Clara: pizza", "Ben: sushi"], ["Clara: tacos"]])
        #expect(!groups[0].allSame)
    }
}
