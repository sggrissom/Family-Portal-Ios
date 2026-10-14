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
