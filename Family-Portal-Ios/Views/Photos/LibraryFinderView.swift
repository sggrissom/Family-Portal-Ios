import Photos
import SwiftData
import SwiftUI
import UIKit

/// **Find in your library**: one person's ages, each with how many photos the app already has of them then, leading to the best library photos from that stretch.
/// Everything is looked at on the device; a photo leaves it only when the user adds it.
struct LibraryFinderView: View {
    let person: Person

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var libraryStart: Date?
    @State private var isPrepared = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Copy.libraryFinder.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Copy.libraryFinder.done) { dismiss() }
                    }
                }
                .navigationDestination(for: LibraryFinder.AgeWindow.self) { window in
                    LibraryCandidatesView(person: person, window: window)
                }
                .task { await prepare() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .authorized, .limited:
            if isPrepared {
                windowList
            } else {
                ProgressView()
            }
        case .notDetermined:
            ProgressView()
        default:
            ContentUnavailableView {
                Label(Copy.libraryFinder.noAccessTitle, systemImage: "photo.on.rectangle.angled")
            } description: {
                Text(Copy.libraryFinder.noAccess)
            } actions: {
                Button(Copy.libraryFinder.openSettings, action: openSettings)
            }
        }
    }

    private var windows: [LibraryFinder.AgeWindow] {
        guard let birthday = person.birthday else { return [] }
        let all = LibraryFinder.windows(birthday: birthday)
        guard let libraryStart else { return all }
        return all.filter { $0.to > libraryStart }
    }

    private var windowList: some View {
        let dates = person.photos.map(\.photoDate)
        let windows = windows
        return List {
            if status == .limited {
                Section {
                    Text(Copy.libraryFinder.limited)
                        .font(.subheadline)
                    Button(Copy.libraryFinder.openSettings, action: openSettings)
                }
            }
            Section {
                ForEach(windows) { window in
                    NavigationLink(value: window) {
                        windowRow(window, inApp: LibraryFinder.count(of: dates, in: window))
                    }
                }
            } header: {
                Text(Copy.libraryFinder.chooseAge(person.name))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Copy.libraryFinder.onDevice)
                    if let libraryStart, windows.count < LibraryFinder.windows(birthday: person.birthday ?? libraryStart).count {
                        Text(Copy.libraryFinder.libraryStarts(libraryStart.displayDay().formatted(.dateTime.month(.wide).year())))
                    }
                }
            }
        }
        .overlay {
            if windows.isEmpty {
                ContentUnavailableView(Copy.libraryFinder.nothingInRange, systemImage: "photo.on.rectangle")
            }
        }
    }

    private func windowRow(_ window: LibraryFinder.AgeWindow, inApp: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.label)
                Text(Copy.libraryFinder.range(from: window.from, to: window.to))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(inApp == 0 ? Copy.libraryFinder.noneYet : Copy.libraryFinder.inApp(inApp))
                .font(.subheadline)
                .foregroundStyle(inApp == 0 ? Color.orange : Color.secondary)
        }
    }

    private func prepare() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { return }
        libraryStart = await LibraryScanner.libraryStart()
        isPrepared = true
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

/// The best photo from each moment in one age window, streamed in as the library is looked through, oldest first. Tap to choose, then **Add** imports them through the ordinary batch form with this person already chosen.
struct LibraryCandidatesView: View {
    let person: Person
    let window: LibraryFinder.AgeWindow

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(AddFlow.self) private var addFlow

