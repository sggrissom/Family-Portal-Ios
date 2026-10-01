import Foundation

/// Naming the faces the server found (backend/faces.go). Online only: every change re-matches the family's faces on the server, so the screen reloads the review after each one rather than predicting it.
struct FaceReviewService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func review() async throws -> GetFaceReviewResponseDTO {
        try await apiClient.callRPC(.getFaceReview, payload: EmptyRequestDTO())
    }

    /// Names the faces as one person — also how an automatic tag is confirmed.
    func assign(faceIds: [Int], to personId: Int) async throws -> AssignFacesResponseDTO {
        try await apiClient.callRPC(.assignFaces, payload: AssignFacesRequestDTO(faceIds: faceIds, personId: personId))
    }

    /// "Not them": the face goes back to unnamed, and the server won't suggest that person for it again.
    func reject(faceIds: [Int]) async throws {
        let _: FaceIdsResponseDTO = try await apiClient.callRPC(.rejectFaces, payload: FaceIdsRequestDTO(faceIds: faceIds))
    }

    /// "Not someone in the family": the faces leave the review for good.
    func dismiss(faceIds: [Int]) async throws {
        let _: FaceIdsResponseDTO = try await apiClient.callRPC(.dismissFaces, payload: FaceIdsRequestDTO(faceIds: faceIds))
    }
}
