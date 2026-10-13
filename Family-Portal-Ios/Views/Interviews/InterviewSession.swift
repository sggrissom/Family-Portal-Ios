import Foundation
import OSLog

/// One interview being asked — the state and the saving behind the web's `ask.tsx`, kept out of the view so it can be driven by a test.
/// Every answer saves as soon as the parent moves on. The words being typed are held as a draft until that save succeeds, and a save that fails for want of a connection retries quietly every few seconds instead of interrupting the conversation.
@Observable
@MainActor
final class InterviewSession {

    private(set) var interview: InterviewDTO
    let person: PersonDTO
    private(set) var questions: [InterviewQuestionDTO]
    private let previous: [String: [PreviousAnswerDTO]]
    /// Saved answers by question id.
    private(set) var answers: [Int: MilestoneDTO]
    /// What each answer field holds now, typed or saved.
    var text: [Int: String] = [:]
    /// The last text the server confirmed, per question.
    private var saved: [Int: String] = [:]
    private var inflight: Set<Int> = []
    /// A save asked for while one was already in flight for the same question: whether it was a skip. Sent when the first returns.
    private var again: [Int: Bool] = [:]
    /// Questions whose save failed and is being retried.
    private(set) var failed: Set<Int> = []
    /// The question on screen; `questions.count` is the finish panel.
    private(set) var index = 0
    private(set) var error: String?
    private(set) var isFinishing = false
    private(set) var isUploading = false
    private(set) var isAddingQuestion = false

    private let service: InterviewService
    private let drafts: InterviewDrafts
    private let retryDelay: Duration

    init(_ response: GetInterviewResponseDTO, service: InterviewService, drafts: InterviewDrafts = InterviewDrafts(), retryDelay: Duration = .seconds(4)) {
        interview = response.interview
        person = response.person
        questions = response.questions
        previous = response.previous
        answers = Dictionary(response.answers.map { ($0.questionId, $0) }, uniquingKeysWith: { first, _ in first })
        self.service = service
        self.drafts = drafts
        self.retryDelay = retryDelay

        for question in questions {
            let answer = answers[question.id]?.descriptionText ?? ""
            text[question.id] = answer
            saved[question.id] = answer
        }
        // A draft that differs from what was saved is what the parent was typing when they left.
        for (questionId, draft) in drafts.drafts(interviewId: interview.id) where text[questionId] != nil && draft != saved[questionId] {
            text[questionId] = draft
        }
        index = questions.firstIndex { status(of: $0.id) == .pending } ?? questions.count
    }

    // MARK: - Reading

    var current: InterviewQuestionDTO? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    var isAtEnd: Bool { index >= questions.count }

    func status(of questionId: Int) -> Interviews.QuestionStatus {
        Interviews.status(of: questionId, in: interview, answered: Set(answers.keys))
    }

    func previous(for questionId: Int) -> [PreviousAnswerDTO] {
        previous[String(questionId)] ?? []
    }

    var pending: [InterviewQuestionDTO] {
        questions.filter { status(of: $0.id) == .pending }
    }

    var title: String {
        Interviews.title(interview, personName: person.name, birthday: person.birthday)
    }

    // MARK: - Moving

    /// Leaves the current question — saving it if it changed — and shows another.
    func go(to newIndex: Int) {
        if let question = current {
            commit(question.id)
        }
        index = max(0, min(newIndex, questions.count))
    }

    func next() { go(to: index + 1) }
    func back() { go(to: index - 1) }

    func edit(_ questionId: Int, to value: String) {
        text[questionId] = value
        drafts.save(value, interviewId: interview.id, questionId: questionId)
    }

    func skip() {
        guard let question = current else { return }
        text[question.id] = ""
        saved[question.id] = ""
        drafts.clear(interviewId: interview.id, questionId: question.id)
        Task { await save(question.id, skipped: true) }
        index = min(index + 1, questions.count)
    }

