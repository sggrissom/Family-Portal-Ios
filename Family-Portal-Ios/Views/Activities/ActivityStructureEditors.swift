import SwiftUI
import SwiftData
import OSLog

// The annual setup half: the program, its seasons, the competitions in a season, the routines in a season, and who is in a routine.

// MARK: - Shared pieces

struct ActivityFormError: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
        }
    }
}

struct ActivityDateRangeSection: View {
    @Binding var start: ActivityDateField
    @Binding var end: ActivityDateField
    let startLabel: String
    let endLabel: String

    var body: some View {
        Section("Dates") {
            Toggle(startLabel, isOn: $start.isSet)
            if start.isSet {
                DatePicker(startLabel, selection: $start.day, displayedComponents: .date)
                    .labelsHidden()
            }

            Toggle(endLabel, isOn: $end.isSet)
            if end.isSet {
                DatePicker(endLabel, selection: $end.day, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }
}

struct ActivityDeleteSection: View {
    let title: String
    let confirmation: String
    let cascade: String
    let isBusy: Bool
    let delete: @MainActor () -> Void

    @State private var isConfirming = false

    var body: some View {
        Section {
            Button(role: .destructive) {
                isConfirming = true
            } label: {
                Label(title, systemImage: "trash")
            }
            .disabled(isBusy)
        }
        .confirmationDialog(confirmation, isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cascade)
        }
    }
}

struct ActivityTextField: View {
    let prompt: String
    @Binding var text: String
    var suggestions: [String] = []
    var limit: Int = ActivityFieldLimit.label.characters

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(prompt, text: Binding(
                get: { text },
                // Capped as typed, because the server truncates past this rather than refusing. `prefix` rather than a trim, which would eat the space just pressed.
                set: { text = String($0.prefix(limit)) }
            ))
            VocabularySuggestions(suggestions: suggestions, text: $text)
        }
    }
}

// MARK: - Activity

