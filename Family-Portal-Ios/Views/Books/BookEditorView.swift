import SwiftData
import SwiftUI

/// Changing a saved book — the web's `/edit-book/<id>` (`frontend/pages/books/edit-book.tsx`). Opened from the reader's Edit button when the viewer may change the book.
/// Every change is to the editor's own copy and nothing reaches the server until Save, which sends the whole book with the revision it opened. Book-only writing stays in the book; "Edit the original milestone" is the way to change the record itself.
struct BookEditorView: View {
    let response: GetBookResponseDTO
    let onSaved: @MainActor () async -> Void
    let onDeleted: @MainActor () -> Void

    @Environment(BookService.self) private var service
    @Environment(AuthService.self) private var authService
    @Environment(\.dismiss) private var dismiss

    /// Matched by server id, for "Edit the original milestone".
    @Query private var localMilestones: [Milestone]

    @State private var draft: BookDTO
    /// The book as last saved, which `draft` is compared with to know whether there is anything to save.
    @State private var saved: BookDTO
    @State private var hasSaved = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var isConflict = false
    @State private var isConfirmingDiscard = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var editingMilestone: Milestone?

    init(response: GetBookResponseDTO, onSaved: @escaping @MainActor () async -> Void, onDeleted: @escaping @MainActor () -> Void) {
        self.response = response
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        var book = response.book
        if book.categories.isEmpty { book.categories = BookCategory.all.map(\.value) }
        book.density = BookDensity(book.density).rawValue
        book.match = book.match == "all" ? "all" : "any"
        _draft = State(initialValue: book)
        _saved = State(initialValue: book)
    }

    private var assembler: BookAssembler { BookAssembler(book: draft, sources: response.sources) }

    private var isDirty: Bool {
        draft.content(reviewedAt: nil) != saved.content(reviewedAt: nil)
    }

