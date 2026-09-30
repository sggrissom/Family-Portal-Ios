import SwiftUI
import SwiftData

struct PhotoGalleryView: View {
    @Environment(AddFlow.self) private var addFlow
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]
    @Query(sort: \Person.name) private var people: [Person]

    @Environment(AppNavigator.self) private var navigator
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

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

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    private var visiblePhotos: [Photo] {
        filter.apply(to: photos)
    }

    var body: some View {
        content
            .navigationTitle(Copy.nav.photos)
            .searchable(text: filterBinding.searchText, prompt: "Title or description")
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
            .task(id: network?.isConnected ?? true) {
                await loadSuggestionCount()
            }
            // Coming back from the review, whose last fetch is the freshest count there is.
            .onAppear {
                if network?.isConnected ?? true, let cached = AnalysisService.shared.cachedTagSuggestions {
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
        if photos.isEmpty && addFlow.importer.progress == nil {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle",
                description: Text("Tap + to add your first photo.")
            )
        } else if visiblePhotos.isEmpty && !photos.isEmpty {
            noMatchesView
        } else {
            ScrollView {
                if filter.isActive {
                    Text(countCaption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(visiblePhotos) { photo in
                        NavigationLink(value: PhotoRoute(id: photo.id)) {
                            PhotoThumbnailView(imageData: photo.imageData, title: photo.title, remoteId: photo.remoteId)
                        }
                    }
                }
                .padding(4)
            }
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

    private func loadSuggestionCount() async {
        let analysis = AnalysisService.shared
        guard network?.isConnected ?? true else {
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
