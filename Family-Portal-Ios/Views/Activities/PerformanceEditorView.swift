import SwiftUI
import SwiftData
import OSLog

/// One editor for a whole performance — which routine (when new), its results, head-to-head, date, notes and photos — saved together through `SaveAppearance`, so a refused part leaves nothing half-written. The web's competition-page results editor.
/// Which routine performed at which competition is fixed once recorded: that pair is the record's identity, not a field on it.
struct PerformanceEditorView: View {
    let eventId: Int
    /// `nil` records a new performance.
    let existing: AppearanceDetailDTO?
    /// The season's routines, for the picker on a new performance and for each one's roster.
    let entries: [EntryViewDTO]
    let activityId: Int?
    let activityKind: String
    let labels: ActivityLabels
    let onSaved: @MainActor () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var entryId: Int?
    @State private var drafts: [ResultDraft]
    @State private var occurredAt: ActivityDateField
    @State private var notes: String
    @State private var matchup: MatchupDraft
    @State private var photoIds: [Int]
    @State private var vocabulary = ActivityScreenState<ListActivityVocabularyResponseDTO>()
    @State private var invalidRow: ResultDraft.ID?
    @State private var validationError: ResultValidationError?
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var isPickingPhotos = false
    @State private var isConfirmingDelete = false

    /// `entryId` preselects the routine of a new performance, as the competition page's "Record results" does.
    init(
        eventId: Int,
        existing: AppearanceDetailDTO? = nil,
        entryId: Int? = nil,
        entries: [EntryViewDTO],
        activityId: Int?,
        activityKind: String,
        labels: ActivityLabels,
        onSaved: @escaping @MainActor () async -> Void
    ) {
        self.eventId = eventId
        self.existing = existing
        self.entries = entries
        self.activityId = activityId
        self.activityKind = activityKind
        self.labels = labels
        self.onSaved = onSaved
        _entryId = State(initialValue: existing?.entry.id ?? entryId)
        _drafts = State(initialValue: existing?.results.map(ResultDraft.init) ?? [])
        _occurredAt = State(initialValue: existing.map { ActivityDateField($0.appearance.occurredAt) } ?? ActivityDateField())
        _notes = State(initialValue: existing?.appearance.notes ?? "")
        _matchup = State(initialValue: existing.map { MatchupDraft(Matchup($0.appearance)) } ?? MatchupDraft())
        _photoIds = State(initialValue: existing?.photoIds ?? [])
    }

    private var roster: [Int] {
        entries.first { $0.entry.id == entryId }?.personIds ?? []
    }

    private var title: String {
        if let existing { return existing.entry.name }
        return entries.first { $0.entry.id == entryId }?.entry.name ?? "Record \(labels.appearance)"
    }

    private var quickLabels: [String] {
        ActivityResults.quickLabels(kind: activityKind, used: vocabulary.value?.adjudications ?? [])
    }

    private var canAddRow: Bool { drafts.count < ActivityFieldLimit.resultsPerAppearance }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                if existing == nil {
                    entrySection
                }

                ForEach($drafts) { $draft in
                    resultSection($draft)
                }

                addResultSection

                AppearanceMatchupSection(draft: $matchup, labels: labels)
                AppearanceDateSection(field: $occurredAt, labels: labels)
                AppearanceNotesSection(notes: $notes)

