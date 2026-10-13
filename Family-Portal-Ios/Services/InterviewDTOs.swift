import Foundation

// The annual interview (backend/interview*.go). An answer is an ordinary `MilestoneDTO` with `category: "interview"`; these are the sitting and the family's question list, which live on the server only.

/// One sitting: who was interviewed, when, which questions were planned and which were skipped. Answers are never copied here — they are the answer moments.
nonisolated struct InterviewDTO: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    @OrZero var familyId: Int
    @OrZero var personId: Int
    let date: Date
    @OrZero var title: String
    /// "conducted" or "historical".
    @OrZero var source: String
    /// "in-progress" or "complete".
    @OrZero var status: String
    @OrZero var questionIds: [Int]
    @OrZero var skippedIds: [Int]
    @OrZero var photoId: Int
    @OrZero var notes: String
    /// The save check `UpdateInterview` compares, like a book's revision.
    @OrZero var version: Int

    static let inProgress = "in-progress"
    static let complete = "complete"

    var isInProgress: Bool { status == Self.inProgress }
}

/// A question on the family's list. Its id survives rewording, which is what lines answers up across years. `text` may hold `{name}` and `{age}`; inside an interview it arrives already rendered.
nonisolated struct InterviewQuestionDTO: Codable, Sendable, Hashable, Identifiable {
    /// 0 for a built-in the family has not saved yet; `defaultKey` names it then.
    let id: Int
    @OrZero var familyId: Int
    let text: String
    @OrZero var section: String
    @OrZero var position: Int
    @OrZero var minAgeYears: Int
    @OrZero var maxAgeYears: Int
    @OrZero var defaultKey: String
    @OrZero var archived: Bool
    /// Added for one interview, not on the list. They collect under "Also asked".
    @OrZero var oneOff: Bool
}

/// An earlier answer to the same question by the same person, newest first.
nonisolated struct PreviousAnswerDTO: Codable, Sendable, Hashable {
    @OrZero var interviewId: Int
    @OrZero var milestoneId: Int
    let date: Date
    @OrZero var ageYears: Int
    @OrZero var text: String
}

nonisolated struct GetInterviewRequestDTO: Encodable, Sendable {
    let id: Int
}

/// Everything one interview's page and its conduct screen need, in one call.
nonisolated struct GetInterviewResponseDTO: Decodable, Sendable {
    let interview: InterviewDTO
    let person: PersonDTO
    @OrZero var questions: [InterviewQuestionDTO]
    @OrZero var answers: [MilestoneDTO]
    /// Keyed by question id. Go marshals an `int` map key as a string, so it is read as one and looked up through `previous(for:)`.
    @OrZero var previous: [String: [PreviousAnswerDTO]]

    func previous(for questionId: Int) -> [PreviousAnswerDTO] {
        previous[String(questionId)] ?? []
    }
}

nonisolated struct InterviewResponseDTO: Decodable, Sendable {
    let interview: InterviewDTO
}

/// The whole sitting is sent back on every change: `UpdateInterview` assigns each field, so an omitted one is cleared.
nonisolated struct UpdateInterviewRequestDTO: Encodable, Sendable {
    let id: Int
    let version: Int
    /// `YYYY-MM-DD`.
    let date: String
    let title: String
    let notes: String
    let photoId: Int
    let status: String

    init(_ interview: InterviewDTO, date: String? = nil, title: String? = nil, notes: String? = nil, photoId: Int? = nil, status: String? = nil) {
        id = interview.id
        version = interview.version
        self.date = date ?? interview.date.recordDayKey
        self.title = title ?? interview.title
        self.notes = notes ?? interview.notes
        self.photoId = photoId ?? interview.photoId
        self.status = status ?? interview.status
    }
}

nonisolated struct DeleteInterviewRequestDTO: Encodable, Sendable {
    let id: Int
}

nonisolated struct DeleteInterviewResponseDTO: Decodable, Sendable {
    @OrZero var personId: Int
}

// MARK: - Conduct

nonisolated struct GetInterviewSetupRequestDTO: Encodable, Sendable {
    let personId: Int
}

/// The setup screen's one call: the family's list (or the built-in one, unsaved), and any interview already in progress for this person.
nonisolated struct GetInterviewSetupResponseDTO: Decodable, Sendable {
    let person: PersonDTO
    @OrZero var questions: [InterviewQuestionDTO]
    @OrZero var retired: [InterviewQuestionDTO]
    /// `id` 0 when there is none — Go sends the zero struct.
    let inProgress: InterviewDTO
    @OrZero var answered: Int
}

/// Saved questions go by id; built-ins the family has never saved go by `defaultKey`, and the server copies the list in on this first write.
nonisolated struct StartInterviewRequestDTO: Encodable, Sendable {
    let personId: Int
    /// `YYYY-MM-DD`.
    let date: String
    let questionIds: [Int]
    let defaultKeys: [String]
    let oneOffQuestions: [String]
}

/// Creates, rewrites or deletes the answer moment: an empty answer deletes it, and `skipped` records the question as passed.
nonisolated struct SaveInterviewAnswerRequestDTO: Encodable, Sendable {
    let interviewId: Int
    let questionId: Int
    let answer: String
    let skipped: Bool
}

nonisolated struct SaveInterviewAnswerResponseDTO: Decodable, Sendable {
    let interview: InterviewDTO
    /// `id` 0 when the answer was cleared or skipped.
    let answer: MilestoneDTO?
}