    /// Saves the answer if it changed. The save runs on its own, so moving on never waits for the network; `finish` awaits the task it gets back.
    @discardableResult
    private func commit(_ questionId: Int) -> Task<Void, Never>? {
        let value = trimmed(text[questionId])
        if value == trimmed(saved[questionId]) {
            drafts.clear(interviewId: interview.id, questionId: questionId)
            return nil
        }
        return Task { await save(questionId, skipped: false) }
    }

    // MARK: - Saving

    private func save(_ questionId: Int, skipped: Bool) async {
        if inflight.contains(questionId) {
            again[questionId] = skipped
            return
        }
        inflight.insert(questionId)
        let value = skipped ? "" : trimmed(text[questionId])
        do {
            let response = try await service.saveAnswer(SaveInterviewAnswerRequestDTO(
                interviewId: interview.id, questionId: questionId, answer: value, skipped: skipped
            ))
            inflight.remove(questionId)
            failed.remove(questionId)
            interview = response.interview
            if let answer = response.answer, answer.id > 0 {
                answers[questionId] = answer
            } else {
                answers[questionId] = nil
            }
            saved[questionId] = value
            if let skip = again.removeValue(forKey: questionId) {
                await save(questionId, skipped: skip)
            } else if trimmed(text[questionId]) == value {
                drafts.clear(interviewId: interview.id, questionId: questionId)
            }
        } catch {
            inflight.remove(questionId)
            guard Self.isRetryable(error) else {
                // The server said no — a removed question, an interview deleted elsewhere, an answer too long. Retrying would only say it again.
                failed.remove(questionId)
                self.error = error.localizedDescription
                return
            }
            AppLog.ui.info("Interview answer not saved, retrying: \(String(describing: error), privacy: .public)")
            failed.insert(questionId)
            Task { [weak self, retryDelay] in
                try? await Task.sleep(for: retryDelay)
                guard let self, self.failed.contains(questionId) else { return }
                await self.save(questionId, skipped: self.again.removeValue(forKey: questionId) ?? skipped)
            }
        }
    }

    /// A connection that dropped or a server that fell over is worth trying again; an answer the server refused is not.
    nonisolated static func isRetryable(_ error: Error) -> Bool {
        switch error {
        case APIError.network: return true
        case APIError.server(let status, _): return status >= 500
        case is URLError: return true
        default: return false
        }
    }

    private func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Follow-ups and portrait

    /// Inserts a question after the current one and shows it.
    func addFollowUp(_ question: String, keep: Bool) async -> Bool {
        let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isAddingQuestion, let after = current else { return false }
        isAddingQuestion = true
        defer { isAddingQuestion = false }
        do {
            let response = try await service.addQuestion(AddInterviewQuestionRequestDTO(
                interviewId: interview.id, text: value, afterQuestionId: after.id, keep: keep
            ))
            interview = response.interview
            let at = (questions.firstIndex { $0.id == after.id } ?? index) + 1
            questions.insert(response.question, at: at)
            text[response.question.id] = ""
            saved[response.question.id] = ""
            go(to: at)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func setPortrait(_ imageData: Data) async {
        isUploading = true
        error = nil
        defer { isUploading = false }
        do {
            let image = try await service.uploadPortrait(imageData, personId: person.id)
            interview = try await service.updateInterview(UpdateInterviewRequestDTO(interview, photoId: image.id))
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Finishing

    /// Saves anything still unsaved, waits for it, then marks the interview complete. False — with `error` set — when an answer could not be saved.
    func finish() async -> Bool {
        isFinishing = true
        defer { isFinishing = false }
        let saves = questions.compactMap { commit($0.id) }
        for save in saves {
            await save.value
        }
        // A save started earlier, when the parent moved on, may still be on the wire. Give it a moment to land, as the web does.
        for _ in 0..<50 where !inflight.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard failed.isEmpty, inflight.isEmpty else {
            error = Copy.interview.ask.unsavedOnFinish
            return false
        }
        do {
            interview = try await service.updateInterview(UpdateInterviewRequestDTO(interview, status: InterviewDTO.complete))
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func dismissError() {
        error = nil
    }
}