    var body: some View {
        let assembler = self.assembler
        let book = assembler.assemble()
        NavigationStack {
            Form {
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        if isConflict {
                            Button("Close and Reload") {
                                Task {
                                    dismiss()
                                    await onSaved()
                                }
                            }
                        }
                    }
                }

                titleSection(assembler)
                wordsSection
                pickingSection(assembler)
                additionsSection(assembler)

                if book.missing > 0 {
                    Section {
                        Label(
                            book.missing == 1
                                ? "One item was deleted from the family record or can no longer be seen. Saving will drop it from the book."
                                : "\(book.missing) items were deleted from the family record or can no longer be seen. Saving will drop them from the book.",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }

                chapterSections(book, assembler)
                BookLeftOutSection(draft: $draft, assembler: assembler)
                notesSection(book, assembler)
                deleteSection
            }
            .navigationTitle("Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(hasSaved && !isDirty ? "Done" : "Cancel") {
                        if isDirty { isConfirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save(assembler) } }
                            .disabled(!isDirty)
                    }
                }
            }
            .interactiveDismissDisabled(isDirty || isSaving)
            .confirmationDialog("Discard your changes to this book?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .sheet(item: $editingMilestone) { milestone in
                EditMilestoneView(milestone: milestone)
            }
        }
    }

    // MARK: - Title and cover

    private func titleSection(_ assembler: BookAssembler) -> some View {
        Section {
            TextField("Title", text: Binding(
                get: { draft.title },
                set: { draft.title = String($0.prefix(120)) }
            ))
            .font(BookType.serif(.title3))
            NavigationLink {
                BookCoverPicker(coverPhotoId: $draft.coverPhotoId, photos: assembler.candidates().photos)
            } label: {
                HStack(spacing: 12) {
                    BookThumb(photoId: assembler.photos[draft.coverPhotoId] != nil ? draft.coverPhotoId : 0, size: 56, symbol: "photo")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cover")
                        Text(assembler.photos[draft.coverPhotoId] != nil ? "Change cover" : "No cover")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text(BookDay.bookDates(start: draft.startDate, end: draft.endDate))
        }
    }

    // MARK: - Writing

    private var wordsSection: some View {
        Section {
            TextField("Introduction", text: $draft.introduction, prompt: Text("A few lines to open the book"), axis: .vertical)
                .lineLimit(3...10)
            TextField("Closing letter", text: $draft.letter, prompt: Text("Something to say to them at the end of the year"), axis: .vertical)
                .lineLimit(4...12)
            TextField("Signed", text: $draft.signature, prompt: Text("Love, Mom and Dad"))
            Toggle("Include how they grew", isOn: $draft.showGrowth)
        } header: {
            Text("Your words")
        } footer: {
            Text("These live only in this book. Memories worth keeping are better added as milestones, so they appear everywhere.")
        }
        .font(BookType.serif(.body))
    }

    // MARK: - Picking again

    private func pickingSection(_ assembler: BookAssembler) -> some View {
        Section {
            Picker("Length", selection: Binding(
                get: { BookDensity(draft.density) },
                set: { draft.density = $0.rawValue; resuggest() }
            )) {
                ForEach(BookDensity.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            ForEach(BookCategory.all) { category in
                let isOn = draft.categories.contains(category.value)
                Toggle(category.label, isOn: Binding(
                    get: { isOn },
                    set: { on in
                        draft.categories = on
                            ? draft.categories + [category.value]
                            : draft.categories.filter { $0 != category.value }
                        resuggest()
                    }
                ))
                // The last kind left cannot be switched off: a book of nothing.
                .disabled(isOn && draft.categories.count == 1)
            }

            if assembler.isMulti {
                Picker("Which photos", selection: Binding(
                    get: { draft.match },
                    set: { draft.match = $0; resuggest() }
                )) {
                    Text("Any of them").tag("any")
                    Text("All of them").tag("all")
                }
            }
        } header: {
            Text("How many photos")
        } footer: {
            Text("Changing these picks again. Anything you've kept stays, and anything you've removed stays out.")
        }
    }

    private func resuggest() {
        let suggestion = BookAssembler(book: draft, sources: response.sources).suggest(
            density: BookDensity(draft.density),
            current: draft.items,
            excluded: draft.excluded,
            coverPhotoId: draft.coverPhotoId
        )
        draft.items = suggestion.items
    }

    // MARK: - New since the last save

    @ViewBuilder
    private func additionsSection(_ assembler: BookAssembler) -> some View {
        let additions = hasSaved ? [] : assembler.additions(since: response.book.reviewedAt, items: draft.items, excluded: draft.excluded)
        if !additions.isEmpty {
            Section {
                ForEach(additions, id: \.key) { item in
                    HStack(spacing: 12) {
                        BookItemSummary(item: item, assembler: assembler)
                        Spacer(minLength: 4)
                        Button("Add") { add(item, assembler) }
                            .buttonStyle(.borderless)
                        Button("Leave Out") {
                            var out = item
                            out.photoId = 0
                            draft.excluded.append(out)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("New since you last saved")
            } footer: {
                Text("Added to the family record after this book was last saved. Nothing joins the book until you add it.")
            }
        }
    }

    private func add(_ item: BookItemDTO, _ assembler: BookAssembler) {
        var items = draft.items
        assembler.insertByDay(&items, item)
        draft.items = items
        draft.excluded.removeAll { $0.key == item.key }
    }

    // MARK: - Chapters

    @ViewBuilder
    private func chapterSections(_ book: AssembledBook, _ assembler: BookAssembler) -> some View {
        ForEach(book.chapters.filter { !$0.items.isEmpty }) { chapter in
            let opensWithHero = chapter.blocks.contains { if case .hero = $0 { return true } else { return false } }
            Section {
                ForEach(Array(chapter.items.enumerated()), id: \.element) { position, index in
                    if draft.items.indices.contains(index) {
                        BookEditorItemRow(
                            item: itemBinding(index),
                            assembler: assembler,
                            opensChapter: position == 0 && opensWithHero,
                            canMoveEarlier: position > 0,
                            canMoveLater: position < chapter.items.count - 1,
                            onMove: { delta in move(in: chapter.items, from: position, by: delta) },
                            onRemove: { remove(at: index) },
                            onEditOriginal: editOriginal(draft.items[index])
                        )
                    }
                }
                .onMove { from, to in reorder(chapter.items, from: from, to: to) }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(chapter.title.isEmpty ? "Untitled" : chapter.title)
                    Spacer()
                    if !chapter.dates.isEmpty {
                        Text(chapter.dates).textCase(nil)
                    }
                }
            }
        }
    }

    private func itemBinding(_ index: Int) -> Binding<BookItemDTO> {
        Binding(
            get: { draft.items.indices.contains(index) ? draft.items[index] : BookItemDTO(kind: .photo, sourceId: 0) },
            set: { if draft.items.indices.contains(index) { draft.items[index] = $0 } }
        )
    }

    /// Swaps an item with its neighbour in the chapter, which may sit elsewhere in the book's list.
    private func move(in chapterItems: [Int], from position: Int, by delta: Int) {
        let target = position + delta
        guard chapterItems.indices.contains(target) else { return }
        draft.items.swapAt(chapterItems[position], chapterItems[target])
    }

    /// A drag within one chapter: the chapter's items change places among the slots they already hold in the book's list.
    private func reorder(_ chapterItems: [Int], from: IndexSet, to: Int) {
        var moved = chapterItems.map { draft.items[$0] }
        moved.move(fromOffsets: from, toOffset: to)
        var items = draft.items
        for (slot, index) in chapterItems.enumerated() { items[index] = moved[slot] }
        draft.items = items
    }

    /// Out of the book and onto the excluded list, so picking again never brings it back.
    private func remove(at index: Int) {
        guard draft.items.indices.contains(index) else { return }
        var item = draft.items.remove(at: index)
        item.caption = ""
        item.pinned = false
        item.photoId = 0
        draft.excluded.append(item)
    }

    /// Nil when the milestone has not reached this device yet, which hides the action rather than opening nothing.
    private func editOriginal(_ item: BookItemDTO) -> (() -> Void)? {
        // A book can hold a milestone from a family the account only views; that one stays read-only here too.
        guard let milestone = localMilestone(for: item), authService.access.canContribute(to: milestone) else { return nil }
        return { editingMilestone = milestone }
    }

    private func localMilestone(for item: BookItemDTO) -> Milestone? {
        guard item.itemKind == .milestone else { return nil }
        return localMilestones.first { $0.serverId == item.sourceId }
    }

    // MARK: - What went in

    private func notesSection(_ book: AssembledBook, _ assembler: BookAssembler) -> some View {
        let (milestones, photos) = assembler.candidates()
        let entries = draft.items.filter { assembler.itemDay($0) != nil }
        let milestonesUsed = entries.filter { $0.itemKind == .milestone }.count
        let photosUsed = entries.filter { $0.itemKind == .photo }.count
            + entries.filter { $0.itemKind == .milestone && $0.photoId != 0 }.count
            + (book.cover != nil ? 1 : 0)
        let unready = response.sources.photos.filter { $0.status != 0 }.count
        let undated = response.sources.photos.filter { $0.status == 0 && !BookDay.isRealDay(BookDay.dayOf($0.photoDate)) }.count
        return Section("What went into this book") {
            Text("\(milestonesUsed) of \(milestones.count) records from these dates")
            Text("\(photosUsed) of \(photos.count) photos from these dates")
            if undated > 0 { Text("\(undated) photos have no date and were left out") }
            if unready > 0 { Text("\(unready) photos are still processing or failed") }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                if isDeleting {
                    ProgressView()
                } else {
                    Text("Delete This Book…")
                }
            }
            .disabled(isDeleting)
            .confirmationDialog("Delete this book?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Book", role: .destructive) { Task { await delete() } }
            } message: {
                Text("The photos and milestones stay in the family record.")
            }
        }
    }

    // MARK: - Saving

    private func save(_ assembler: BookAssembler) async {
        isSaving = true
        error = nil
        isConflict = false
        defer { isSaving = false }

        var book = draft
        book.items = draft.items.filter { assembler.itemDay($0) != nil }
        if assembler.photos[book.coverPhotoId] == nil { book.coverPhotoId = 0 }
        do {
            let result = try await service.updateBook(
                id: response.book.id,
                revision: draft.revision,
                content: book.content(reviewedAt: response.now.isEmpty ? nil : response.now)
            )
            draft.revision = result.revision
            draft.items = result.items
            draft.excluded = result.excluded
            draft.title = result.title
            saved = draft
            hasSaved = true
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isConflict = BookService.isChangedConflict(error)
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteBook(id: response.book.id)
            dismiss()
            onDeleted()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Rows

/// A server photo as a small square, or a symbol where there is none.
struct BookThumb: View {
    let photoId: Int
    var size: CGFloat = 52
    var symbol: String = "note.text"

    var body: some View {
        Group {
            if photoId > 0 {
                RemotePhotoView(remoteId: photoId, size: .thumb)
            } else {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A thumbnail or a milestone's words, with when it is from.
private struct BookItemSummary: View {
    let item: BookItemDTO
    let assembler: BookAssembler

    var body: some View {
        HStack(spacing: 12) {
            if item.itemKind == .photo {
                BookThumb(photoId: item.sourceId, size: 44)
            } else if let m = assembler.milestones[item.sourceId] {
                Image(systemName: MilestoneCategory(rawValue: m.category)?.icon ?? "note.text")
                    .foregroundStyle(MilestoneCategory(rawValue: m.category)?.color ?? .gray)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let m = assembler.milestones[item.sourceId], item.itemKind == .milestone {
                    Text(m.description).lineLimit(2)
                }
                Text(assembler.detailOf(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BookEditorItemRow: View {
    @Binding var item: BookItemDTO
    let assembler: BookAssembler
    let opensChapter: Bool
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onMove: (Int) -> Void
    let onRemove: () -> Void
    let onEditOriginal: (() -> Void)?

    private var milestone: BookMilestoneDTO? {
        item.itemKind == .milestone ? assembler.milestones[item.sourceId] : nil
    }

    private var photo: BookImageDTO? {
        item.itemKind == .photo ? assembler.photos[item.sourceId] : nil
    }

    private var attached: [Int] {
        (milestone?.photoIds ?? []).filter { assembler.photos[$0] != nil }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BookThumb(
                photoId: photo?.id ?? item.photoId,
                symbol: milestone.flatMap { MilestoneCategory(rawValue: $0.category)?.icon } ?? "note.text"
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if opensChapter {
                        Text("Opens the chapter")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    if item.pinned {
                        Label("Kept", systemImage: "pin.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                if let milestone {
                    Text(milestone.description)
                        .font(.subheadline)
                }
                Text(assembler.detailOf(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let photo {
                    TextField(
                        "Caption in this book",
                        text: Binding(get: { item.caption }, set: { item.caption = String($0.prefix(300)) }),
                        prompt: Text(BookAssembler.originalCaption(photo).isEmpty ? "Add a caption for this book" : BookAssembler.originalCaption(photo)),
                        axis: .vertical
                    )
                    .font(.footnote)
                    .textFieldStyle(.roundedBorder)
                }
                if !attached.isEmpty {
                    attachedPicker
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button { onMove(-1) } label: { Label("Move Earlier", systemImage: "arrow.up") }
                    .disabled(!canMoveEarlier)
                Button { onMove(1) } label: { Label("Move Later", systemImage: "arrow.down") }
                    .disabled(!canMoveLater)
                Button { item.pinned.toggle() } label: {
                    Label(item.pinned ? "Don't Keep" : "Keep", systemImage: item.pinned ? "pin.slash" : "pin")
                }
                if let onEditOriginal {
                    Button(action: onEditOriginal) { Label("Edit the Original Milestone", systemImage: "pencil") }
                }
                Button(role: .destructive, action: onRemove) { Label("Remove from Book", systemImage: "minus.circle") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Item actions")
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onRemove) { Label("Remove", systemImage: "minus.circle") }
        }
        .swipeActions(edge: .leading) {
            Button { item.pinned.toggle() } label: {
                Label(item.pinned ? "Don't Keep" : "Keep", systemImage: item.pinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
    }

    /// Which of the milestone's photos the book shows beside it, or none.
    private var attachedPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    item.photoId = 0
                } label: {
                    Text("No photo")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .frame(height: 40)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(selection(item.photoId == 0))
                }
                ForEach(attached, id: \.self) { id in
                    Button {
                        item.photoId = id
                    } label: {
                        BookThumb(photoId: id, size: 40)
                            .overlay(selection(item.photoId == id))
                    }
                    .accessibilityLabel("Show this photo")
                    .accessibilityAddTraits(item.photoId == id ? .isSelected : [])
                }
            }
        }
        .buttonStyle(.borderless)
    }

    private func selection(_ on: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(on ? Color.accentColor : .clear, lineWidth: 2)
    }
}

// MARK: - Not in the book

/// Everything else from the book's dates, month by month, to add by hand.
private struct BookLeftOutSection: View {
    @Binding var draft: BookDTO
    let assembler: BookAssembler

    private struct Month: Identifiable {
        let id: String
        var milestones: [BookMilestoneDTO] = []
        var photos: [BookImageDTO] = []
    }

    private var months: [Month] {
        let included = Set(draft.items.map(\.key))
        var used = Set(draft.items.filter { $0.itemKind == .milestone && $0.photoId != 0 }.map(\.photoId))
        used.insert(draft.coverPhotoId)
        let (milestones, photos) = assembler.candidates()
        var order: [String] = []
        var months: [String: Month] = [:]
        func touch(_ day: String) -> String {
            let key = String(day.prefix(7))
            if months[key] == nil {
                months[key] = Month(id: key)
                order.append(key)
            }
            return key
        }
        for m in milestones where !included.contains(BookItemDTO.milestone(m.id).key) {
            months[touch(BookDay.dayOf(m.milestoneDate))]?.milestones.append(m)
        }
        for p in photos where !included.contains(BookItemDTO.photo(p.id).key) && !used.contains(p.id) {
            months[touch(BookDay.dayOf(p.photoDate))]?.photos.append(p)
        }
        return order.sorted().compactMap { months[$0] }
    }

    var body: some View {
        let months = self.months
        if !months.isEmpty {
            Section {
                ForEach(months) { month in
                    DisclosureGroup {
                        ForEach(month.milestones, id: \.id) { m in
                            HStack {
                                Image(systemName: MilestoneCategory(rawValue: m.category)?.icon ?? "note.text")
                                    .foregroundStyle(MilestoneCategory(rawValue: m.category)?.color ?? .gray)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.description).font(.subheadline)
                                    Text(BookDay.shortDay(BookDay.dayOf(m.milestoneDate)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Add") {
                                    add(.milestone(m.id, photoId: m.photoIds.first { assembler.photos[$0] != nil } ?? 0))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        if !month.photos.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 6) {
                                ForEach(month.photos, id: \.id) { p in
                                    Button {
                                        add(.photo(p.id))
                                    } label: {
                                        BookThumb(photoId: p.id, size: 64)
                                            .overlay(alignment: .bottomTrailing) {
                                                Image(systemName: "plus.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, Color.accentColor)
                                                    .padding(3)
                                            }
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Add the photo from \(assembler.detailOf(.photo(p.id)))")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } label: {
                        HStack {
                            Text(BookDay.monthName(month.id + "-01", year: true))
                            Spacer()
                            Text(summary(month))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Not in the book")
            } footer: {
                Text("Everything else from these dates. Add anything you miss.")
            }
        }
    }

    private func summary(_ month: Month) -> String {
        var parts: [String] = []
        if !month.milestones.isEmpty {
            parts.append("\(month.milestones.count) milestone\(month.milestones.count == 1 ? "" : "s")")
        }
        if !month.photos.isEmpty {
            parts.append("\(month.photos.count) photo\(month.photos.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func add(_ item: BookItemDTO) {
        var items = draft.items
        assembler.insertByDay(&items, item)
        draft.items = items
        draft.excluded.removeAll { $0.key == item.key }
    }
}

// MARK: - Cover

private struct BookCoverPicker: View {
    @Binding var coverPhotoId: Int
    let photos: [BookImageDTO]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                ContentUnavailableView("No Photos", systemImage: "photo", description: Text("There are no photos from these dates to use as the cover."))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(photos, id: \.id) { photo in
                        Button {
                            coverPhotoId = photo.id
                            dismiss()
                        } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { RemotePhotoView(remoteId: photo.id, size: .thumb) }
                                .clipped()
                                .overlay(alignment: .topTrailing) {
                                    if photo.id == coverPhotoId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.accentColor)
                                            .font(.title3)
                                            .padding(6)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use the photo from \(BookDay.shortDay(BookDay.dayOf(photo.photoDate))) as the cover")
                        .accessibilityAddTraits(photo.id == coverPhotoId ? .isSelected : [])
                    }
                }
                .padding(4)
            }
        }
        .navigationTitle("Cover")
        .navigationBarTitleDisplayMode(.inline)
    }
}
