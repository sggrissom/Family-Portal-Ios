import Foundation

/// The annual interview (backend/interview*.go). Reads are online-first through `ActivitySnapshotCache`, like books, so an interview opened once can be read again offline. Writes are online only and never queued: `UpdateInterview` carries a version that only means something now, and the answers themselves are moments only the server may create.
/// The answer moments also arrive in the ordinary pull. After a write that changes them here, the caller pulls, so the store catches up rather than showing the old answers until the next sync.
@Observable
@MainActor
final class InterviewService {

    private let apiClient: APIClient
    private let cache: ActivitySnapshotCache

    init(apiClient: APIClient = .shared, cache: ActivitySnapshotCache = .shared) {
        self.apiClient = apiClient
        self.cache = cache
    }

    // MARK: - Reads

    func interview(id: Int) -> ActivityRead<GetInterviewResponseDTO> {
        cache.read(.getInterview, payload: GetInterviewRequestDTO(id: id), key: ActivitySnapshotKey(.getInterview, id), apiClient: apiClient)
    }

    func personInterviews(personId: Int) -> ActivityRead<GetPersonInterviewsResponseDTO> {
        cache.read(.getPersonInterviews, payload: GetPersonInterviewsRequestDTO(personId: personId), key: ActivitySnapshotKey(.getPersonInterviews, personId), apiClient: apiClient)
    }

    /// Keyed on nothing but the proc: the page is the whole family, and `today` only moves who is due.
    func familyInterviews(today: String) -> ActivityRead<GetFamilyInterviewsResponseDTO> {
        cache.read(.getFamilyInterviews, payload: GetFamilyInterviewsRequestDTO(today: today), key: ActivitySnapshotKey(.getFamilyInterviews), apiClient: apiClient)
    }

    func compare(questionId: Int) -> ActivityRead<CompareInterviewAnswersResponseDTO> {
        cache.read(.compareInterviewAnswers, payload: CompareInterviewAnswersRequestDTO(questionId: questionId, personIds: []), key: ActivitySnapshotKey(.compareInterviewAnswers, questionId), apiClient: apiClient)
    }

    // MARK: - Writes

    /// `ErrInterviewChanged`, word for word: someone else saved first.
    static let changedMessage = "Someone else changed this interview after you opened it. Reload to see their changes."

    static func isChangedConflict(_ error: Error) -> Bool {
        guard case APIError.server(_, let message) = error else { return false }
        return message?.trimmingCharacters(in: .whitespacesAndNewlines) == changedMessage
    }

    /// Not cached: setup is asked once, just before a start, and an in-progress interview it missed would start a second one the server refuses.
    func setup(personId: Int) async throws -> GetInterviewSetupResponseDTO {
        try await apiClient.callRPC(.getInterviewSetup, payload: GetInterviewSetupRequestDTO(personId: personId))
    }

    func start(_ request: StartInterviewRequestDTO) async throws -> InterviewDTO {
        let response: InterviewResponseDTO = try await apiClient.callRPC(.startInterview, payload: request)
        return response.interview
    }

    func saveAnswer(_ request: SaveInterviewAnswerRequestDTO) async throws -> SaveInterviewAnswerResponseDTO {
        try await apiClient.callRPC(.saveInterviewAnswer, payload: request)
    }

    func addQuestion(_ request: AddInterviewQuestionRequestDTO) async throws -> AddInterviewQuestionResponseDTO {
        try await apiClient.callRPC(.addInterviewQuestion, payload: request)
    }

    /// A portrait goes straight to the server rather than through the upload queue: the interview needs its id now, and the conduct screen is online anyway.
    func uploadPortrait(_ imageData: Data, personId: Int) async throws -> ImageDTO {
        try await PhotoSyncService(apiClient: apiClient).uploadPhoto(
            imageData: imageData,
            title: "",
            description: "",
            photoDate: Date().localWallClock(),
            personIds: [personId]
        )
    }

    func updateInterview(_ request: UpdateInterviewRequestDTO) async throws -> InterviewDTO {
        let response: InterviewResponseDTO = try await apiClient.callRPC(.updateInterview, payload: request)
        return response.interview
    }

    func deleteInterview(id: Int) async throws {
        let _: DeleteInterviewResponseDTO = try await apiClient.callRPC(.deleteInterview, payload: DeleteInterviewRequestDTO(id: id))
    }
}
