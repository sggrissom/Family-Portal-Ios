import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/interviews.test.ts, plus how answers decode, store and fold on the phone.
@MainActor
@Suite("Interviews")
struct InterviewsTests {

    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try APIClient.decode(T.self, from: Fixture.data(object))
    }

    /// An answer as the server sends one: `interviewId` and `questionId` only when set, as `omitempty` leaves them.
    private func answer(_ id: Int, interview: Int, question: Int = 1, text: String? = nil, context: String = "What's your favorite food?") throws -> MilestoneDTO {
        var json = Fixture.milestone(id: id, personId: 1, description: text ?? "a\(id)", category: interview > 0 ? "interview" : "first", milestoneDate: "2025-05-10T00:00:00Z", context: context)
        if interview > 0 {
            json["interviewId"] = interview
            json["questionId"] = question
        }
        return try decode(MilestoneDTO.self, json)
    }

    private func interview(id: Int = 9, title: String = "", skipped: [Int] = [2]) throws -> InterviewDTO {
        try decode(InterviewDTO.self, [
            "id": id, "familyId": 7, "personId": 1, "date": "2025-05-03T00:00:00Z",
            "title": title, "status": "complete", "questionIds": [1, 2, 3], "skippedIds": skipped,
        ] as [String: Any])
    }

    private func question(_ id: Int, _ section: String = "Favorites", text: String? = nil) throws -> InterviewQuestionDTO {
        try decode(InterviewQuestionDTO.self, ["id": id, "text": text ?? "q\(id)", "section": section] as [String: Any])
    }

    // MARK: - Pure logic

    @Test("Ages count whole years, turning over on the birthday itself")
    func ageYears() {
        let birthday = Self.date("2018-05-10T00:00:00Z")
        #expect(Interviews.ageYears(birthday: birthday, at: Self.date("2025-05-09T00:00:00Z")) == 6)
        #expect(Interviews.ageYears(birthday: birthday, at: Self.date("2025-05-10T00:00:00Z")) == 7)
        #expect(Interviews.ageYears(birthday: birthday, at: Self.date("2017-01-01T00:00:00Z")) == 0)
        #expect(Interviews.ageYears(birthday: nil, at: Self.date("2025-05-10T00:00:00Z")) == 0)
    }

    @Test("A title is the interview's own, else the first name and age")
    func title() throws {
        let birthday = Self.date("2018-05-10T00:00:00Z")
        #expect(Interviews.title(try interview(), personName: "Clara Whitfield", birthday: birthday) == "Clara's interview at 6")
        #expect(Interviews.title(try interview(title: "Birthday interview"), personName: "Clara Whitfield", birthday: birthday) == "Birthday interview")
    }

    @Test("A question is answered, skipped or pending")
    func status() throws {
        let sitting = try interview()
        #expect([1, 2, 3].map { Interviews.status(of: $0, in: sitting, answered: [1]) } == [.answered, .skipped, .pending])
    }

    @Test("Answers group by interview and other moments stay loose")
    func fold() throws {
        let items = try [answer(5, interview: 2), answer(1, interview: 0), answer(3, interview: 2), answer(4, interview: 9), answer(2, interview: 0)]
        let (groups, loose) = Interviews.fold(items)
        #expect(groups.map(\.interviewId) == [2, 9])
        #expect(groups.map { $0.answers.map(\.id) } == [[3, 5], [4]])
        #expect(loose.map(\.id) == [1, 2])
    }

    @Test("Questions shorten for a card's preview lines")
    func shortQuestion() {
        #expect(Interviews.shortQuestion("What's your favorite food?") == "favorite food")
        #expect(Interviews.shortQuestion("Who is your best friend?") == "best friend")
        #expect(Interviews.shortQuestion("What do you want to be when you grow up?") == "What do you want to be when you grow up")
    }

    @Test("Answers compare without case, punctuation or accents")
    func normalize() {
        #expect(Interviews.normalizeAnswer("  Crème brûlée!! ") == "creme brulee")
        #expect(Interviews.normalizeAnswer("Pizza.") == Interviews.normalizeAnswer("pizza"))
    }

    @Test("What changed is measured against the most recent earlier interview")
    func changes() throws {
        let questions = try [question(10), question(11)]
        let answers = try [10: answer(1, interview: 9, question: 10, text: "Tacos"), 11: answer(2, interview: 9, question: 11, text: "blue")]
        func previous(_ interviewId: Int, _ iso: String, _ text: String) throws -> PreviousAnswerDTO {
            try decode(PreviousAnswerDTO.self, ["interviewId": interviewId, "date": iso, "text": text] as [String: Any])
        }
        let earlier = try [
            10: [previous(2, "2024-05-10T00:00:00Z", "pizza"), previous(1, "2023-05-10T00:00:00Z", "pizza")],
            11: [previous(1, "2023-05-10T00:00:00Z", "green")],
        ]
        let changes = Interviews.changesSincePrevious(questions: questions, answers: answers, previous: { earlier[$0] ?? [] })
        #expect(changes.map { [$0.before, $0.after] } == [["pizza", "Tacos"]])
        #expect(changes.first?.question == "What's your favorite food?")
        #expect(Interviews.changesSincePrevious(questions: questions, answers: answers, previous: { _ in [] }).isEmpty)
    }

    // MARK: - Wire

    @Test("An interview decodes with its answers and previous answers keyed by question")
    func decodesInterview() throws {
        let payload: [String: Any] = [
            "interview": [
                "id": 9, "familyId": 7, "personId": 1, "date": "2025-05-03T00:00:00Z", "title": "",
                "source": "conducted", "status": "in-progress", "questionIds": [10, 11], "skippedIds": NSNull(),
                "photoId": 0, "notes": "", "version": 3,
            ] as [String: Any],
            "person": Fixture.person(id: 1, name: "Clara"),
            "questions": [["id": 10, "familyId": 7, "text": "What's your favorite food?", "section": "Favorites", "defaultKey": "fav-food"]],
            "answers": [
                Fixture.milestone(id: 40, personId: 1, description: "Tacos", category: "interview", context: "What's your favorite food?")
                    .merging(["interviewId": 9, "questionId": 10]) { _, new in new },
            ],
            "previous": ["10": [["interviewId": 4, "milestoneId": 31, "date": "2024-05-03T00:00:00Z", "ageYears": 5, "text": "pizza"]]],
        ]
        let response = try decode(GetInterviewResponseDTO.self, payload)
        #expect(response.interview.isInProgress)
        #expect(response.interview.skippedIds.isEmpty)
        #expect(response.interview.version == 3)
        #expect(response.questions.map(\.defaultKey) == ["fav-food"])
        #expect(response.answers.map(\.interviewId) == [9])
        #expect(response.answers.map(\.questionId) == [10])
        #expect(response.previous(for: 10).map(\.text) == ["pizza"])
        #expect(response.previous(for: 11).isEmpty)
    }

    @Test("An ordinary moment reads as no interview")
    func ordinaryMomentHasNoInterview() throws {
        let moment = try answer(1, interview: 0)
        #expect(moment.interviewId == 0)
        #expect(moment.questionId == 0)
    }

    @Test("An update sends the whole interview back with the change")
    func updateRequest() throws {
        let sitting = try interview(title: "Birthday")
        let request = UpdateInterviewRequestDTO(sitting, notes: "Very silly")
        #expect(request.id == 9)
        #expect(request.date == "2025-05-03")
        #expect(request.title == "Birthday")
        #expect(request.notes == "Very silly")
        #expect(request.status == "complete")
    }

    // MARK: - Store

    @Test("A synced answer keeps its category, interview and question")
    func mapsAnswer() throws {
        let dto = try answer(40, interview: 9, question: 10)
        let milestone = Milestone(descriptionText: "", category: .other, date: Date())
        applyMilestoneDTO(dto, to: milestone)
        #expect(milestone.category == .interview)
        #expect(milestone.interviewId == 9)
        #expect(milestone.questionId == 10)
        #expect(milestone.context == "What's your favorite food?")
    }

    @Test("Editing an answer keeps its question")
    func editKeepsQuestion() {
        let milestone = Milestone(descriptionText: "pizza", category: .interview, date: Date())
        milestone.context = "What's your favorite food?"
        milestone.setEntry(" tacos ", context: "")
        #expect(milestone.descriptionText == "tacos")
        #expect(milestone.context == "What's your favorite food?")
    }

    @Test("No category picker offers interview")
    func pickable() {
        #expect(!MilestoneCategory.pickable.contains(.interview))
        #expect(MilestoneCategory.pickable.count == MilestoneCategory.allCases.count - 1)
    }

    @Test("A day folds an interview's answers into one card")
    func daySummaryFolds() throws {
        let context = try TestStore.makeContext()
        let clara = Person(name: "Clara", gender: .female, birthday: Self.date("2018-05-10T00:00:00Z"), isPregnancy: false)
        context.insert(clara)
        func moment(_ serverId: Int, interviewId: Int) -> Milestone {
            let milestone = Milestone(descriptionText: "a\(serverId)", category: interviewId > 0 ? .interview : .first, date: Self.date("2025-05-10T00:00:00Z"))
            context.insert(milestone)
            milestone.person = clara
            milestone.remoteId = String(serverId)
            milestone.interviewId = interviewId
            return milestone
        }
        let days = DaySummaries.summarize(DayRecords(milestones: [moment(2, interviewId: 2), moment(1, interviewId: 2), moment(3, interviewId: 0)]), people: [clara])
        #expect(days.count == 1)
        #expect(days[0].milestones.map(\.descriptionText) == ["a3"])
        #expect(days[0].interviews.count == 1)
        #expect(days[0].interviews[0].answers.map(\.descriptionText) == ["a1", "a2"])
    }
}
