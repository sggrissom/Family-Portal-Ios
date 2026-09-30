import Foundation
import OSLog

/// A server photo search in progress: the one mode of the gallery that depends on the server. `ListFamilyPhotos` with a `query` ranks by how well each photo fits the words (CLIP), and turns people's names in the query into an all-of person filter.
/// Results are kept as server ids in the server's order and resolved against the local mirror at render, so a photo this device hasn't pulled yet simply doesn't show.
struct PhotoSearchResults: Equatable {
    static let pageSize = 60

    let query: String
    /// The request this search was made with, minus the cursor — so paging asks the same question.
    let request: PhotoSearchRequest
    private(set) var photoIds: [Int] = []
    private(set) var nextCursor: String = ""
    private(set) var matchedPersonIds: [Int] = []
    private(set) var searchMode: String = ""

    init(query: String, request: PhotoSearchRequest) {
        self.query = query
        self.request = request
    }

    var hasMore: Bool { !nextCursor.isEmpty }

    /// Only titles and descriptions were searched, because image search is down.
    var isTextOnly: Bool { searchMode == "text" }

    /// Takes on the next page. A photo already listed is not listed twice.
    mutating func append(_ response: ListFamilyPhotosResponseDTO) {
        var seen = Set(photoIds)
        for item in response.photos where seen.insert(item.image.id).inserted {
            photoIds.append(item.image.id)
        }
        nextCursor = response.nextCursor
        if matchedPersonIds.isEmpty {
            matchedPersonIds = response.matchedPersonIds
        }
        if !response.searchMode.isEmpty {
            searchMode = response.searchMode
        }
    }
}

/// The panel filters, as the server takes them. People go by server id, so one still uploading can't be sent; the local filter still has them.
struct PhotoSearchRequest: Equatable {
    var personIds: [Int] = []
    var tagIds: [Int] = []
    var dateFrom: String?
    var dateTo: String?

    init(filter: PhotoFilter, people: [Person]) {
        personIds = people
            .filter { filter.personLocalIds.contains($0.id) }
            .compactMap { $0.remoteId.flatMap(Int.init) }
            .sorted()
        tagIds = filter.tagRemoteIds.sorted()
        let range = filter.normalizedDateRange
        dateFrom = range.from.map { dateToAPIString($0) }
        dateTo = range.to.map { dateToAPIString($0) }
    }

    func dto(query: String, cursor: String?) -> ListFamilyPhotosRequestDTO {
        ListFamilyPhotosRequestDTO(
            query: query,
            limit: PhotoSearchResults.pageSize,
            cursor: cursor,
            personIds: personIds.isEmpty ? nil : personIds,
            tagIds: tagIds.isEmpty ? nil : tagIds,
            dateFrom: dateFrom,
            dateTo: dateTo
        )
    }
}

extension AnalysisService {
    /// One page of a server search. Throws, so the gallery can fall back to the local filter and say why.
    func searchPhotos(query: String, request: PhotoSearchRequest, cursor: String? = nil) async throws -> ListFamilyPhotosResponseDTO {
        try await apiClient.callRPC(.listFamilyPhotos, payload: request.dto(query: query, cursor: cursor))
    }
}
