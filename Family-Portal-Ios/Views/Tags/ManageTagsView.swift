import SwiftUI

/// The family's tag vocabulary — the web's Manage Tags page: create, rename, recolour, set the auto-suggest phrase, delete.
/// Online only (see `TagService`). After each change the local `FamilyTag` mirror is re-pulled, so pickers and chips elsewhere catch up without waiting for a sync.
struct ManageTagsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SyncService.self) private var syncService

    @State private var tags: [TagDTO] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var newName = ""
    @State private var newColor = TagColor.color(forHex: Self.defaultColorHex)
    @State private var newFamilyId = 0
    @State private var editing: TagDTO?
    @State private var tagToDelete: TagDTO?

    /// The web's default for a new tag.
    private static let defaultColorHex = "#6366f1"

    private let service = TagService()

    private var families: [FamilyInfoDTO] { authService.families }

    private var access: FamilyAccess { authService.access }

    /// Where a new tag can go: families the account can add to, never one it only views.
    private var writableFamilies: [FamilyRefDTO] { access.contributableFamilies }

    private var sortedTags: [TagDTO] {
        tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            if !writableFamilies.isEmpty {
                createSection
            }

            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                tagsSection
            }
        }
        .navigationTitle(Copy.account.tags)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $editing) { tag in
            NavigationStack {
                TagEditorView(tag: tag) { name, color, phrase in
                    try await update(tag, name: name, color: color, phrase: phrase)
                }
            }
        }
        .confirmationDialog(
            "Delete Tag",
            isPresented: Binding(
                get: { tagToDelete != nil },
                set: { if !$0 { tagToDelete = nil } }
            ),
            presenting: tagToDelete
        ) { tag in
            Button("Delete \"\(tag.name)\"", role: .destructive) {
                Task { await delete(tag) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { tag in
            Text("\"\(tag.name)\" will be removed from all milestones and photos.")
        }
    }

    // MARK: - Sections

    private var createSection: some View {
        Section {
            if writableFamilies.count > 1 {
                Picker("Family", selection: $newFamilyId) {
                    ForEach(writableFamilies, id: \.id) { family in
                        Text(family.name.isEmpty ? "Family \(family.id)" : family.name)
                            .tag(family.id)
                    }
                }
            }
            TextField("Tag name", text: $newName)
                .textInputAutocapitalization(.words)
                .onChange(of: newName) { _, value in
                    if value.count > TagService.nameLimit { newName = String(value.prefix(TagService.nameLimit)) }
                }
                .submitLabel(.done)
                .onSubmit { Task { await create() } }
            ColorPicker("Color", selection: $newColor, supportsOpacity: false)
            Button("Add Tag") {
                Task { await create() }
            }
            .disabled(isSaving || trimmedNewName.isEmpty)
        } header: {
            Text("New Tag")
        } footer: {
            Text("Tags organize your family's milestones and photos.")
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        Section {
            if tags.isEmpty {
                Text(writableFamilies.isEmpty ? "No tags yet." : "No tags yet. Create one above.")
                    .foregroundStyle(.secondary)
            } else {
                // Renaming takes a contributor of the tag's family and deleting an admin, as on the web; a tag the account can't change is listed without either.
                ForEach(sortedTags) { tag in
                    if access.canContribute(tag.familyId) {
                        Button {
                            editing = tag
                        } label: {
                            row(for: tag, editable: true)
                        }
                        .disabled(isSaving)
                        .swipeActions(edge: .trailing) {
                            if access.canAdmin(tag.familyId) {
                                Button("Delete", role: .destructive) {
                                    tagToDelete = tag
                                }
                            }
                        }
                    } else {
                        row(for: tag, editable: false)
                    }
                }
            }
        } footer: {
            if tags.contains(where: { access.canContribute($0.familyId) }) {
                Text("Tap a tag to edit it, or swipe to delete.")
            }
        }
    }

    private func row(for tag: TagDTO, editable: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(TagColor.color(forHex: tag.color))
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .foregroundStyle(.primary)
                if !tag.autoPhrase.isEmpty {
                    Text("Suggested for “\(tag.autoPhrase)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if families.count > 1, let family = families.first(where: { $0.id == tag.familyId }) {
                    Text(family.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if editable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(editable ? "Edit tag" : "")
    }

    // MARK: - Actions

    private func load() async {
        if newFamilyId == 0 {
            newFamilyId = writableFamilies.first(where: \.isPrimary)?.id ?? writableFamilies.first?.id ?? 0
        }
        do {
            tags = try await service.list()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func create() async {
        let name = trimmedNewName
        guard !name.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let tag = try await service.create(name: name, color: TagColor.hex(for: newColor), familyId: newFamilyId)
            tags.append(tag)
            newName = ""
            errorMessage = nil
            await syncService.refreshTags()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Throws back to the editor, which keeps itself open and shows the reason.
    private func update(_ tag: TagDTO, name: String, color: String, phrase: String) async throws {
        let saved = try await service.update(id: tag.id, name: name, color: color, autoPhrase: phrase)
        if let index = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[index] = saved
        }
        errorMessage = nil
        await syncService.refreshTags()
    }

    private func delete(_ tag: TagDTO) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.delete(id: tag.id)
            tags.removeAll { $0.id == tag.id }
            errorMessage = nil
            await syncService.refreshTags()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One tag's name, colour and auto-suggest phrase, presented as a sheet over the list.
private struct TagEditorView: View {
    let tag: TagDTO
    let save: @MainActor (_ name: String, _ color: String, _ phrase: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var color: Color
    /// Untouched, the tag keeps its stored string exactly — including a malformed one the picker could only approximate.
    @State private var colorTouched = false
    @State private var phrase: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(tag: TagDTO, save: @escaping @MainActor (_ name: String, _ color: String, _ phrase: String) async throws -> Void) {
        self.tag = tag
        self.save = save
        _name = State(initialValue: tag.name)
        _color = State(initialValue: TagColor.color(forHex: tag.color))
        _phrase = State(initialValue: tag.autoPhrase)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section {
                TextField("Tag name", text: $name)
                    .textInputAutocapitalization(.words)
                    .onChange(of: name) { _, value in
                        if value.count > TagService.nameLimit { name = String(value.prefix(TagService.nameLimit)) }
                    }
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                    .onChange(of: color) { _, _ in colorTouched = true }
            }

            Section {
                TextField("e.g. kids at the lake cabin", text: $phrase, axis: .vertical)
                    .lineLimit(1...3)
                    .onChange(of: phrase) { _, value in
                        if value.count > TagService.phraseLimit { phrase = String(value.prefix(TagService.phraseLimit)) }
                    }
            } header: {
                Text("Suggest for photos of…")
            } footer: {
                Text("Optional. Photos that match are suggested for this tag.")
            }
        }
        .navigationTitle("Edit Tag")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await submit() }
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func submit() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let hex = colorTouched ? TagColor.hex(for: color) : tag.color
            try await save(trimmedName, hex, phrase.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