    @State private var scan = LibraryScan()
    @State private var selected: Set<String> = []
    @State private var batch: PhotoBatch?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]
    private let skips = LibraryFinderSkips()

    var body: some View {
        ScrollView {
            header
                .padding(.horizontal)
                .padding(.top, 8)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(scan.candidates) { candidate in
                    cell(candidate)
                }
            }
            .padding(4)
        }
        .overlay {
            if scan.isFinished && scan.candidates.isEmpty {
                ContentUnavailableView(
                    Copy.libraryFinder.nothingFound,
                    systemImage: "photo.on.rectangle",
                    description: Text(Copy.libraryFinder.nothingFoundDetail)
                )
            }
        }
        .navigationTitle(window.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Copy.libraryFinder.add(selected.count), action: add)
                    .disabled(selected.isEmpty)
            }
        }
        .task {
            await scan.run(window: window, imported: importedIndex(), skipped: skips.skipped(for: person.id))
        }
        .sheet(item: $batch) { batch in
            PhotoBatchFormView(batch: batch, importer: addFlow.importer)
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = scan.progress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text(Copy.libraryFinder.looking(photos: scan.photoCount, moments: progress.total))
                        .font(.subheadline)
                }
            } else if !scan.isFinished {
                ProgressView(Copy.libraryFinder.reading)
            } else if !scan.candidates.isEmpty {
                Text(Copy.libraryFinder.summary(candidates: scan.candidates.count, moments: scan.momentCount))
                    .font(.subheadline)
            }
            if scan.alreadyInApp > 0 {
                Text(Copy.libraryFinder.alreadyAdded(scan.alreadyInApp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ candidate: LibraryFinder.Candidate) -> some View {
        let isSelected = selected.contains(candidate.id)
        return LibraryThumbnail(assetId: candidate.id)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.25))
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                if candidate.momentSize > 1 {
                    Label("\(candidate.momentSize)", systemImage: "square.stack")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(6)
                        .accessibilityLabel(Copy.libraryFinder.bestOf(candidate.momentSize))
                }
            }
            .opacity(isSelected ? 0.8 : 1)
            .contentShape(Rectangle())
            .onTapGesture { toggle(candidate.id) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(candidate.asset.date.displayDay().formatted(date: .abbreviated, time: .omitted))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .contextMenu {
                Button(Copy.libraryFinder.dontSuggest(person.name), systemImage: "eye.slash") {
                    skips.skip(candidate.id, for: person.id)
                    selected.remove(candidate.id)
                    scan.remove([candidate.id])
                }
            } preview: {
                LibraryPreview(assetId: candidate.id)
            }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    /// Oldest first, as the grid shows them. They leave the grid at once: the import records their asset ids, so the next search won't offer them either.
    private func add() {
        let ids = scan.candidates.map(\.id).filter(selected.contains)
        let entryIds = addFlow.importer.importLibraryAssets(ids, into: modelContext, syncService: syncService, errorPresenter: errorPresenter)
        scan.remove(Set(ids))
        selected = []
        guard !entryIds.isEmpty else { return }
        batch = PhotoBatch(entryIds: entryIds, preselectedPersonIds: [person.id])
    }

    /// Every photo the app holds, whoever is tagged: a library photo already added for someone else is still already added.
    private func importedIndex() -> LibraryFinder.ImportedIndex {
        let photos = (try? modelContext.fetch(FetchDescriptor<Photo>())) ?? []
        return LibraryFinder.ImportedIndex(
            assetIds: photos.compactMap(\.libraryAssetId),
            captureTimes: photos.map(\.photoDate)
        )
    }
}

/// One age window's search: fetch, split into moments, look at a few photos of each, keep the best. Candidates arrive in date order, so the grid only ever grows at the end.
@MainActor
@Observable
final class LibraryScan {
    struct Progress {
        var done: Int
        var total: Int
    }

    private(set) var candidates: [LibraryFinder.Candidate] = []
    /// Moments looked at so far while running; nil before and after.
    private(set) var progress: Progress?
    private(set) var isFinished = false
    private(set) var photoCount = 0
    private(set) var momentCount = 0
    /// Photos left out because they're already in the app or were skipped for this person.
    private(set) var alreadyInApp = 0

    private var hasStarted = false

    func run(window: LibraryFinder.AgeWindow, imported: LibraryFinder.ImportedIndex, skipped: Set<String>) async {
        // `.task` runs again whenever the grid reappears, as it does on returning from the photo viewer.
        guard !hasStarted else { return }
        hasStarted = true

        let all = await LibraryScanner.assets(in: window)
        let fresh = all.filter { !imported.contains($0) && !skipped.contains($0.id) }
        photoCount = all.count
        alreadyInApp = all.count - fresh.count

        let moments = LibraryFinder.moments(fresh)
        momentCount = moments.count
        progress = Progress(done: 0, total: moments.count)
        defer {
            progress = nil
            isFinished = !Task.isCancelled
            // A search cut short by leaving the screen starts over next time rather than showing half a grid.
            if Task.isCancelled { reset() }
        }

        for moment in moments {
            var analyses: [String: LibraryFinder.Analysis] = [:]
            for asset in LibraryFinder.sample(moment) {
                guard !Task.isCancelled else { return }
                if let analysis = await LibraryScanner.analyze(asset.id) {
                    analyses[asset.id] = analysis
                }
            }
            if let best = LibraryFinder.best(of: moment, analyses: analyses) {
                candidates.append(best)
            }
            progress?.done += 1
        }
    }

    func remove(_ ids: Set<String>) {
        candidates.removeAll { ids.contains($0.id) }
    }

    private func reset() {
        hasStarted = false
        candidates = []
        photoCount = 0
        momentCount = 0
        alreadyInApp = 0
    }
}

/// A library photo as a square grid cell.
struct LibraryThumbnail: View {
    let assetId: String

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: assetId) {
                image = await LibraryScanner.thumbnail(assetId, side: 140 * displayScale)
            }
    }
}

/// The whole photo, for a long press.
private struct LibraryPreview: View {
    let assetId: String

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .frame(width: 300, height: 300)
            }
        }
        .task {
            image = await LibraryScanner.thumbnail(assetId, side: 1_200)
        }
    }
}
