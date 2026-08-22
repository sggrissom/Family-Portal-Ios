import SwiftUI
import SwiftData
import ImageIO
import OSLog
import PhotosUI

struct PhotoGalleryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]
    @Query(sort: \Person.name) private var people: [Person]

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var importProgress: ImportProgress?
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
                    if let importProgress {
                        ImportProgressBar(progress: importProgress)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        filterButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // `.ordered` numbers the picks, and the selection arrives
                        // in the order they were made rather than in library
                        // order — the order the user just built is the one worth
                        // keeping.
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
                    importPicked(newItems)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if photos.isEmpty && importProgress == nil {
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
        // Two different dead ends: a search that found nothing is the system's
        // own empty state, while a filter that excludes everything needs the way
        // back out, since the criteria live behind a sheet the user closed.
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

    /// What is being shown and why — the web's filter summary, which is on its
    /// toolbar button. Here the button is an icon, so the criteria go above the
    /// grid where a short count already had to appear.
    private var countCaption: String {
        let count = "\(visiblePhotos.count) of \(photos.count) photos"
        let summary = filterSummary
        return summary.isEmpty ? count : "\(count) · \(summary)"
    }

    // MARK: - Import

    /// One pass of the picker: how many photos it handed over, and how far the
    /// app has got through reading them.
    ///
    /// Only the *reading and queueing* is counted here. The upload itself belongs
    /// to `SyncQueue` — which already owns retries, offline and ordering — so a
    /// finished import means every photo is on screen and in the queue, not that
    /// every photo is on the server.
    struct ImportProgress {
        var total = 0
        var completed = 0
        var failed = 0
        /// The first thing that went wrong, kept so a single-photo import can
        /// still report exactly what happened rather than a count.
        var firstFailure: Error?

        var settled: Int { completed + failed }
        var isFinished: Bool { settled >= total }
    }

    private func importPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        // Clearing the binding re-enters this method with an empty array, which
        // the guard above absorbs. It has to happen: without it, picking the same
        // photo twice in a row is not a change and never fires.
        pickedItems = []

        // A second pick while the first is still reading extends the same run
        // rather than replacing it, so neither bar nor total goes backwards.
        var progress = importProgress ?? ImportProgress()
        progress.total += items.count
        importProgress = progress

        Task {
            // Sequential on purpose: each item is a full-resolution image, and
            // twenty of them decoded at once is the kind of memory spike that
            // gets an app killed mid-import.
            for item in items {
                do {
                    try await importOne(item)
                    importProgress?.completed += 1
                } catch {
                    AppLog.ui.error("Photo import failed: \(String(describing: error), privacy: .public)")
                    importProgress?.failed += 1
                    if importProgress?.firstFailure == nil {
                        importProgress?.firstFailure = error
                    }
                }

                if importProgress?.isFinished == true {
                    finishImport()
                }
            }
        }
    }

    private func importOne(_ item: PhotosPickerItem) async throws {
        guard let data = try await item.loadTransferable(type: Data.self),
              UIImage(data: data) != nil else {
            throw ImportFailure.unreadable
        }

        let photo = Photo(
            title: "",
            descriptionText: "",
            photoDate: Self.captureDate(from: data) ?? Date(),
            imageData: data
        )
        modelContext.insert(photo)
        try modelContext.save()
        try await syncService?.uploadPhoto(photo)
    }

    private func finishImport() {
        guard let progress = importProgress else { return }
        importProgress = nil

        guard progress.failed > 0 else { return }

        // One report for the whole run. Reporting per photo would stack a dozen
        // alerts behind each other for a batch picked out of iCloud.
        if progress.failed == 1, let failure = progress.firstFailure {
            errorPresenter?.report(failure, title: "Couldn't Add Photo")
        } else {
            errorPresenter?.report(
                message: "\(progress.failed) of \(progress.total) photos couldn't be added. Photos stored in iCloud need to finish downloading in Photos first.",
                title: "Some Photos Weren't Added"
            )
        }
    }

    /// An iCloud photo that never downloaded, or a format `UIImage` won't open.
    /// Silence here looked like a tap that did nothing at all.
    private enum ImportFailure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "That photo couldn't be read. If it's stored in iCloud, open it in Photos first and try again."
        }
    }

    /// Reads the capture date out of the picked image's own EXIF. Deliberately
    /// avoids `PHAsset`, which needs photo-library authorization the picker
    /// itself does not; the backend does the same thing for `inputType: "auto"`.
    private static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = (exif[kCGImagePropertyExifDateTimeOriginal]
                              ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String
        else {
            return nil
        }

        return exifDateFormatter.date(from: original)
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()
}

/// Progress for the import pass, as an inset above the tab bar rather than the
/// full-screen overlay this replaced: photos appear in the grid as they are read,
/// and blocking the screen hid the very thing that shows the import working.
private struct ImportProgressBar: View {
    let progress: PhotoGalleryView.ImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.footnote)
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }
            ProgressView(value: Double(progress.settled), total: Double(max(progress.total, 1)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var label: String {
        progress.total == 1
            ? "Adding photo…"
            : "Adding photo \(min(progress.settled + 1, progress.total)) of \(progress.total)…"
    }
}
