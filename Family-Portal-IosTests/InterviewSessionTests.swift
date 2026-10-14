import Foundation
import Testing
@testable import Family_Portal_Ios

/// The conduct screen's saving, against a fake backend: what `ask.tsx` promises — an answer saves on moving on, a draft survives leaving, a dropped connection retries quietly, and Finish waits for every answer.
@MainActor
@Suite("Interview session")
struct InterviewSessionTests {

    private static func service(_ server: FakeHTTPServer) -> InterviewService {
        InterviewService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("InterviewSession-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }

    private static func drafts() -> InterviewDrafts {
        let name = "InterviewSessionTests-\(UUID().uuidString)"
        return InterviewDrafts(defaults: UserDefaults(suiteName: name)!)
    }

    private static func interviewJSON(skipped: [Int] = [], status: String = "in-progress", version: Int = 1) -> [String: Any] {
        [
            "id": 9, "familyId": 7, "personId": 1, "date": "2025-05-03T00:00:00Z", "title": "",
            "source": "conducted", "status": status, "questionIds": [10, 11, 12], "skippedIds": skipped,
            "photoId": 0, "notes": "", "version": version,
        ]
    }

    private static func answerJSON(_ id: Int, question: Int, text: String) -> [String: Any] {
        Fixture.milestone(id: id, personId: 1, description: text, category: "interview", milestoneDate: "2025-05-03T00:00:00Z", context: "q\(question)")
            .merging(["interviewId": 9, "questionId": question]) { _, new in new }
    }

    private static func response(answers: [[String: Any]] = [], skipped: [Int] = []) throws -> GetInterviewResponseDTO {
        try APIClient.decode(GetInterviewResponseDTO.self, from: Fixture.data([
            "interview": interviewJSON(skipped: skipped),
            "person": Fixture.person(id: 1, name: "Clara", birthday: "2018-05-10T00:00:00Z"),
            "questions": [10, 11, 12].map { ["id": $0, "familyId": 7, "text": "q\($0)", "section": "Favorites"] },
            "answers": answers,
            "previous": [String: Any](),
        ] as [String: Any]))
    }

    private static func body(_ request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    /// Saves run as their own tasks; wait for what they leave behind.
    private static func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Opening

    @Test("It opens on the first question not yet asked")
    func opensOnFirstPending() throws {
        let server = FakeHTTPServer()
        let session = InterviewSession(
            try Self.response(answers: [Self.answerJSON(40, question: 10, text: "pizza")], skipped: [11]),
            service: Self.service(server), drafts: Self.drafts()
        )
        #expect(session.index == 2)
        #expect(session.text[10] == "pizza")
        #expect(session.status(of: 11) == .skipped)
    }

    @Test("A draft left unsaved is back on the way in")
    func restoresDraft() throws {
        let drafts = Self.drafts()
        drafts.save("Goldfish cr", interviewId: 9, questionId: 10)
        let session = InterviewSession(try Self.response(), service: Self.service(FakeHTTPServer()), drafts: drafts)
        #expect(session.text[10] == "Goldfish cr")
    }

    // MARK: - Saving

    @Test("Moving on saves the answer and clears its draft")
    func movingOnSaves() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveInterviewAnswer", respond: .json([
            "interview": Self.interviewJSON(), "answer": Self.answerJSON(40, question: 10, text: "Goldfish"),
        ]))
        let drafts = Self.drafts()
        let session = InterviewSession(try Self.response(), service: Self.service(server), drafts: drafts)

        session.edit(10, to: "  Goldfish ")
        session.next()
        await Self.eventually { session.answers[10] != nil }

        let body = try Self.body(try #require(server.requests(for: "rpc/SaveInterviewAnswer").first))
        #expect(body["answer"] as? String == "Goldfish")
        #expect(body["skipped"] as? Bool == false)
        #expect(session.index == 1)
        #expect(drafts.drafts(interviewId: 9).isEmpty)
    }

    @Test("Moving past an unchanged answer sends nothing")
    func unchangedIsNotSent() async throws {
        let server = FakeHTTPServer()
        let session = InterviewSession(try Self.response(), service: Self.service(server), drafts: Self.drafts())
        session.next()
        try await Task.sleep(for: .milliseconds(50))
        #expect(server.requests(for: "rpc/SaveInterviewAnswer").isEmpty)
    }

    @Test("Skip records the question as passed, with no answer")
    func skipIsRecorded() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveInterviewAnswer", respond: .json(["interview": Self.interviewJSON(skipped: [10])]))
        let session = InterviewSession(try Self.response(), service: Self.service(server), drafts: Self.drafts())

        session.edit(10, to: "half typed")
        session.skip()
        await Self.eventually { session.status(of: 10) == .skipped }

