import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Interview answer notes")
struct InterviewAnswerNoteTests {

    @Test("An answer's note decodes, and every other moment reads empty")
    func decodesNote() throws {
        let withNote = Fixture.milestone(id: 1, personId: 1, description: "yellow", category: "interview", milestoneDate: "2025-05-03T00:00:00Z", context: "Favorite color?")
            .merging(["interviewId": 9, "questionId": 10, "note": "said while giggling"]) { _, new in new }
        let plain = Fixture.milestone(id: 2, personId: 1, description: "Walked", category: "first", milestoneDate: "2025-05-03T00:00:00Z")
        let decoded = try APIClient.decode([MilestoneDTO].self, from: Fixture.data([withNote, plain]))
        #expect(decoded.map(\.note) == ["said while giggling", ""])
    }

    @Test("Compare carries each answer's note into its age group")
    func compareCarriesNote() throws {
        let rows = try APIClient.decode([CompareRowDTO].self, from: Fixture.data([[
            "person": Fixture.person(id: 1, name: "Clara", birthday: "2018-05-10T00:00:00Z"),
            "answers": [
                ["interviewId": 9, "milestoneId": 1, "date": "2025-05-03T00:00:00Z", "ageYears": 6, "text": "yellow", "note": "giggling"],
                ["interviewId": 8, "milestoneId": 2, "date": "2024-05-03T00:00:00Z", "ageYears": 5, "text": "pink"],
            ],
        ] as [String: Any]]))
        let groups = Interviews.byAge(rows)
        #expect(groups.map(\.age) == [5, 6])
        #expect(groups.map { $0.answers[0].note } == ["", "giggling"])
    }

    @Test("Setting a note sends the interview, question and note")
    func setNote() async throws {
        let server = FakeHTTPServer()
        let answer = Fixture.milestone(id: 1, personId: 1, description: "yellow", category: "interview", milestoneDate: "2025-05-03T00:00:00Z")
            .merging(["interviewId": 9, "questionId": 10, "note": "giggling"]) { _, new in new }
        server.route("rpc/SetInterviewAnswerNote", respond: .json(["answer": answer]))
        let service = InterviewService(apiClient: server.apiClient(), cache: ActivitySnapshotCache(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("AnswerNote-\(UUID().uuidString)", isDirectory: true)
        ))

        let saved = try await service.setAnswerNote(SetInterviewAnswerNoteRequestDTO(interviewId: 9, questionId: 10, note: "giggling"))

        #expect(saved.note == "giggling")
        let request = try #require(server.requests(for: "rpc/SetInterviewAnswerNote").first)
        let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["interviewId"] as? Int == 9)
        #expect(body["questionId"] as? Int == 10)
        #expect(body["note"] as? String == "giggling")
    }
}