                Section {
                    Button {
                        isPickingPhotos = true
                    } label: {
                        LabeledContent("Photos and videos", value: photoIds.isEmpty ? "" : "\(photoIds.count)")
                    }
                    ActivityPhotoStrip(photoIds: photoIds)
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete \(labels.appearance)", systemImage: "trash")
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(entryId == nil || isSaving || matchup.error != nil)
                }
            }
            .task {
                guard let activityId else { return }
                await vocabulary.load(service.vocabulary(activityId: activityId))
            }
            .sheet(isPresented: $isPickingPhotos) {
                // Picking only changes the selection; it is written with everything else on Save.
                ActivityPhotoPickerView(
                    attachedPhotoIds: photoIds,
                    subject: labels.appearance.lowercased(),
                    save: { photoIds = $0 },
                    onSaved: {}
                )
            }
            .confirmationDialog(
                "Delete this \(labels.appearance.lowercased())?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its results and attached photos go with it. This can't be undone.")
            }
        }
    }

    // MARK: - Which routine

    @ViewBuilder
    private var entrySection: some View {
        if entries.isEmpty {
            Section {
                Text("This season has no \(labels.entryPlural.lowercased()) yet. They're set up on the web.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            // Two performances of one routine at one competition are allowed on purpose (rounds), so nothing is filtered out.
            Section(labels.entry) {
                Picker(labels.entry, selection: $entryId) {
                    Text("Choose…").tag(Int?.none)
                    ForEach(entries) { entryView in
                        Text(entryLabel(entryView)).tag(Int?(entryView.entry.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            }
        }
    }

    private func entryLabel(_ entryView: EntryViewDTO) -> String {
        let roster = ActivityPeople(people).rosterText(entryView.personIds)
        let descriptors = ActivityEntryText.descriptors(entryView.entry)
        let detail = [descriptors, roster].compactMap { $0 }.filter { !$0.isEmpty }
        return detail.isEmpty
            ? entryView.entry.name
            : "\(entryView.entry.name) — \(detail.joined(separator: " · "))"
    }

    // MARK: - Results

    private var addResultSection: some View {
        Section {
            if !quickLabels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickLabels, id: \.self) { label in
                            Button(label) { addRow(ResultDraft(kind: .adjudication, label: label)) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            ForEach(ActivityResultKind.allCases, id: \.self) { kind in
                Button {
                    addRow(ResultDraft(kind: kind))
                } label: {
                    Label(kindName(kind), systemImage: "plus.circle")
                }
            }
        } header: {
            Text(drafts.isEmpty ? "Add a result" : "Add another")
        } footer: {
            if drafts.isEmpty && existing.map({ !$0.results.isEmpty }) == true {
                Text("Saving with no results clears this \(labels.appearance.lowercased())'s results sheet.")
            }
        }
        .disabled(!canAddRow || isSaving)
    }

    private func addRow(_ draft: ResultDraft) {
        guard canAddRow else { return }
        drafts.append(draft)
    }

    @ViewBuilder
    private func resultSection(_ draft: Binding<ResultDraft>) -> some View {
        let row = draft.wrappedValue

        Section {
            Picker("Kind", selection: draft.kind) {
                ForEach(ActivityResultKind.allCases, id: \.self) { kind in
                    Text(kindName(kind)).tag(kind)
                }
            }

            switch row.kind {
            case .adjudication:
                labelField(draft, prompt: "Adjudication", suggestions: vocabulary.value?.adjudications ?? [])
            case .award:
                labelField(draft, prompt: "Award", suggestions: vocabulary.value?.awards ?? [])
            case .placement:
                HStack {
                    TextField("Rank", text: clamped(draft.rankText, to: 6))
                        .keyboardType(.numberPad)
                    Text("of")
                        .foregroundStyle(.secondary)
                    TextField("Field size", text: clamped(draft.outOfText, to: 6))
                        .keyboardType(.numberPad)
                }
                labelField(draft, prompt: "Label (optional)", suggestions: [])
            case .score:
                TextField("Score", text: clamped(draft.scoreText, to: 20))
                    .keyboardType(.decimalPad)
                labelField(draft, prompt: "Label (optional)", suggestions: [])
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField("Category", text: clamped(draft.category, to: ActivityFieldLimit.label.characters))
                VocabularySuggestions(
                    suggestions: vocabulary.value?.categories ?? [],
                    text: draft.category
                )
            }

            if !roster.isEmpty {
                Picker("For", selection: draft.personId) {
                    Text("Whole \(labels.entry.lowercased())").tag(Int?.none)
                    ForEach(roster, id: \.self) { personId in
                        Text(personName(personId)).tag(Int?(personId))
                    }
                }
            }

            TextField("Notes", text: clamped(draft.notes, to: ActivityFieldLimit.notes.characters), axis: .vertical)
                .lineLimit(1...4)

            Button(role: .destructive) {
                drafts.removeAll { $0.id == row.id }
                if invalidRow == row.id {
                    invalidRow = nil
                    validationError = nil
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        } header: {
            Text(kindName(row.kind))
        } footer: {
            if invalidRow == row.id, let validationError {
                Text(validationError.localizedDescription)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func labelField(
        _ draft: Binding<ResultDraft>,
        prompt: String,
        suggestions: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(prompt, text: clamped(draft.label, to: ActivityFieldLimit.label.characters))
            VocabularySuggestions(suggestions: suggestions, text: draft.label)
        }
    }

    private func kindName(_ kind: ActivityResultKind) -> String {
        switch kind {
        case .adjudication: return "Adjudication"
        case .placement: return "Placement"
        case .award: return "Award"
        case .score: return "Score"
        }
    }

    private func personName(_ personId: Int) -> String {
        ActivityPeople(people).name(personId) ?? "Person \(personId)"
    }

    /// Caps a field at the length the server would silently truncate it to. `prefix` rather than `clamp`, since trimming while someone types eats the space they just pressed.
    private func clamped(_ binding: Binding<String>, to limit: Int) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = String($0.prefix(limit)) }
        )
    }

    // MARK: - Saving

    private func save() {
        guard let entryId else { return }
        if let failure = ResultSheet.validate(drafts, roster: roster) {
            invalidRow = failure.row
            validationError = failure.error
            saveError = nil
            return
        }
        invalidRow = nil
        validationError = nil
        saveError = nil
        isSaving = true

        let inputs = ResultSheet.inputs(drafts)
        Task {
            do {
                // The date is always sent: an absent one means "unknown", not "leave it alone".
                _ = try await service.saveAppearance(
                    id: existing?.appearance.id ?? 0,
                    eventId: eventId,
                    entryId: entryId,
                    occurredAt: occurredAt.date,
                    notes: notes,
                    matchup: matchup.matchup,
                    results: inputs,
                    photoIds: photoIds
                )
                await onSaved()
                dismiss()
            } catch {
                AppLog.activities.error(
                    "Saving a performance failed: \(String(describing: error), privacy: .public)"
                )
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func delete() {
        guard let existing else { return }
        isSaving = true
        Task {
            do {
                try await service.deleteAppearance(id: existing.appearance.id)
                await onSaved()
                dismiss()
            } catch {
                AppLog.activities.error(
                    "Deleting an appearance failed: \(String(describing: error), privacy: .public)"
                )
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

struct VocabularySuggestions: View {
    let suggestions: [String]
    @Binding var text: String

    private static let maximum = 8

    private var matches: [String] {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = typed.isEmpty
            ? suggestions
            : suggestions.filter { $0.localizedCaseInsensitiveContains(typed) }

        if candidates.count == 1, candidates[0].caseInsensitiveCompare(typed) == .orderedSame {
            return []
        }
        return Array(candidates.prefix(Self.maximum))
    }

    var body: some View {
        if !matches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(matches, id: \.self) { suggestion in
                        Button(suggestion) { text = suggestion }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
