import Foundation

/// The family's tag vocabulary (backend/tags.go): list, create, rename, recolour, delete.
/// Online only, like membership: the server refuses a duplicate name, so a queued create could never be trusted to land. The Tags screen re-pulls the local `FamilyTag` mirror after each change.
struct TagService {
    /// The server's limits, so the Tags screen stops a long entry while typing rather than having it refused on save.
    static let nameLimit = 40
    static let phraseLimit = 120

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func list() async throws -> [TagDTO] {
        let response: ListTagsResponseDTO = try await apiClient.callRPC(.listTags, payload: EmptyRequestDTO())
        return response.tags
    }

    func create(name: String, color: String, familyId: Int) async throws -> TagDTO {
        let response: TagResponseDTO = try await apiClient.callRPC(
            .createTag,
            payload: CreateTagRequestDTO(name: name, color: color, familyId: familyId, autoPhrase: "")
        )
        return response.tag
    }

    func update(id: Int, name: String, color: String, autoPhrase: String) async throws -> TagDTO {
        let response: TagResponseDTO = try await apiClient.callRPC(
            .updateTag,
            payload: UpdateTagRequestDTO(id: id, name: name, color: color, autoPhrase: autoPhrase)
        )
        return response.tag
    }

    /// The server detaches the tag from every photo and milestone in the same transaction.
    func delete(id: Int) async throws {
        let _: EmptyResponseDTO = try await apiClient.callRPC(.deleteTag, payload: DeleteTagRequestDTO(id: id))
    }
}
