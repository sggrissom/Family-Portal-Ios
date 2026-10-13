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

    // MARK: - Writes

    /// `ErrInterviewChanged`, word for word: someone else saved first.
    static let changedMessage = "Someone else changed this interview after you opened it. Reload to see their changes."

    static func isChangedConflict(_ error: Error) -> Bool {
        guard case APIError.server(_, let message) = error else { return false }
        return message?.trimmingCharacters(in: .whitespacesAndNewlines) == changedMessage
    }

    func updateInterview(_ request: UpdateInterviewRequestDTO) async throws -> InterviewDTO {
        let response: InterviewResponseDTO = try await apiClient.callRPC(.updateInterview, payload: request)
        return response.interview
    }

    func deleteInterview(id: Int) async throws {
        let _: DeleteInterviewResponseDTO = try await apiClient.callRPC(.deleteInterview, payload: DeleteInterviewRequestDTO(id: id))
    }
}
