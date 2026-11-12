import Photos
import SwiftData
import SwiftUI
import UIKit

/// Where the finder's stack can go: one person's ages, or one age's search.
enum LibraryRoute: Hashable {
    case ages(personId: UUID)
    case window(personId: UUID, window: LibraryFinder.AgeWindow)
}

/// **Find in your library**. Opened for a person, it starts at their ages; opened from the gallery, at the family's coverage map.
/// Everything is looked at on the device; a photo leaves it only when the user adds it.
struct LibraryFinderView: View {
    /// Nil opens the family map.
    let personId: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var people: [Person]

    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var libraryStart: Date?
    @State private var isPrepared = false

    init(personId: UUID? = nil) {
        self.personId = personId
    }

    init(person: Person) {
        self.init(personId: person.id)
    }

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
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .ages(let personId):
                        if let person = lookUp(personId) {
                            LibraryAgesView(person: person, libraryStart: libraryStart)
                        }
                    case .window(let personId, let window):
                        if let person = lookUp(personId) {
                            LibrarySearchView(person: person, window: window)
                        }
                    }
                }
                .task { await prepare() }
        }
    }

    private func lookUp(_ id: UUID) -> Person? {
        people.first { $0.id == id }
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .authorized, .limited:
            if !isPrepared {
                ProgressView()
            } else {
                VStack(spacing: 0) {
                    if status == .limited {
                        limitedNote
                    }
                    if let personId, let person = lookUp(personId) {
                        LibraryAgesView(person: person, libraryStart: libraryStart)
                    } else {
                        LibraryCoverageView(libraryStart: libraryStart)
                    }
                }
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

    private var limitedNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Copy.libraryFinder.limited)
                .font(.subheadline)
            Button(Copy.libraryFinder.openSettings, action: openSettings)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
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

/// One person's ages, each with how many photos the app has of them then and how many the library holds, so a gap that can be filled stands out from one that can't.
struct LibraryAgesView: View {
    let person: Person
    let libraryStart: Date?

    /// Library photos per window, by `AgeWindow.id`, filled in as the counts arrive.
    @State private var libraryCounts: [Int: Int] = [:]

    private var windows: [LibraryFinder.AgeWindow] {
        guard let birthday = person.birthday else { return [] }
        return LibraryFinder.windows(birthday: birthday).filter { !LibraryFinder.isBeforeLibrary($0, start: libraryStart) }
    }

    private var hidesEarlierAges: Bool {
        guard let birthday = person.birthday else { return false }
        return windows.count < LibraryFinder.windows(birthday: birthday).count
    }

    var body: some View {
        let dates = person.photos.map(\.photoDate)
        let windows = windows
        List {
            Section {
                ForEach(windows) { window in
                    NavigationLink(value: LibraryRoute.window(personId: person.id, window: window)) {
                        row(window, inApp: LibraryFinder.count(of: dates, in: window), inLibrary: libraryCounts[window.id])
                    }
                }
            } header: {
                Text(Copy.libraryFinder.chooseAge(person.name))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Copy.libraryFinder.onDevice)
                    if let libraryStart, hidesEarlierAges {
                        Text(Copy.libraryFinder.libraryStarts(libraryStart.displayDay().formatted(.dateTime.month(.wide).year())))
                    }
                }
            }
        }
        .navigationTitle(person.name)
        .overlay {
            if windows.isEmpty {
                ContentUnavailableView(Copy.libraryFinder.nothingInRange, systemImage: "photo.on.rectangle")
            }
        }
        .task(id: person.id) {
            for window in windows {
                guard !Task.isCancelled else { return }
                libraryCounts[window.id] = await LibraryScanner.count(in: window)
            }
        }
    }

    private func row(_ window: LibraryFinder.AgeWindow, inApp: Int, inLibrary: Int?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.label)
                Text(Copy.libraryFinder.range(from: window.from, to: window.to))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(inApp == 0 ? Copy.libraryFinder.noneYet : Copy.libraryFinder.inApp(inApp))
                    .font(.subheadline)
                    .foregroundStyle(inApp == 0 && (inLibrary ?? 1) > 0 ? Color.orange : Color.secondary)
                if let inLibrary {
                    Text(Copy.libraryFinder.inLibrary(inLibrary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The family at a glance: a row of ages for each child, birth to eighteen, coloured by how many photos the app has of them at each. Orange is an age with none that the library reaches back to. Tap a square to search that age.
/// Ages line up down the page, so "everyone at two" is one column. Adults' childhoods are usually older than any phone library, so they're listed below with their own counts instead.
struct LibraryCoverageView: View {
    let libraryStart: Date?

    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]
    @Environment(AuthService.self) private var auth

    private let cell: CGFloat = 12
    private let spacing: CGFloat = 3

    private var everyone: [Person] {
        PersonChips.ordered(people, relations: relations, ownFamilyId: auth.currentUser?.familyId)
            .filter { $0.birthday != nil && !$0.isPregnancy && auth.access.canContribute(to: $0) }
    }

    private func childhood(_ person: Person) -> [LibraryFinder.AgeWindow] {
        guard let birthday = person.birthday else { return [] }
        return LibraryFinder.childhood(LibraryFinder.windows(birthday: birthday))
    }

    var body: some View {
        let everyone = everyone
        let mapped = everyone.filter { person in
            childhood(person).contains { !LibraryFinder.isBeforeLibrary($0, start: libraryStart) }
        }
        let others = everyone.filter { person in !mapped.contains { $0.id == person.id } }

        List {
            if !mapped.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            axis
                            ForEach(mapped) { person in
                                personRow(person)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    legend
                } header: {
                    Text(Copy.libraryFinder.coverageTitle)
                } footer: {
                    Text(Copy.libraryFinder.coverageFooter)
                }
            }
            if !others.isEmpty {
                Section(Copy.libraryFinder.othersTitle) {
                    ForEach(others) { person in
                        NavigationLink(value: LibraryRoute.ages(personId: person.id)) {
                            Text(person.name)
                        }
                    }
                }
            }
        }
        .overlay {
            if everyone.isEmpty {
                ContentUnavailableView(Copy.libraryFinder.nobody, systemImage: "person.2")
            }
        }
    }

    private func personRow(_ person: Person) -> some View {
        let windows = childhood(person)
        let dates = person.photos.map(\.photoDate)
        let counts = windows.map { LibraryFinder.count(of: dates, in: $0) }
        let gaps = zip(windows, counts).filter { !LibraryFinder.isBeforeLibrary($0.0, start: libraryStart) && $0.1 == 0 }.count

        return VStack(alignment: .leading, spacing: 4) {
            NavigationLink(value: LibraryRoute.ages(personId: person.id)) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.subheadline.weight(.semibold))
                    if gaps > 0 {
                        Text(Copy.libraryFinder.gaps(gaps))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: spacing) {
                ForEach(windows.indices, id: \.self) { index in
                    square(person, window: windows[index], count: counts[index])
                }
            }
        }
    }

    @ViewBuilder
    private func square(_ person: Person, window: LibraryFinder.AgeWindow, count: Int) -> some View {
        let label = Copy.libraryFinder.cellLabel(name: person.name, age: window.label, count: count)
        if LibraryFinder.isBeforeLibrary(window, start: libraryStart) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Color.secondary.opacity(0.3))
                .frame(width: cell, height: cell * 1.8)
                .accessibilityLabel(label)
        } else {
            NavigationLink(value: LibraryRoute.window(personId: person.id, window: window)) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill(LibraryFinder.coverage(count)))
                    .frame(width: cell, height: cell * 1.8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }

    private func fill(_ coverage: LibraryFinder.Coverage) -> Color {
        switch coverage {
        case .empty: .orange
        case .few: Color.accentColor.opacity(0.3)
        case .several: Color.accentColor.opacity(0.6)
        case .many: Color.accentColor
        }
    }

    /// Age marks over the columns: birth, then 1, 2, 5, 10, 15 and 18.
    private var axis: some View {
        ZStack(alignment: .topLeading) {
            ForEach(LibraryFinder.axisMarks, id: \.column) { mark in
                Text(mark.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(mark.column) * (cell + spacing))
            }
        }
        .frame(width: CGFloat(LibraryFinder.childhoodColumns) * (cell + spacing), height: 14, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(.empty, Copy.libraryFinder.legendNone)
            legendItem(.few, "1–2")
            legendItem(.several, "3–9")
            legendItem(.many, "10+")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ coverage: LibraryFinder.Coverage, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(fill(coverage))
                .frame(width: 10, height: 10)
            Text(text)
        }
    }
}