struct ActivityEditorView: View {
    let existing: ActivityDTO?
    let onSaved: @MainActor () async -> Void
    let onDeleted: (@MainActor () async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service

    @State private var name: String
    @State private var kind: String
    @State private var saveError: String?
    @State private var isSaving = false

    init(
        existing: ActivityDTO? = nil,
        onSaved: @escaping @MainActor () async -> Void,
        onDeleted: (@MainActor () async -> Void)? = nil
    ) {
        self.existing = existing
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? ActivityKind.dance)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                ActivityFormError(message: saveError)

                Section {
                    ActivityTextField(prompt: "Name", text: $name, limit: ActivityFieldLimit.name.characters)
                    Picker("Kind", selection: $kind) {
                        ForEach(ActivityKind.all, id: \.self) { kind in
                            Text(ActivityKind.displayName(kind)).tag(kind)
                        }
                    }
                } footer: {
                    Text("The kind only chooses what things are called — \(ActivityLabels.forKind(kind).entryPlural.lowercased()) and \(ActivityLabels.forKind(kind).eventPlural.lowercased()). Everything else works the same either way.")
                }

                if let existing {
                    ActivityDeleteSection(
                        title: "Delete Activity",
                        confirmation: "Delete \(existing.name)?",
                        cascade: "Every season under it goes too — all its competitions, routines, performances and results. This can't be undone.",
                        isBusy: isSaving,
                        delete: { delete(existing.id) }
                    )
                }
            }
            .navigationTitle(existing == nil ? "New Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { activityFormToolbar(isValid: isValid, isSaving: isSaving, dismiss: dismiss, save: save) }
        }
    }

    private func save() {
        perform {
            if let existing {
                _ = try await service.updateActivity(id: existing.id, name: name, kind: kind)
            } else {
                _ = try await service.createActivity(name: name, kind: kind)
            }
        }
    }

    private func delete(_ id: Int) {
        perform(isDelete: true) { try await service.deleteActivity(id: id) }
    }

    private func perform(isDelete: Bool = false, _ work: @escaping @MainActor () async throws -> Void) {
        saveError = nil
        isSaving = true
        Task {
            do {
                try await work()
                if isDelete, let onDeleted {
                    await onDeleted()
                } else {
                    await onSaved()
                }
                dismiss()
            } catch {
                AppLog.activities.error("Activity write failed: \(String(describing: error), privacy: .public)")
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Season

struct SeasonEditorView: View {
    let activityId: Int
    let existing: SeasonDTO?
    let onSaved: @MainActor () async -> Void
    let onDeleted: (@MainActor () async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service

    @State private var name: String
    @State private var start: ActivityDateField
    @State private var end: ActivityDateField
    @State private var notes: String
    @State private var saveError: String?
    @State private var isSaving = false

    init(
        activityId: Int,
        existing: SeasonDTO? = nil,
        onSaved: @escaping @MainActor () async -> Void,
        onDeleted: (@MainActor () async -> Void)? = nil
    ) {
        self.activityId = activityId
        self.existing = existing
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _name = State(initialValue: existing?.name ?? "")
        _start = State(initialValue: existing.map { ActivityDateField($0.startDate) } ?? ActivityDateField())
        _end = State(initialValue: existing.map { ActivityDateField($0.endDate) } ?? ActivityDateField())
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                ActivityFormError(message: saveError)

                Section {
                    ActivityTextField(prompt: "Name", text: $name, limit: ActivityFieldLimit.name.characters)
                } footer: {
                    Text("Something like “2025–26 Competition Season”.")
                }

                ActivityDateRangeSection(
                    start: $start,
                    end: $end,
                    startLabel: "Starts",
                    endLabel: "Ends"
                )

                AppearanceNotesSection(notes: $notes)

                if let existing {
                    ActivityDeleteSection(
                        title: "Delete Season",
                        confirmation: "Delete \(existing.name)?",
                        cascade: "Every competition and routine in this season goes with it, and every performance and result under those. This can't be undone.",
                        isBusy: isSaving,
                        delete: { delete(existing.id) }
                    )
                }
            }
            .navigationTitle(existing == nil ? "New Season" : "Edit Season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { activityFormToolbar(isValid: isValid, isSaving: isSaving, dismiss: dismiss, save: save) }
        }
    }

    private func save() {
        perform {
            // Both dates always go, set or not: an omitted key on `UpdateSeason` clears the date rather than leaving it alone.
            if let existing {
                _ = try await service.updateSeason(
                    id: existing.id, name: name,
                    startDate: start.date, endDate: end.date, notes: notes
                )
            } else {
                _ = try await service.createSeason(
                    activityId: activityId, name: name,
                    startDate: start.date, endDate: end.date, notes: notes
                )
            }
        }
    }

    private func delete(_ id: Int) {
        perform(isDelete: true) { try await service.deleteSeason(id: id) }
    }

    private func perform(isDelete: Bool = false, _ work: @escaping @MainActor () async throws -> Void) {
        saveError = nil
        isSaving = true
        Task {
            do {
                try await work()
                if isDelete, let onDeleted {
                    await onDeleted()
                } else {
                    await onSaved()
                }
                dismiss()
            } catch {
                AppLog.activities.error("Season write failed: \(String(describing: error), privacy: .public)")
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Competition

struct CompetitionEditorView: View {
    let seasonId: Int
    let existing: ActivityEventDTO?
    let labels: ActivityLabels
    let hostSuggestions: [String]
    let onSaved: @MainActor () async -> Void
    let onDeleted: (@MainActor () async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service

    @State private var name: String
    @State private var host: String
    @State private var location: String
    @State private var start: ActivityDateField
    @State private var end: ActivityDateField
    @State private var notes: String
    @State private var saveError: String?
    @State private var isSaving = false

    init(
        seasonId: Int,
        existing: ActivityEventDTO? = nil,
        labels: ActivityLabels,
        hostSuggestions: [String] = [],
        onSaved: @escaping @MainActor () async -> Void,
        onDeleted: (@MainActor () async -> Void)? = nil
    ) {
        self.seasonId = seasonId
        self.existing = existing
        self.labels = labels
        self.hostSuggestions = hostSuggestions
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _name = State(initialValue: existing?.name ?? "")
        _host = State(initialValue: existing?.host ?? "")
        _location = State(initialValue: existing?.location ?? "")
        _start = State(initialValue: existing.map { ActivityDateField($0.startDate) } ?? ActivityDateField())
        _end = State(initialValue: existing.map { ActivityDateField($0.endDate) } ?? ActivityDateField())
        _notes = State(initialValue: existing?.notes ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                ActivityFormError(message: saveError)

                Section {
                    ActivityTextField(prompt: "Name", text: $name, limit: ActivityFieldLimit.name.characters)
                    ActivityTextField(prompt: "Host", text: $host, suggestions: hostSuggestions)
                    ActivityTextField(prompt: "Location", text: $location, limit: ActivityFieldLimit.name.characters)
                }

                ActivityDateRangeSection(
                    start: $start,
                    end: $end,
                    startLabel: "Starts",
                    endLabel: "Ends"
                )

                AppearanceNotesSection(notes: $notes)

                if let existing {
                    ActivityDeleteSection(
                        title: "Delete \(labels.event)",
                        confirmation: "Delete \(existing.name)?",
                        cascade: "Every \(labels.appearance.lowercased()) at this \(labels.event.lowercased()) goes with it, along with their results and photos. This can't be undone.",
                        isBusy: isSaving,
                        delete: { delete(existing.id) }
                    )
                }
            }
            .navigationTitle(existing == nil ? "New \(labels.event)" : "Edit \(labels.event)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { activityFormToolbar(isValid: isValid, isSaving: isSaving, dismiss: dismiss, save: save) }
        }
    }

    private func save() {
        perform {
            if let existing {
                _ = try await service.updateEvent(
                    id: existing.id, name: name, host: host, location: location,
                    startDate: start.date, endDate: end.date, notes: notes
                )
            } else {
                _ = try await service.createEvent(
                    seasonId: seasonId, name: name, host: host, location: location,
                    startDate: start.date, endDate: end.date, notes: notes
                )
            }
        }
    }

    private func delete(_ id: Int) {
        perform(isDelete: true) { try await service.deleteEvent(id: id) }
    }

    private func perform(isDelete: Bool = false, _ work: @escaping @MainActor () async throws -> Void) {
        saveError = nil
        isSaving = true
        Task {
            do {
                try await work()
                if isDelete, let onDeleted {
                    await onDeleted()
                } else {
                    await onSaved()
                }
                dismiss()
            } catch {
                AppLog.activities.error("Competition write failed: \(String(describing: error), privacy: .public)")
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Routine

struct RoutineEditorView: View {
    let seasonId: Int
    let existing: EntryViewDTO?
    let labels: ActivityLabels
    let vocabulary: ListActivityVocabularyResponseDTO?
    let onSaved: @MainActor () async -> Void
    let onDeleted: (@MainActor () async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var name: String
    @State private var format: String
    @State private var style: String
    @State private var division: String
    @State private var level: String
    @State private var notes: String
    @State private var roster: [Int]
    @State private var saveError: String?
    @State private var isSaving = false

    init(
        seasonId: Int,
        existing: EntryViewDTO? = nil,
        labels: ActivityLabels,
        vocabulary: ListActivityVocabularyResponseDTO? = nil,
        onSaved: @escaping @MainActor () async -> Void,
        onDeleted: (@MainActor () async -> Void)? = nil
    ) {
        self.seasonId = seasonId
        self.existing = existing
        self.labels = labels
        self.vocabulary = vocabulary
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _name = State(initialValue: existing?.entry.name ?? "")
        _format = State(initialValue: existing?.entry.format ?? "")
        _style = State(initialValue: existing?.entry.style ?? "")
        _division = State(initialValue: existing?.entry.division ?? "")
        _level = State(initialValue: existing?.entry.level ?? "")
        _notes = State(initialValue: existing?.entry.notes ?? "")
        _roster = State(initialValue: existing?.personIds ?? [])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                ActivityFormError(message: saveError)

                Section {
                    ActivityTextField(prompt: "Name", text: $name, limit: ActivityFieldLimit.name.characters)
                    ActivityTextField(prompt: "Format", text: $format, suggestions: vocabulary?.formats ?? [])
                    ActivityTextField(prompt: "Style", text: $style, suggestions: vocabulary?.styles ?? [])
                    ActivityTextField(prompt: "Division", text: $division, suggestions: vocabulary?.divisions ?? [])
                    ActivityTextField(prompt: "Level", text: $level, suggestions: vocabulary?.levels ?? [])
                }

                Section(labels.roster) {
                    NavigationLink {
                        RosterPickerView(selection: $roster, labels: labels)
                    } label: {
                        HStack {
                            Text("Who's in it")
                            Spacer()
                            Text(ActivityPeople(people).rosterText(roster) ?? "Nobody yet")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                AppearanceNotesSection(notes: $notes)

                if let existing {
                    ActivityDeleteSection(
                        title: "Delete \(labels.entry)",
                        confirmation: "Delete \(existing.entry.name)?",
                        cascade: "Every \(labels.appearance.lowercased()) by this \(labels.entry.lowercased()) goes with it, along with their results and photos. This can't be undone.",
                        isBusy: isSaving,
                        delete: { delete(existing.entry.id) }
                    )
                }
            }
            .navigationTitle(existing == nil ? "New \(labels.entry)" : "Edit \(labels.entry)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { activityFormToolbar(isValid: isValid, isSaving: isSaving, dismiss: dismiss, save: save) }
        }
    }

    private func save() {
        perform {
            if let existing {
                _ = try await service.updateEntry(
                    id: existing.entry.id, name: name, format: format,
                    style: style, division: division, level: level, notes: notes
                )
                // Two calls on edit because the backend splits them. The roster goes second: if the details fail, nothing has changed at all.
                if roster != existing.personIds {
                    _ = try await service.setEntryRoster(entryId: existing.entry.id, personIds: roster)
                }
            } else {
                _ = try await service.createEntry(
                    seasonId: seasonId, name: name, format: format,
                    style: style, division: division, level: level,
                    notes: notes, personIds: roster
                )
            }
        }
    }

    private func delete(_ id: Int) {
        perform(isDelete: true) { try await service.deleteEntry(id: id) }
    }

    private func perform(isDelete: Bool = false, _ work: @escaping @MainActor () async throws -> Void) {
        saveError = nil
        isSaving = true
        Task {
            do {
                try await work()
                if isDelete, let onDeleted {
                    await onDeleted()
                } else {
                    await onSaved()
                }
                dismiss()
            } catch {
                AppLog.activities.error("Routine write failed: \(String(describing: error), privacy: .public)")
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// Who is on a routine. Written in *server* ids, and `setEntryRosterTx` refuses anyone not already on the owning family's roster.
struct RosterPickerView: View {
    @Binding var selection: [Int]
    let labels: ActivityLabels

    @Query(sort: \Person.name) private var people: [Person]

    private struct Candidate: Identifiable {
        let remoteId: Int
        let person: Person
        var id: Int { remoteId }
    }

    private var candidates: [Candidate] {
        people.compactMap { person in
            person.remoteId.flatMap(Int.init).map { Candidate(remoteId: $0, person: person) }
        }
    }

    var body: some View {
        List {
            if candidates.isEmpty {
                Text("Nobody on this device has synced yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(candidates) { candidate in
                    Button {
                        toggle(candidate.remoteId)
                    } label: {
                        HStack {
                            PersonAvatarView(person: candidate.person, size: 32)
                            Text(candidate.person.name)
                            Spacer()
                            if selection.contains(candidate.remoteId) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection.contains(candidate.remoteId) ? .isSelected : [])
                }
            }

            // A roster can hold a child from a linked household this device never pulled; dropping ids nothing resolves would take that child off the routine.
            let unresolved = selection.filter { id in !candidates.contains { $0.remoteId == id } }
            if !unresolved.isEmpty {
                Section {
                    Text("\(unresolved.count) more \(unresolved.count == 1 ? "person" : "people") on this \(labels.entry.lowercased()) aren't on this device. They stay on it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(labels.roster)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ remoteId: Int) {
        if let index = selection.firstIndex(of: remoteId) {
            selection.remove(at: index)
        } else {
            selection.append(remoteId)
        }
    }
}

// MARK: - Toolbar

@MainActor
@ToolbarContentBuilder
func activityFormToolbar(
    isValid: Bool,
    isSaving: Bool,
    dismiss: DismissAction,
    save: @escaping () -> Void
) -> some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
    }
    ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save)
            .disabled(!isValid || isSaving)
    }
}
