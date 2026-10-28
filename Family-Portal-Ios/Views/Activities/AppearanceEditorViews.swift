import SwiftUI
import SwiftData
import OSLog

/// Files a routine at a competition. Two appearances of the same entry at the same event are allowed on purpose, so nothing is filtered out.
struct AddAppearanceView: View {
    let eventId: Int
    let entries: [EntryViewDTO]
    let labels: ActivityLabels
    let onSaved: @MainActor () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var entryId: Int?
    @State private var occurredAt = ActivityDateField()
    @State private var notes = ""
    @State private var matchup = MatchupDraft()
    @State private var saveError: String?
    @State private var isSaving = false

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

                if entries.isEmpty {
                    Section {
                        Text("This season has no \(labels.entryPlural.lowercased()) yet. They're set up on the web.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
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

                AppearanceDateSection(field: $occurredAt, labels: labels)
                AppearanceMatchupSection(draft: $matchup, labels: labels)
                AppearanceNotesSection(notes: $notes)
            }
            .navigationTitle("Add \(labels.appearance)")
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

    private func save() {
        guard let entryId else { return }
        saveError = nil
        isSaving = true

        Task {
            do {
                _ = try await service.createAppearance(
                    eventId: eventId,
                    entryId: entryId,
                    occurredAt: occurredAt.date,
                    notes: notes,
                    matchup: matchup.matchup
                )
                await onSaved()
                dismiss()
            } catch {
                AppLog.activities.error(
                    "Creating an appearance failed: \(String(describing: error), privacy: .public)"
                )
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// Which routine performed at which competition is deliberately not editable: that pair is the record's identity, not a field on it.
struct EditAppearanceView: View {
    let appearance: AppearanceDTO
    let entryName: String
    let labels: ActivityLabels
    let onSaved: @MainActor () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service

    @State private var occurredAt: ActivityDateField
    @State private var notes: String
    @State private var matchup: MatchupDraft
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var isConfirmingDelete = false

    init(
        appearance: AppearanceDTO,
        entryName: String,
        labels: ActivityLabels,
        onSaved: @escaping @MainActor () async -> Void
    ) {
        self.appearance = appearance
        self.entryName = entryName
        self.labels = labels
        self.onSaved = onSaved
        _occurredAt = State(initialValue: ActivityDateField(appearance.occurredAt))
        _notes = State(initialValue: appearance.notes)
        _matchup = State(initialValue: MatchupDraft(Matchup(appearance)))
    }

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

                Section {
                    LabeledContent(labels.entry, value: entryName)
                } footer: {
                    Text("Which \(labels.entry.lowercased()) performed at which \(labels.event.lowercased()) can't be changed. Delete and re-enter it instead — its results go with it.")
                }

                AppearanceDateSection(field: $occurredAt, labels: labels)
                AppearanceMatchupSection(draft: $matchup, labels: labels)
                AppearanceNotesSection(notes: $notes)

                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete \(labels.appearance)", systemImage: "trash")
                    }
                    .disabled(isSaving)
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
                        .disabled(isSaving || matchup.error != nil)
                }
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

    private func save() {
        saveError = nil
        isSaving = true

        Task {
            do {
                // The date is always sent, never omitted: an absent key means "set it to unknown" rather than "leave it alone". The matchup is always sent too, so emptying its fields clears it.
                _ = try await service.updateAppearance(
                    id: appearance.id,
                    occurredAt: occurredAt.date,
                    notes: notes,
                    matchup: matchup.matchup
                )
                await onSaved()
                dismiss()
            } catch {
                AppLog.activities.error(
                    "Updating an appearance failed: \(String(describing: error), privacy: .public)"
                )
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func delete() {
        isSaving = true
        Task {
            do {
                try await service.deleteAppearance(id: appearance.id)
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

// MARK: - Shared form pieces

/// A date that may genuinely not be known. `OccurredAt` has no null on the wire, so the zero time is how "sometime that weekend" is stored.
struct ActivityDateField: Equatable {
    var isSet: Bool
    var day: Date

    init() {
        isSet = false
        day = .now
    }

    init(_ serverValue: Date) {
        if let known = serverValue.serverDate {
            isSet = true
            day = known.displayDay()
        } else {
            isSet = false
            day = .now
        }
    }

    /// What the write sends. `nil` clears the date, which is what the toggle being off means.
    var date: Date? { isSet ? day.localRecordDay() : nil }
}

struct AppearanceDateSection: View {
    @Binding var field: ActivityDateField
    let labels: ActivityLabels

    var body: some View {
        Section {
            Toggle("Know the day?", isOn: $field.isSet)
            if field.isSet {
                DatePicker("Day", selection: $field.day, displayedComponents: .date)
            }
        } footer: {
            if !field.isSet {
                Text("Left off, this \(labels.appearance.lowercased()) sorts by the \(labels.event.lowercased())'s own dates — which is usually what you want mid-weekend.")
            }
        }
    }
}

/// Round, opponent, outcome and an optional score, for a battle bracket or a tournament game. Open from the start for a sport or a matchup already recorded; otherwise behind a button, since most performances have no opponent. Two scores fill in the outcome they imply until one is picked by hand.
struct AppearanceMatchupSection: View {
    @Binding var draft: MatchupDraft
    let labels: ActivityLabels

    @State private var isOpen: Bool
    @State private var outcomeChosen: Bool

    init(draft: Binding<MatchupDraft>, labels: ActivityLabels) {
        _draft = draft
        self.labels = labels
        _isOpen = State(initialValue: labels == .sport || draft.wrappedValue.matchup.isRecorded)
        _outcomeChosen = State(initialValue: !draft.wrappedValue.outcome.isEmpty)
    }

    private var outcome: Binding<String> {
        Binding {
            draft.outcome
        } set: { value in
            draft.outcome = value
            outcomeChosen = !value.isEmpty
        }
    }

    var body: some View {
        if isOpen {
            Section {
                HStack {
                    TextField("Round", text: $draft.round)
                    Menu {
                        ForEach(Matchups.commonRounds, id: \.self) { round in
                            Button(round) { draft.round = round }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("Common rounds")
                }
                TextField("Against", text: $draft.opponent)
                Picker("Outcome", selection: outcome) {
                    ForEach(MatchupOutcome.all, id: \.self) { option in
                        Text(MatchupOutcome.optionLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Score")
                    Spacer()
                    TextField("Us", text: $draft.scoreFor)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 64)
                        .accessibilityLabel("Our score")
                    Text("–")
                    TextField("Them", text: $draft.scoreAgainst)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 64)
                        .accessibilityLabel("Their score")
                }
            } header: {
                Text("Head-to-head")
            } footer: {
                if let error = draft.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Leave the score empty when none was kept.")
                }
            }
            .onChange(of: draft.scoreFor) { fillOutcome() }
            .onChange(of: draft.scoreAgainst) { fillOutcome() }
        } else {
            Section {
                Button {
                    isOpen = true
                } label: {
                    Label("Head-to-head", systemImage: "plus")
                }
            } footer: {
                Text("For a bracket or a game: the round, who it was against, and whether the \(labels.entry.lowercased()) won.")
            }
        }
    }

    private func fillOutcome() {
        guard !outcomeChosen else { return }
        draft.outcome = draft.outcomeFromScore
    }
}

struct AppearanceNotesSection: View {
    @Binding var notes: String

    var body: some View {
        Section("Notes") {
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .onChange(of: notes) { _, new in
                    // The server truncates past this rather than refusing.
                    if new.count > ActivityFieldLimit.notes.characters {
                        notes = String(new.prefix(ActivityFieldLimit.notes.characters))
                    }
                }
        }
    }
}