/// A follow-up, inserted after `afterQuestionId`. `keep` adds it to the family's list; otherwise it is asked just this once.
nonisolated struct AddInterviewQuestionRequestDTO: Encodable, Sendable {
    let interviewId: Int
    let text: String
    let afterQuestionId: Int
    let keep: Bool
}

nonisolated struct AddInterviewQuestionResponseDTO: Decodable, Sendable {
    let interview: InterviewDTO
    let question: InterviewQuestionDTO
}

// MARK: - Looking back

nonisolated struct GetPersonInterviewsRequestDTO: Encodable, Sendable {
    let personId: Int
}

/// Everything the person's Interviews tab needs in one call: their interviews oldest first, every answer, and every question involved.
nonisolated struct GetPersonInterviewsResponseDTO: Decodable, Sendable {
    let person: PersonDTO
    @OrZero var interviews: [InterviewDTO]
    @OrZero var answers: [MilestoneDTO]
    @OrZero var questions: [InterviewQuestionDTO]
}

nonisolated struct GetFamilyInterviewsRequestDTO: Encodable, Sendable {
    /// The device's `YYYY-MM-DD`, which decides who is due around a birthday.
    let today: String
}

/// One person on the family Interviews page: their last finished interview, how many, any in progress, and whether one is due.
nonisolated struct FamilyInterviewRowDTO: Decodable, Sendable, Identifiable {
    let person: PersonDTO
    /// `id` 0 when there is none.
    let last: InterviewDTO
    @OrZero var count: Int
    let inProgress: InterviewDTO
    @OrZero var answered: Int
    @OrZero var due: Bool
    /// Under 18 with a birthday — who the page lists first.
    @OrZero var child: Bool

    var id: Int { person.id }
}

nonisolated struct GetFamilyInterviewsResponseDTO: Decodable, Sendable {
    @OrZero var people: [FamilyInterviewRowDTO]
}

/// `questionId` 0 lets the server pick the first question anyone has answered; empty `personIds` is everyone.
nonisolated struct CompareInterviewAnswersRequestDTO: Encodable, Sendable {
    let questionId: Int
    let personIds: [Int]
}

nonisolated struct CompareRowDTO: Decodable, Sendable, Identifiable {
    let person: PersonDTO
    @OrZero var answers: [PreviousAnswerDTO]

    var id: Int { person.id }
}

nonisolated struct CompareInterviewAnswersResponseDTO: Decodable, Sendable {
    let question: InterviewQuestionDTO
    /// Every question someone visible has answered, for the picker.
    @OrZero var questions: [InterviewQuestionDTO]
    @OrZero var rows: [CompareRowDTO]
}

// MARK: - Past interviews

/// One answer to a past interview. A question on the list goes by `ref` (`id:12`, or `key:fav-food` for an unsaved built-in); one that isn't goes by `newText`, kept on the list when `keep`.
nonisolated struct ImportAnswerDTO: Encodable, Sendable, Equatable {
    let ref: String
    let answer: String
    let newText: String
    let keep: Bool
}

/// When it was — a date, or an age the server resolves against the birthday ("when she was 4" is often all a family knows) — and what was said.
nonisolated struct HistoricalInterviewDTO: Encodable, Sendable {
    /// "date" or "age".
    let inputType: String
    let date: String
    let ageYears: Int
    let ageMonths: Int
    let title: String
    let notes: String
    let answers: [ImportAnswerDTO]
}

nonisolated struct SaveHistoricalInterviewRequestDTO: Encodable, Sendable {
    let personId: Int
    let interview: HistoricalInterviewDTO
}

// MARK: - The question list

nonisolated struct GetInterviewQuestionsRequestDTO: Encodable, Sendable {
    /// 0 is the caller's own family.
    let familyId: Int
}

nonisolated struct QuestionUsageDTO: Decodable, Sendable, Hashable {
    @OrZero var interviews: Int
    @OrZero var answers: Int

    /// Asked or answered before: it can be retired but never deleted.
    var inUse: Bool { interviews > 0 || answers > 0 }
}

/// The family's list, or the built-in one (unsaved, `id` 0) before anyone has saved it.
nonisolated struct InterviewQuestionsResponseDTO: Decodable, Sendable {
    @OrZero var familyId: Int
    /// The save check, like a book's.
    @OrZero var revision: Int
    @OrZero var questions: [InterviewQuestionDTO]
    /// Built-ins added since the family saved its list, offered and never added on their own.
    @OrZero var suggested: [InterviewQuestionDTO]
    @OrZero var defaults: [InterviewQuestionDTO]
    /// By question id; a Go `map[int]…` arrives with string keys.
    @OrZero var usage: [String: QuestionUsageDTO]

    func usage(of questionId: Int) -> QuestionUsageDTO? {
        usage[String(questionId)]
    }
}

nonisolated struct InterviewQuestionInputDTO: Codable, Sendable, Equatable {
    let id: Int
    let text: String
    let section: String
    let minAgeYears: Int
    let maxAgeYears: Int
    let defaultKey: String
    let archived: Bool
}

/// The whole list in its new order. A question left out keeps its place at the end; `deleteIds` are removed, which the server allows only for one never asked.
nonisolated struct SaveInterviewQuestionsRequestDTO: Encodable, Sendable {
    let familyId: Int
    let revision: Int
    let questions: [InterviewQuestionInputDTO]
    let deleteIds: [Int]
}

/// Moves every answer of `fromId` onto `intoId` and retires `fromId`.
nonisolated struct MergeInterviewQuestionsRequestDTO: Encodable, Sendable {
    let fromId: Int
    let intoId: Int
    let revision: Int
}