/// Changing the album starts a fresh scan and selection for the same age.
private struct LibrarySearchView: View {
    let person: Person
    let window: LibraryFinder.AgeWindow

    @State private var albums: [LibraryScanner.Album] = []
    @State private var album: LibraryScanner.Album?

    var body: some View {
        LibraryCandidatesView(person: person, window: window, album: album)
            .id(album?.id)
            .toolbar {
                if !albums.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker(Copy.libraryFinder.searchIn, selection: $album) {
                                Text(Copy.libraryFinder.wholeLibrary).tag(nil as LibraryScanner.Album?)
                                ForEach(albums) { album in
                                    Text(album.title).tag(Optional(album))
                                }
                            }
                        } label: {
                            Label(Copy.libraryFinder.searchIn,
                                  systemImage: album == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                        .accessibilityValue(album?.title ?? Copy.libraryFinder.wholeLibrary)
                    }
                }
            }
            .task { albums = await LibraryScanner.albums() }
    }
}

/// The best photo from each moment in one age window, streamed in as the library is looked through, oldest first. Tap to choose, then **Add** imports them through the ordinary batch form with this person already chosen.
private struct LibraryCandidatesView: View {
    let person: Person
    let window: LibraryFinder.AgeWindow
    let album: LibraryScanner.Album?

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(AddFlow.self) private var addFlow