        let body = try Self.body(try #require(server.requests(for: "rpc/SaveInterviewAnswer").first))
        #expect(body["skipped"] as? Bool == true)
        #expect(body["answer"] as? String == "")
        #expect(session.text[10] == "")
        #expect(session.index == 1)
    }

    @Test("A dropped connection retries quietly until the answer saves")
    func retriesOffline() async throws {
        let server = FakeHTTPServer()
        server.routeSequence("rpc/SaveInterviewAnswer", [
            .offline(),
            .json(["interview": Self.interviewJSON(), "answer": Self.answerJSON(40, question: 10, text: "Goldfish")]),
        ])
        let drafts = Self.drafts()
        let session = InterviewSession(try Self.response(), service: Self.service(server), drafts: drafts, retryDelay: .milliseconds(20))

        session.edit(10, to: "Goldfish")
        session.next()
        await Self.eventually { session.answers[10] != nil }

        #expect(server.requests(for: "rpc/SaveInterviewAnswer").count == 2)
        #expect(session.failed.isEmpty)
        #expect(session.error == nil)
        #expect(drafts.drafts(interviewId: 9).isEmpty)
    }

    @Test("An answer the server refuses is reported, not retried, and its draft kept")
    func refusalIsReported() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveInterviewAnswer", respond: .status(400, message: "That answer is too long"))
        let drafts = Self.drafts()
        let session = InterviewSession(try Self.response(), service: Self.service(server), drafts: drafts, retryDelay: .milliseconds(20))

        session.edit(10, to: "far too long")
        session.next()
        await Self.eventually { session.error != nil }
        try await Task.sleep(for: .milliseconds(80))

        #expect(server.requests(for: "rpc/SaveInterviewAnswer").count == 1)
        #expect(session.failed.isEmpty)
        #expect(drafts.drafts(interviewId: 9)[10] == "far too long")
    }

    // MARK: - Finishing

    @Test("Finish saves what is on screen, then marks the interview complete")
    func finishCompletes() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveInterviewAnswer", respond: .json([
            "interview": Self.interviewJSON(), "answer": Self.answerJSON(40, question: 10, text: "Goldfish"),
        ]))
        server.route("rpc/UpdateInterview", respond: .json(["interview": Self.interviewJSON(status: "complete", version: 2)]))
        let session = InterviewSession(try Self.response(), service: Self.service(server), drafts: Self.drafts())

        session.edit(10, to: "Goldfish")
        let finished = await session.finish()

        #expect(finished)
        #expect(server.requests(for: "rpc/SaveInterviewAnswer").count == 1)
        let update = try Self.body(try #require(server.requests(for: "rpc/UpdateInterview").first))
        #expect(update["status"] as? String == "complete")
        #expect(update["version"] as? Int == 1)
        #expect(update["date"] as? String == "2025-05-03")
        #expect(!session.interview.isInProgress)
    }

    @Test("Finish stops when an answer could not be saved")
    func finishWaitsForAnswers() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveInterviewAnswer", respond: .offline())
        let session = InterviewSession(try Self.response(), service: Self.service(server), drafts: Self.drafts(), retryDelay: .seconds(60))

        session.edit(10, to: "Goldfish")
        let finished = await session.finish()

        #expect(!finished)
        #expect(session.error == Copy.interview.ask.unsavedOnFinish)
        #expect(server.requests(for: "rpc/UpdateInterview").isEmpty)
    }

    // MARK: - Follow-ups

    @Test("A follow-up goes in after the current question and is asked next")
    func followUp() async throws {
        let server = FakeHTTPServer()
        var interview = Self.interviewJSON()
        interview["questionIds"] = [10, 99, 11, 12]
        server.route("rpc/AddInterviewQuestion", respond: .json([
            "interview": interview,
            "question": ["id": 99, "familyId": 7, "text": "Why pizza?", "section": "Also asked", "oneOff": true],
        ]))
        let session = InterviewSession(try Self.response(), service: Self.service(server), drafts: Self.drafts())

        let added = await session.addFollowUp("Why pizza?", keep: false)

        #expect(added)
        #expect(session.questions.map(\.id) == [10, 99, 11, 12])
        #expect(session.current?.id == 99)
        let body = try Self.body(try #require(server.requests(for: "rpc/AddInterviewQuestion").first))
        #expect(body["afterQuestionId"] as? Int == 10)
        #expect(body["keep"] as? Bool == false)
    }

    @Test("Retrying is for a lost connection or a failing server, never a refusal")
    func retryable() {
        #expect(InterviewSession.isRetryable(URLError(.notConnectedToInternet)))
        #expect(InterviewSession.isRetryable(APIError.server(statusCode: 503, message: nil)))
        #expect(!InterviewSession.isRetryable(APIError.server(statusCode: 400, message: "Question not found or not in your family")))
    }
}
