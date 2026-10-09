import Foundation

/// Books (backend/book.go). Reads are online-first with the activity snapshot cache, so a book opened once can be read again on a plane. Outside SwiftData and `SyncQueue`: a book is references the server resolves against its own permissions, and `GetBook` sends the records with it.
/// Sharing `ActivitySnapshotCache` rather than keeping a second one means `LocalDataReset` already sweeps books with everything else.
@Observable
@MainActor
final class BookService {

    private let apiClient: APIClient
    private let cache: ActivitySnapshotCache

    init(apiClient: APIClient = .shared, cache: ActivitySnapshotCache = .shared) {
        self.apiClient = apiClient
        self.cache = cache
    }

    func books(familyId: Int = 0) -> ActivityRead<ListBooksResponseDTO> {
        read(.listBooks, payload: ListBooksRequestDTO(familyId: familyId), key: ActivitySnapshotKey(.listBooks, familyId))
    }

    func book(id: Int) -> ActivityRead<GetBookResponseDTO> {
        read(.getBook, payload: GetBookRequestDTO(id: id), key: ActivitySnapshotKey(.getBook, id))
    }

    // MARK: - Writes
    // Online only, never queued, like the activity writes: every reference is checked against the server's permissions, and a save carries a revision that only means something now.

    /// `ErrBookChanged`, word for word: the save the server refuses because someone else saved first.
    static let changedMessage = "Someone else saved this book after you opened it. Reload to see their changes."

    /// Matched on the refusal's own body rather than `localizedDescription`, which is only whatever `APIError` chose to show and changes with it.
    static func isChangedConflict(_ error: Error) -> Bool {
        guard case APIError.server(_, let message) = error else { return false }
        return message?.trimmingCharacters(in: .whitespacesAndNewlines) == changedMessage
    }

    /// The records a new book would draw on, and the dates the server settled for it. Not cached: it is asked once, just before a create.
    func sources(personIds: [Int], preset: String, startDate: String, endDate: String) async throws -> GetBookSourcesResponseDTO {
        try await apiClient.callRPC(
            .getBookSources,
            payload: GetBookSourcesRequestDTO(personIds: personIds, preset: preset, startDate: startDate, endDate: endDate)
        )
    }

    func createBook(personIds: [Int], preset: String, startDate: String, endDate: String, content: BookContentDTO) async throws -> BookDTO {
        let response: BookResponseDTO = try await apiClient.callRPC(
            .createBook,
            payload: CreateBookRequestDTO(personIds: personIds, preset: preset, startDate: startDate, endDate: endDate, content: content)
        )
        return response.book
    }

    func updateBook(id: Int, revision: Int, content: BookContentDTO) async throws -> BookDTO {
        let response: BookResponseDTO = try await apiClient.callRPC(
            .updateBook,
            payload: UpdateBookRequestDTO(id: id, revision: revision, content: content)
        )
        return response.book
    }

    func deleteBook(id: Int) async throws {
        let _: EmptyResponseDTO = try await apiClient.callRPC(.deleteBook, payload: DeleteBookRequestDTO(id: id))
    }

    private func read<Response: Decodable & Sendable, Request: Encodable & Sendable>(
        _ proc: RPCMethod,
        payload: Request,
        key: ActivitySnapshotKey
    ) -> ActivityRead<Response> {
        cache.read(proc, payload: payload, key: key, apiClient: apiClient)
    }
}
