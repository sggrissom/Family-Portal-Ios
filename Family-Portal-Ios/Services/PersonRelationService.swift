import Foundation

/// The relationship graph a person sits in (backend/relation.go). Only three edge kinds are ever stored — parent-of, sibling-of, partner-of — and everything else the app shows, from "grandmother" to "cousin", is the server walking those edges outward.
/// Nothing here goes through `SyncQueue`. A label is derived from edges this device cannot see all of, so the answer has to come from the server anyway; a queued edge would show a relationship the graph had not actually gained.
struct PersonRelationService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func relations(personId: Int) async throws -> GetPersonRelationsResponseDTO {
        try await apiClient.callRPC(
            .getPersonRelations,
            payload: GetPersonRelationsRequestDTO(personId: personId)
        )
    }

    /// States that `personId` is `stated` of `anchorId` — "Kate is my sister" — and answers with the person's whole relationship list as it now stands.
    func addRelation(
        personId: Int,
        anchorId: Int,
        stated: StatedRelation
    ) async throws -> GetPersonRelationsResponseDTO {
        let response: RelationActionResponseDTO = try await apiClient.callRPC(
            .addRelation,
            payload: AddRelationRequestDTO(
                personId: personId,
                anchorId: anchorId,
                stated: stated.rawValue
            )
        )
        return try Self.relations(from: response, fallback: "Could not save that relationship.")
    }

    func removeRelation(relationId: Int) async throws -> GetPersonRelationsResponseDTO {
        let response: RelationActionResponseDTO = try await apiClient.callRPC(
            .removeRelation,
            payload: RemoveRelationRequestDTO(relationId: relationId)
        )
        return try Self.relations(from: response, fallback: "Could not remove that relationship.")
    }

    private static func relations(
        from response: RelationActionResponseDTO,
        fallback: String
    ) throws -> GetPersonRelationsResponseDTO {
        guard response.success else {
            throw RelationError.refused(response.error ?? fallback)
        }
        // A success always carries the rebuilt list; treating a missing one as an empty roster would wipe every relationship off the screen.
        guard let relations = response.relations else {
            throw RelationError.refused(fallback)
        }
        return relations
    }
}

/// A refusal the backend carries in the response body rather than the status code, the way the membership procs do: vbeam answers `{ success: false, error: … }` with HTTP 200.
enum RelationError: LocalizedError {
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .refused(let message):
            return message
        }
    }
}
