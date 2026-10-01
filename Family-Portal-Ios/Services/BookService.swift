import Foundation

/// Books (backend/book.go), read online-first with the activity snapshot cache, so a book opened once can be read again on a plane. Outside SwiftData and `SyncQueue`: a book is references the server resolves against its own permissions, and `GetBook` sends the records with it.
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

    /// Decode before caching, never after: caching a payload this build cannot read would make the failure permanent.
    private func read<Response: Decodable & Sendable, Request: Encodable & Sendable>(
        _ proc: RPCMethod,
        payload: Request,
        key: ActivitySnapshotKey
    ) -> ActivityRead<Response> {
        let apiClient = self.apiClient
        let cache = self.cache

        return ActivityRead(
            cached: { await cache.load(Response.self, key: key) },
            live: {
                let data = try await apiClient.callRPCData(proc, payload: payload)
                let value: Response
                do {
                    value = try APIClient.decode(Response.self, from: data)
                } catch {
                    throw APIError.decoding(error)
                }
                await cache.store(data, key: key)
                return value
            }
        )
    }
}
