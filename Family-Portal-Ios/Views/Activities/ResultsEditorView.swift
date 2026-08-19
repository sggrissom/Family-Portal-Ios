import SwiftUI
import SwiftData
import OSLog

/// The results sheet for one performance, edited as a list and saved as one
/// array.
///
/// This is the screen the phone client exists for. You are in a ballroom, you
/// have just watched the routine, and the results sheet is in your hand —
/// entering it *there* is the point. Everything about the shape follows from
/// `SetAppearanceResults` being a whole-set replace: the save carries every row
/// the appearance should end up with, and array position is the sort order, so
/// reordering is a reordered array rather than a second field to keep in sync.
struct ResultsEditorView: View {
    let appearanceId: Int
    let entryName: String
    /// The entry's roster, in server ids. A result may name one person on it and
    /// nobody else.
    let roster: [Int]
    /// For vocabulary autocomplete. `nil` when the caller could not work out
    /// which program this belongs to, in which case the fields are plain text —
    /// degraded, but never blocking a save at a venue.
    let activityId: Int?
    let initialResults: [ActivityResultDTO]
    let labels: ActivityLabels
    /// Lets the screen that opened this refresh itself; the write does not touch
    /// anyone else's snapshot cache.
    let onSaved: @MainActor () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var drafts: [ResultDraft] = []
    @State private var vocabulary = ActivityScreenState<ListActivityVocabularyResponseDTO>()
    @State private var invalidRow: ResultDraft.ID?
    @State private var validationError: ResultValidationError?
    @State private var saveError: String?
    @State private var isSaving = false
    /// Seeded exactly once. From then on the sheet is the user's working copy —
    /// re-seeding would resurrect rows they deleted and throw away half-typed
    /// ones.
    @State private var didSeed = false

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

                ForEach($drafts) { $draft in
                    resultSection($draft)
                }

                Section {
                    Button {
                        drafts.append(ResultDraft())
                    } label: {
                        Label("Add Result", systemImage: "plus.circle")
                    }
                    .disabled(drafts.count >= ActivityFieldLimit.resultsPerAppearance)
                }

                if drafts.isEmpty {
                    Section {
                        Text("Saving with no results clears this \(labels.appearance.lowercased())'s results sheet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(entryName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                guard !didSeed else { return }
                didSeed = true
                drafts = initialResults.map(ResultDraft.init)
            }
            .task {
                guard let activityId else { return }
                await vocabulary.load(service.vocabulary(activityId: activityId))
            }
        }
    }

    // MARK: - One result

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

            // Every kind carries a category — it is what the season view counts
            // by, and the vocabulary collects it from every result regardless of
            // kind.
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

    /// Caps a field at the length the server would silently truncate it to.
    ///
    /// Over-length text is *truncated* on write, not refused, so a field that
    /// let the user type past the limit would quietly keep less than they wrote.
    /// `prefix` rather than `clamp` here because this runs on every keystroke:
    /// trimming while someone is typing eats the space they just pressed.
    private func clamped(_ binding: Binding<String>, to limit: Int) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = String($0.prefix(limit)) }
        )
    }

    // MARK: - Saving

    private func save() {
        // Checked here so the common mistakes never cost a round trip in a
        // building with no signal. The server checks all of it again and is the
        // one that decides — `ResultValidationError` carries the server's own
        // sentences so both routes read the same.
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
                _ = try await service.setAppearanceResults(appearanceId: appearanceId, results: inputs)
                await onSaved()
                dismiss()
            } catch {
                // The sheet stays open: a refusal is something to fix, not
                // something to acknowledge, and the user's rows are still here.
                // `APIError` presents a proc's 400 body verbatim, so this is the
                // backend's own sentence.
                AppLog.activities.error(
                    "Saving results failed: \(String(describing: error), privacy: .public)"
                )
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// What this family has already typed into a free-text field.
///
/// Not a nicety. Adjudication labels are free text by design and nothing
/// normalizes them at write time, so without suggestions "High Gold" becomes
/// "high gold" and "Hi Gold" and the season view cannot even *count* them, let
/// alone rank them.
struct VocabularySuggestions: View {
    let suggestions: [String]
    @Binding var text: String

    /// Enough to be useful on one line's worth of scrolling; a family with two
    /// hundred distinct labels has a data-entry problem a longer list would not
    /// fix.
    private static let maximum = 8

    private var matches: [String] {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = typed.isEmpty
            ? suggestions
            : suggestions.filter { $0.localizedCaseInsensitiveContains(typed) }

        // Nothing to offer once the field already says one of them.
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
