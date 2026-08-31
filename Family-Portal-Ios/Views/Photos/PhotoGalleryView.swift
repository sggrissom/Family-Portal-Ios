import SwiftUI
import SwiftData
import PhotosUI

struct PhotoGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]
    @Query(sort: \Person.name) private var people: [Person]

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var importer = PhotoImporter()
    @State private var filter = PhotoFilter()
    @State private var isFilterPresented = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    private var visiblePhotos: [Photo] {
        filter.apply(to: photos)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Photos")
                .searchable(text: $filter.searchText, prompt: "Title or description")
                .navigationDestination(for: PhotoRoute.self) { route in
                    PhotoDetailView(photoId: route.id)
                }
                .safeAreaInset(edge: .bottom) {
                    if let progress = importer.progress {
                        PhotoImportProgressBar(progress: progress)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        filterButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // `.ordered` numbers the picks and delivers them in the order the user made them, not library order.
                        PhotosPicker(
                            selection: $pickedItems,
                            maxSelectionCount: nil,
                            selectionBehavior: .ordered,
                            matching: .images
                        ) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add photos")
                    }
                }
                .sheet(isPresented: $isFilterPresented) {
                    NavigationStack {
                        PhotoFilterView(filter: $filter)
                    }
                }
                .onChange(of: pickedItems) { _, newItems in
                    // Clearing the binding re-enters this with an empty array, which the importer absorbs. Without it, picking the same photo twice in a row never fires.
                    pickedItems = []
                    importer.importPicked(
                        newItems,
                        into: modelContext,
                        syncService: syncService,
                        errorPresenter: errorPresenter
                    )
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if photos.isEmpty && importer.progress == nil {
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
