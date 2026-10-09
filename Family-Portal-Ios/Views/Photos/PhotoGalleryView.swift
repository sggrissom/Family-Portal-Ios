import OSLog
import SwiftUI
import SwiftData

struct PhotoGalleryView: View {
    @Environment(AddFlow.self) private var addFlow
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]
    @Query(sort: \Person.name) private var people: [Person]

    @Environment(AppNavigator.self) private var navigator
    @Environment(NetworkMonitor.self) private var network
    @Environment(AuthService.self) private var authService

    /// Lives on the navigator, so a person page's "Open in Photos →" can set it and it survives leaving the tab.
    private var filter: PhotoFilter {
        get { navigator.photoFilter }
        nonmutating set { navigator.photoFilter = newValue }
    }

    private var filterBinding: Binding<PhotoFilter> {
        Binding(get: { navigator.photoFilter }, set: { navigator.photoFilter = $0 })
    }
    @State private var isFilterPresented = false
    /// The tag-suggestion review, for the toolbar link. `nil` hides it — offline, analysis off, or nothing to review.
    @State private var suggestionReview: GetTagSuggestionsResponseDTO?
    /// A submitted server search. While set, the grid shows its ranked results instead of the local filter; editing the text away from its query drops it.
    @State private var search: PhotoSearchResults?
    @State private var isSearching = false
    @State private var isLoadingMore = false
    @State private var searchError: String?

    /// A place filter whose answer could not be fetched, for the empty state.
    @State private var placeError: String?

    private var isOnline: Bool { network.isConnected }
    private var browse: PhotoBrowseService { .shared }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    /// The panel filters as the server takes them — the question a place filter asks.
    private var placeRequest: PhotoSearchRequest? {
        filter.placeKey == nil ? nil : PhotoSearchRequest(filter: filter, people: people)
    }

    /// The server's photos at the chosen place, newest first. Nil without a place, or before an answer.
    private var placePhotoIds: [Int]? {
        placeRequest.flatMap { browse.cachedPlacePhotos($0) }
    }

    private var visiblePhotos: [Photo] {
        filter.apply(to: photos, placePhotoIds: placePhotoIds.map(Set.init))
    }

    /// Similar shots folded under one cell, unless the user asked to see them separately or the groups haven't arrived.
    private var cells: [GalleryCell<Photo>] {
        let visible = visiblePhotos
        guard !filter.showsSimilarSeparately, let groups = browse.groups, !groups.isEmpty else {
            return visible.map { GalleryCell(item: $0, groupCover: nil, similarCount: 0) }
        }
        return groups.collapse(visible) { $0.remoteId.flatMap(Int.init) }
    }

    /// Photos at the chosen place that the server has and this device doesn't yet: shown from the server, not silently left out.
    private var unsyncedPlacePhotoIds: [Int] {
        guard let ids = placePhotoIds else { return [] }
        let held = Set(photos.compactMap { $0.remoteId.flatMap(Int.init) })
        return ids.filter { !held.contains($0) }
    }

    var body: some View {
        content
            .navigationTitle(Copy.nav.photos)
            .searchable(text: filterBinding.searchText, prompt: isOnline ? Copy.photoSearch.prompt : Copy.photoSearch.offlinePrompt)
            .onSubmit(of: .search) {
                Task { await submitSearch() }
            }
            // A search answers one question. New words drop it back to the live local filter until they are submitted; new panel filters ask it again.
            .onChange(of: filter.trimmedSearch) { _, text in
                if let search, search.query != text {
                    self.search = nil
                    searchError = nil
                }
            }
            .onChange(of: PhotoSearchRequest(filter: filter, people: people)) { _, _ in
                if search != nil {
                    Task { await submitSearch() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterButton
                }
                if let review = suggestionReview, review.hasSuggestions {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            TagSuggestionsView()
                        } label: {
                            Image(systemName: "sparkles")
                                .overlay(alignment: .topTrailing) {
                                    Text("\(review.total)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .background(Color.accentColor, in: Capsule())
                                        .offset(x: 10, y: -8)
                                }
                        }
                        .accessibilityLabel("\(Copy.tagSuggestions.title), \(review.total)")
                    }
                }
            }
            // Keyed on connectivity, so the link appears once a signal returns.
            .task(id: network.isConnected) {
                await loadSuggestionCount()
                await browse.loadGroups(isConnected: isOnline)
            }
            .task(id: TaskKey(place: placeRequest, online: isOnline)) {
                await loadPlacePhotos()
            }
            // Coming back from the review, whose last fetch is the freshest count there is.
            .onAppear {
                if network.isConnected, let cached = AnalysisService.shared.cachedTagSuggestions {
                    suggestionReview = cached
                }
            }
            .sheet(isPresented: $isFilterPresented) {
                NavigationStack {
                    PhotoFilterView(filter: filterBinding)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let search {
            searchResults(search)
        } else if photos.isEmpty && addFlow.importer.progress == nil {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle",
                description: Text(authService.access.canContributeAnywhere ? "Tap + to add your first photo." : "")
            )
        } else if filter.placeKey != nil && placePhotoIds == nil {
            placePendingView
        } else if visiblePhotos.isEmpty && !photos.isEmpty && unsyncedPlacePhotoIds.isEmpty {
            noMatchesView
        } else {
            ScrollView {
                if let note = localSearchNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                if filter.isActive {
                    Text(countCaption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(cells, id: \.item.id) { cell in
                        galleryCell(cell)
                    }
                }
                .padding(4)

                let unsynced = unsyncedPlacePhotoIds
                if !unsynced.isEmpty {
                    Text(Copy.photoBrowse.notSyncedHeading(unsynced.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(unsynced, id: \.self) { id in
                            ServerPhotoCell(remoteId: id, local: nil)
                        }
                    }
                    .padding(4)
                }
            }
        }
    }

    private func galleryCell(_ cell: GalleryCell<Photo>) -> some View {
        NavigationLink(value: PhotoRoute(id: cell.item.id)) {
            PhotoThumbnailView(imageData: cell.item.imageData, title: cell.item.title, remoteId: cell.item.remoteId)
        }
        // Its own link over the photo's, so the badge opens the group and the rest of the cell opens the photo.
        .overlay(alignment: .topTrailing) {
            if let cover = cell.groupCover, cell.similarCount > 0, let groups = browse.groups {
                NavigationLink(value: AppRoute.similarPhotos(ids: groups.members(ofCover: cover))) {
                    Label("+\(cell.similarCount)", systemImage: "square.stack")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(4)
                }
                .accessibilityLabel(Copy.photoBrowse.similarBadge(cell.similarCount))
            }
        }
    }

    // MARK: - Places

    /// Keyed on both, so going back online retries a place that couldn't be fetched.
    private struct TaskKey: Hashable {
        let place: PhotoSearchRequest?
        let online: Bool
    }

    private func loadPlacePhotos() async {
        placeError = nil
        guard let request = placeRequest, browse.cachedPlacePhotos(request) == nil else { return }
        guard isOnline else {
            placeError = Copy.photoBrowse.placeOffline
            return
        }
        do {
            try await browse.loadPlacePhotos(request)
        } catch {
            guard !Task.isCancelled else { return }
            AppLog.ui.error("Place photos failed: \(String(describing: error), privacy: .public)")
            placeError = Copy.photoBrowse.placeFailed
        }
    }

    /// A place is chosen but the server hasn't said which photos are there: loading, offline, or failed.
    @ViewBuilder
    private var placePendingView: some View {
        if let placeError {
            ContentUnavailableView {
                Label(filter.placeName, systemImage: "mappin.and.ellipse")
            } description: {
                Text(placeError)
            } actions: {
                Button(Copy.photoBrowse.clearPlace) {
                    filter.placeKey = nil
                    filter.placeName = ""
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var noMatchesView: some View {
        if filter.hasPanelFilters {
            ContentUnavailableView {
                Label("No Photos Match", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Try widening or clearing the filters.")
            } actions: {
                Button("Clear Filters") {
                    filter.clearPanelFilters()
                }
            }
        } else {
            ContentUnavailableView.search(text: filter.trimmedSearch)
        }
    }

    // MARK: - Server search

    /// Said while the grid is the local filter over typed words: offline, that is all there is; online, the words haven't been submitted yet, or the search failed.
    private var localSearchNote: String? {
        guard !filter.trimmedSearch.isEmpty else { return nil }
        if !isOnline { return Copy.photoSearch.offlineNote }
        if let searchError { return searchError }
        if isSearching { return Copy.photoSearch.searching }
        return nil
    }

    private func submitSearch() async {
        let query = filter.trimmedSearch
        guard !query.isEmpty, isOnline else {
            search = nil
            return
        }
        let request = PhotoSearchRequest(filter: filter, people: people)
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let response = try await AnalysisService.shared.searchPhotos(query: query, request: request)
            // The text may have moved on while the answer was in flight.
            guard filter.trimmedSearch == query else { return }
            var results = PhotoSearchResults(query: query, request: request)
            results.append(response)
            search = results
        } catch {
            AppLog.ui.error("Photo search failed: \(String(describing: error), privacy: .public)")
            search = nil
            searchError = Copy.photoSearch.failed
        }
    }

    private func loadMore() async {
        guard var results = search, results.hasMore, !isLoadingMore, isOnline else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let response = try await AnalysisService.shared.searchPhotos(query: results.query, request: results.request, cursor: results.nextCursor)
            guard search?.query == results.query, search?.request == results.request else { return }
            results.append(response)
            search = results
        } catch {
            AppLog.ui.error("Photo search paging failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func searchResults(_ results: PhotoSearchResults) -> some View {
        let byRemoteId = Dictionary(photos.compactMap { photo in photo.remoteId.flatMap(Int.init).map { ($0, photo) } }, uniquingKeysWith: { first, _ in first })
        return ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(Copy.photoSearch.bestMatches(results.query, with: matchedNames(results.matchedPersonIds)))
                    .font(.subheadline.weight(.semibold))
                if results.isTextOnly {
                    Text(Copy.photoSearch.textOnlyNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(Copy.photoSearch.clear) {
                    filter.searchText = ""
                    search = nil
                }
                .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 4)

            if results.photoIds.isEmpty && !results.hasMore {
                ContentUnavailableView.search(text: results.query)
            }

            // In the server's ranking, never grouped. A result this device doesn't hold yet is shown from the server in its place.
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(results.photoIds, id: \.self) { id in
                    ServerPhotoCell(remoteId: id, local: byRemoteId[id])
                        .onAppear {
                            if id == results.photoIds.last {
                                Task { await loadMore() }
                            }
                        }
                }
            }
            .padding(4)

            if isLoadingMore {
                ProgressView()
                    .padding()
            } else if results.hasMore && results.photoIds.isEmpty {
                Button(Copy.photoSearch.more) {
                    Task { await loadMore() }
                }
                .padding()
            }
        }
    }

    /// "Clara and Mia" — the first names of the people the query named, as the web writes them.
    private func matchedNames(_ remoteIds: [Int]) -> String {
        let names = remoteIds.compactMap { id in
            people.first { $0.remoteId == String(id) }?.name.firstName
        }
        return names.joined(separator: " and ")
    }

    private func loadSuggestionCount() async {
        let analysis = AnalysisService.shared
        guard network.isConnected else {
            suggestionReview = nil
            return
        }
        if suggestionReview == nil {
            suggestionReview = analysis.cachedTagSuggestions
        }
        if let fresh = await analysis.tagSuggestions() {
            suggestionReview = fresh
        }
    }

    private var filterButton: some View {
        Button {
            isFilterPresented = true
        } label: {
            Image(systemName: filter.hasPanelFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(
            filter.hasPanelFilters
                ? "Filter photos, filtering by \(filterSummary)"
                : "Filter photos"
        )
    }

    private var filterSummary: String {
        let names = Dictionary(people.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return filter.summary { names[$0] }
    }

    private var countCaption: String {
        let count = "\(visiblePhotos.count) of \(photos.count) photos"
        let summary = filterSummary
        return summary.isEmpty ? count : "\(count) · \(summary)"
    }
}
