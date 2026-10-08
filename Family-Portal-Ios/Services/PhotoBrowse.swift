import Foundation
import OSLog

// How the server's photo grouping and places sit over the local photo mirror (the web's `family-photos.tsx`).
//
// The gallery stays the local mirror — it is what works offline, shows uploads still pending, and needs no paging. The server adds two things the mirror can't know:
// - **Similar groups.** `ListFamilyPhotos` with `collapseSimilar` names each group's cover and the rest. Membership is the server's and does not depend on any filter, so it is fetched once per session over every photo and laid over whatever the gallery shows (`SimilarGroups.collapse`). Without it — offline before it arrived, or a failure — photos simply show ungrouped.
// - **Places.** The listing carries no place per photo, so a place filter asks the server for the photos there (with the other panel filters, by server id) and the gallery keeps the local photos among them. Photos the server returns that this device doesn't hold yet are shown from the server rather than dropped. Offline, a place answer already fetched still applies; one never fetched says so.
// Search stays separate: ranked by the server and never grouped (`PhotoSearchResults`).

/// A gallery cell: one photo, or one photo standing for its group of similar shots.
struct GalleryCell<Item> {
    let item: Item
    /// The group's cover (a server id), when the photo stands for a group.
    let groupCover: Int?
    /// How many other photos the group holds — the "+N" badge.
    let similarCount: Int
}

/// Groups of similar shots, keyed by server photo id.
nonisolated struct SimilarGroups: Equatable, Sendable {
    /// Cover → the others in its group.
    private(set) var others: [Int: [Int]] = [:]
    /// Every member, cover included → its group's cover.
    private(set) var coverOf: [Int: Int] = [:]

    init() {}

    var isEmpty: Bool { others.isEmpty }

    /// Takes in a page of a collapsed listing. An item without `similar` is in no group.
    mutating func add(_ items: [PhotoWithPeopleDTO]) {
        for item in items {
            guard let similar = item.similar, !similar.isEmpty else { continue }
            let cover = item.image.id
            others[cover] = similar
            coverOf[cover] = cover
            for id in similar { coverOf[id] = cover }
        }
    }

    /// Every photo in the group, cover first.
    func members(ofCover cover: Int) -> [Int] {
        [cover] + (others[cover] ?? [])
    }

    /// The cells for `items`, already filtered and in display order. A photo in no group is its own cell. A group shows once: as its cover when the cover is among `items`, else as its first member there — so a filter that hides the cover still finds the group — badged with the number of other photos in the whole group, every one of which the group view opens.
    func collapse<Item>(_ items: [Item], remoteId: (Item) -> Int?) -> [GalleryCell<Item>] {
        let visibleCovers = Set(items.compactMap(remoteId).filter { coverOf[$0] == $0 })
        var shown: Set<Int> = []
        var cells: [GalleryCell<Item>] = []
        for item in items {
            guard let id = remoteId(item), let cover = coverOf[id] else {
                cells.append(GalleryCell(item: item, groupCover: nil, similarCount: 0))
                continue
            }
            if visibleCovers.contains(cover) {
                guard id == cover else { continue }
            } else {
                guard shown.insert(cover).inserted else { continue }
            }
            cells.append(GalleryCell(item: item, groupCover: cover, similarCount: others[cover]?.count ?? 0))
        }
        return cells
    }
}

/// The server half of photo browsing: similar groups, the place list, and the photos at a place. Session memory only, like `AnalysisService`; `LocalDataReset` clears it. Never queued — these are reads.
@MainActor
@Observable
final class PhotoBrowseService {
    static let shared = PhotoBrowseService()

    /// The most a listing page holds (`maxPhotoPageSize`).
    static let pageSize = 200
    /// A runaway cursor stops here rather than paging forever.
    private static let maxPages = 200

    /// Nil until fetched, and after a failure — the gallery then shows photos ungrouped.
    private(set) var groups: SimilarGroups?
    /// `ListPhotoPlaces`, for the filter panel. Nil until fetched.
    private(set) var places: [PhotoPlaceCountDTO]?
    /// Server ids at a place, in the server's order (newest first), per question asked.
    private var placePhotos: [PhotoSearchRequest: [Int]] = [:]
    private var isLoadingGroups = false

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func loadGroups(isConnected: Bool) async {
        guard groups == nil, !isLoadingGroups, isConnected else { return }
        isLoadingGroups = true
        defer { isLoadingGroups = false }
        do {
            var found = SimilarGroups()
            try await listAll(ListFamilyPhotosRequestDTO(collapseSimilar: true)) { found.add($0) }
            groups = found
        } catch {
            AppLog.ui.error("Similar photo groups unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    func loadPlaces(isConnected: Bool) async {
        guard isConnected else { return }
        do {
            let response: ListPhotoPlacesResponseDTO = try await apiClient.callRPC(.listPhotoPlaces, payload: EmptyRequestDTO())
            places = response.places
        } catch {
            AppLog.ui.error("Photo places unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    /// The photos the server has at the request's place, already fetched. Nil when this question hasn't been answered.
    func cachedPlacePhotos(_ request: PhotoSearchRequest) -> [Int]? {
        placePhotos[request]
    }

    /// Fetches every photo at the request's place that also matches its other filters. Throws, so the gallery can say why there is nothing to show.
    @discardableResult
    func loadPlacePhotos(_ request: PhotoSearchRequest) async throws -> [Int] {
        if let cached = placePhotos[request] { return cached }
        var ids: [Int] = []
        try await listAll(request.listingDTO()) { items in ids.append(contentsOf: items.map(\.image.id)) }
        placePhotos[request] = ids
        return ids
    }

    func removeAll() {
        groups = nil
        places = nil
        placePhotos = [:]
    }

    /// Every page of a listing, handed over as each arrives.
    private func listAll(_ base: ListFamilyPhotosRequestDTO, page: ([PhotoWithPeopleDTO]) -> Void) async throws {
        var request = base
        request.limit = Self.pageSize
        for _ in 0..<Self.maxPages {
            let response: ListFamilyPhotosResponseDTO = try await apiClient.callRPC(.listFamilyPhotos, payload: request)
            page(response.photos)
            guard !response.nextCursor.isEmpty, response.nextCursor != request.cursor else { return }
            request.cursor = response.nextCursor
        }
    }
}
