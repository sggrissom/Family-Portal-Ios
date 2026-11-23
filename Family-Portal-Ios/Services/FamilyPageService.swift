import Foundation

/// The public family page (backend/family_page.go). Online only, never queued: a page goes public only when the server agrees.
struct FamilyPageService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func settings(familyId: Int) async throws -> FamilyPageSettingsResponseDTO {
        try await apiClient.callRPC(.getFamilyPageSettings, payload: FamilyIdRequestDTO(familyId: familyId))
    }

    func publish(familyId: Int, settings: FamilyPageSettingsDTO) async throws -> FamilyPageSettingsResponseDTO {
        try await apiClient.callRPC(
            .publishFamilyPage,
            payload: PublishFamilyPageRequestDTO(familyId: familyId, settings: settings)
        )
    }

    func unpublish(familyId: Int) async throws -> FamilyPageSettingsResponseDTO {
        try await apiClient.callRPC(.unpublishFamilyPage, payload: FamilyIdRequestDTO(familyId: familyId))
    }
}