    @State private var scan = LibraryScan()
    @State private var selected: Set<String> = []
    @State private var batch: PhotoBatch?
    @State private var openedGroup: LibraryFinder.Candidate?

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
                    description: Text(album == nil ? Copy.libraryFinder.nothingFoundDetail : Copy.libraryFinder.nothingInAlbum)
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
            await scan.run(window: window, album: album, imported: importedIndex(), skipped: skips.skipped(for: person.id))
        }
        .sheet(item: $openedGroup) { group in
            groupSheet(group)
        }
        .sheet(item: $batch) { batch in
            PhotoBatchFormView(batch: batch, importer: addFlow.importer)
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let album {
                Label(album.title, systemImage: "rectangle.stack")
                    .font(.subheadline)
            }
            if let progress = scan.progress {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text(Copy.libraryFinder.looking(photos: scan.photoCount, moments: progress.total))
                        .font(.subheadline)
                }
            } else if !scan.isFinished {
                ProgressView(Copy.libraryFinder.reading)
            } else if !scan.candidates.isEmpty {
                Text(album == nil
                     ? Copy.libraryFinder.summary(candidates: scan.candidates.count, moments: scan.momentCount)
                     : Copy.libraryFinder.albumSummary)
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
        photoCell(candidate.asset)
            .contextMenu {
                Button(Copy.libraryFinder.dontSuggest(person.name), systemImage: "eye.slash") {
                    let id = candidate.asset.id
                    skips.skip(id, for: person.id)
                    selected.remove(id)
                    scan.remove([id])
                }
            } preview: {
                LibraryPreview(assetId: candidate.asset.id)
            }
            .overlay(alignment: .bottomLeading) {
                if candidate.momentSize > 1 {
                    Button {
                        openedGroup = candidate
                    } label: {
                        Label("\(candidate.momentSize)", systemImage: "square.stack")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.65), in: Capsule())
                            .frame(minWidth: 44, minHeight: 44, alignment: .bottomLeading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel(Copy.libraryFinder.browseGroup(candidate.momentSize))
                }
            }
    }

    private func groupSheet(_ group: LibraryFinder.Candidate) -> some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(group.assets) { asset in
                        photoCell(asset)
                            .contextMenu {
                                Button(selected.contains(asset.id) ? Copy.libraryFinder.deselectPhoto : Copy.libraryFinder.selectPhoto) {
                                    toggle(asset.id)
                                }
                            } preview: {
                                LibraryPreview(assetId: asset.id)
                            }
                    }
                }
                .padding(4)
            }
            .navigationTitle(Copy.libraryFinder.inApp(group.momentSize))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.libraryFinder.done) { openedGroup = nil }
                }
            }
        }
    }

    private func photoCell(_ asset: LibraryFinder.Asset) -> some View {
        let isSelected = selected.contains(asset.id)
        return Button {
            toggle(asset.id)
        } label: {
            LibraryThumbnail(assetId: asset.id)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.25))
                        .padding(6)
                }
                .opacity(isSelected ? 0.8 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(asset.date.displayDay().formatted(date: .abbreviated, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        let ids = scan.candidates.flatMap(\.assets).map(\.id).filter(selected.contains)
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

    private final class CachedAnalysis {
        let value: LibraryFinder.Analysis

        init(_ value: LibraryFinder.Analysis) {
            self.value = value
        }
    }

    private static let analysisCache: NSCache<NSString, CachedAnalysis> = {
        let cache = NSCache<NSString, CachedAnalysis>()
        cache.countLimit = 8_000
        return cache
    }()

    func run(
        window: LibraryFinder.AgeWindow,
        album: LibraryScanner.Album?,
        imported: LibraryFinder.ImportedIndex,
        skipped: Set<String>
    ) async {
        // `.task` runs again whenever the grid reappears, as it does on returning from the photo viewer.
        guard !hasStarted else { return }
        hasStarted = true

        let all = await LibraryScanner.assets(in: window, album: album)
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
            guard !Task.isCancelled else { return }
            // An explicitly chosen album already narrows the photos. Show each group without downloading thumbnails for Vision.
            if album != nil, let cover = moment.assets.first(where: \.isFavorite) ?? moment.assets.first {
                candidates.append(LibraryFinder.Candidate(asset: cover, in: moment))
                progress?.done += 1
                continue
            }

            var analyses: [String: LibraryFinder.Analysis] = [:]
            for asset in LibraryFinder.sample(moment) {
                guard !Task.isCancelled else { return }
                let version = asset.modificationDate?.timeIntervalSinceReferenceDate ?? 0
                let key = "\(asset.id):\(version)" as NSString
                if let cached = Self.analysisCache.object(forKey: key) {
                    analyses[asset.id] = cached.value
                } else if let analysis = await LibraryScanner.analyze(asset.id) {
                    Self.analysisCache.setObject(CachedAnalysis(analysis), forKey: key)
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
        for index in candidates.indices {
            candidates[index].remove(ids)
        }
        candidates.removeAll { $0.assets.isEmpty }
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
                image = nil
                let thumbnail = await LibraryScanner.thumbnail(assetId, side: 140 * displayScale)
                guard !Task.isCancelled else { return }
                image = thumbnail
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
