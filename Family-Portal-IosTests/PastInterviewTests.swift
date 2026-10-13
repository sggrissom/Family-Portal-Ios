import Foundation
import Testing
@testable import Family_Portal_Ios

/// Typing in a past interview: what the form sends — the web's `past.tsx` `save`.
@MainActor
@Suite("Past interviews")
struct PastInterviewTests {

    private static func question(_ id: Int, key: String = "") throws -> InterviewQuestionDTO {
        try APIClient.decode(InterviewQuestionDTO.self, from: Fixture.data(["id": id, "text": "q\(id)", "section": "Favorites", "defaultKey": key] as [String: Any]))
    }

    @Test("Blank answers are not sent; listed ones go by ref in list order, then the extras")
    func importAnswers() throws {
        let questions = try [Self.question(10), Self.question(0, key: "fav-food"), Self.question(11)]
        var draft = PastInterviewDraft()
        draft.answers = ["id:11": "blue", "key:fav-food": "  pasta ", "id:10": "   "]
        draft.extras = [
            PastInterviewDraft.Extra(question: "Favorite dinosaur", answer: "T. rex", keep: false),
            PastInterviewDraft.Extra(question: "Half typed", answer: "", keep: true),
        ]

        #expect(draft.filled == 3)
        #expect(draft.importAnswers(listOrder: questions) == [
            ImportAnswerDTO(ref: "key:fav-food", answer: "pasta", newText: "", keep: false),
            ImportAnswerDTO(ref: "id:11", answer: "blue", newText: "", keep: false),
            ImportAnswerDTO(ref: "", answer: "T. rex", newText: "Favorite dinosaur", keep: false),
        ])
    }

    @Test("An age is sent for the server to resolve against the birthday")
    func ageRequest() throws {
        let interview = HistoricalInterviewDTO(inputType: "age", date: "", ageYears: 4, ageMonths: 0, title: "", notes: "", answers: [])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SaveHistoricalInterviewRequestDTO(personId: 7, interview: interview))) as? [String: Any]
        let body = try #require(json?["interview"] as? [String: Any])
        #expect(json?["personId"] as? Int == 7)
        #expect(body["inputType"] as? String == "age")
        #expect(body["ageYears"] as? Int == 4)
        #expect((body["answers"] as? [Any])?.isEmpty == true)
    }

    @Test("Saving goes to SaveHistoricalInterview and answers with the new interview")
    func saves() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveHistoricalInterview", respond: .json(["interview": [
            "id": 21, "familyId": 7, "personId": 1, "date": "2022-05-10T00:00:00Z", "source": "historical", "status": "complete",
        ] as [String: Any]]))
        let service = InterviewService(apiClient: server.apiClient(), cache: ActivitySnapshotCache(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("PastInterview-\(UUID().uuidString)", isDirectory: true)
        ))
        let interview = try await service.saveHistorical(SaveHistoricalInterviewRequestDTO(
            personId: 1,
            interview: HistoricalInterviewDTO(inputType: "date", date: "2022-05-10", ageYears: 0, ageMonths: 0, title: "", notes: "", answers: [
                ImportAnswerDTO(ref: "id:10", answer: "pizza", newText: "", keep: false),
            ])
        ))
        #expect(interview.id == 21)
        #expect(server.requests(for: "rpc/SaveHistoricalInterview").count == 1)
    }
}
