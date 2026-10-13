import SwiftUI

/// The family's question list — the web's `/interview-questions`: reword, reorder, move between sections, set ages, retire and restore, delete what was never asked, merge duplicates, take up new suggested questions, or reset to the built-in list.
/// Edits are a draft until Save, which sends the whole list with the revision it read; someone else saving first is refused rather than overwritten. Reordering is Move up and Move down, the web's own non-drag fallback.
struct InterviewQuestionsView: View {
    @Environment(InterviewService.self) private var service

    @State private var loaded: InterviewQuestionsResponseDTO?
    @State private var draft = QuestionListDraft()
    @State private var saved = QuestionListDraft()
    @State private var deleteIds: [Int] = []
    @State private var loadError: String?
    @State private var error: String?
    @State private var isSaving = false
    @State private var newText: [String: String] = [:]
    @State private var newSection = ""
    @State private var showsRetired = false
    @State private var editingAges: QuestionRow?
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var confirmsReset = false
    @State private var merging: (from: QuestionRow, into: QuestionRow)?

    private var hasChanges: Bool { draft != saved || !deleteIds.isEmpty }

    var body: some View {
        Group {
            if let loaded {
                list(loaded)
            } else if let loadError {
                ContentUnavailableView {
                    Label(Copy.interview.questions.title, systemImage: "wifi.slash")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Copy.interview.questions.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $editingAges) { row in
            AgeRangeForm(row: row) { min, max in
                if let at = draft.index(of: row.key) {
                    draft.rows[at].minAgeYears = min
                    draft.rows[at].maxAgeYears = max
                }
            }
        }
        .alert(Copy.interview.questions.renameSection(renaming ?? ""), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(Copy.interview.questions.sectionPlaceholder, text: $renameText)
            Button(Copy.interview.view.save) {
                if let renaming { draft.rename(section: renaming, to: renameText) }
                renaming = nil
            }
            Button(Copy.interview.view.cancel, role: .cancel) { renaming = nil }
        }
        .confirmationDialog(Copy.interview.questions.confirmReset, isPresented: $confirmsReset, titleVisibility: .visible) {
            Button(Copy.interview.questions.reset) {
                draft.resetToDefaults(loaded?.defaults ?? [])
            }
        }
        .confirmationDialog(
            merging.map { Copy.interview.questions.confirmMerge(from: $0.from.text, into: $0.into.text) } ?? "",
            isPresented: Binding(get: { merging != nil }, set: { if !$0 { merging = nil } }),
            titleVisibility: .visible
        ) {
            Button(Copy.interview.questions.mergeInto) {
                if let merging { Task { await merge(merging.from, into: merging.into) } }
            }
        }
    }

    // MARK: - List

    private func list(_ loaded: InterviewQuestionsResponseDTO) -> some View {
        List {
            Section {
                Text(Copy.interview.questions.intro)
                Text(Copy.interview.questions.placeholders)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }

            suggestedSection(loaded)

            ForEach(draft.sections, id: \.self) { section in
                Section {
                    let rows = draft.active(in: section)
                    if rows.isEmpty {
                        Text(Copy.interview.questions.emptySection)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { row in
                        questionRow(row, loaded: loaded)
                    }
                    HStack {
                        TextField(Copy.interview.questions.addQuestionPlaceholder, text: Binding(
                            get: { newText[section] ?? "" },
                            set: { newText[section] = $0 }
                        ))
                        .onSubmit { addQuestion(to: section) }
                        Button(Copy.interview.questions.add) { addQuestion(to: section) }
                            .disabled((newText[section] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    HStack {
                        Text(section)
                        Spacer()
                        Button(Copy.interview.questions.edit) {
                            renameText = section
                            renaming = section
                        }
                        .font(.caption)
                        .textCase(nil)
                        .accessibilityLabel(Copy.interview.questions.renameSection(section))
                    }
                }
            }

            Section {
                HStack {
                    TextField(Copy.interview.questions.sectionPlaceholder, text: $newSection)
                        .onSubmit(addSection)
                    Button(Copy.interview.questions.add, action: addSection)
                        .disabled(newSection.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text(Copy.interview.questions.addSection)
            }

            let retired = draft.retired
            if !retired.isEmpty {
                Section {
                    DisclosureGroup(Copy.interview.questions.retired(retired.count), isExpanded: $showsRetired) {
                        Text(Copy.interview.questions.retiredHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ForEach(retired) { row in
                            HStack {
                                Text(row.text)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(Copy.interview.questions.restore) { setArchived(row, false) }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(Copy.interview.questions.save) {
                        Task { await save() }
                    }
                    .disabled(!hasChanges)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(Copy.interview.questions.reset, systemImage: "arrow.counterclockwise") {
                    confirmsReset = true
                }
            }
        }
    }

    @ViewBuilder
    private func suggestedSection(_ loaded: InterviewQuestionsResponseDTO) -> some View {
        let have = Set(draft.rows.map(\.defaultKey))
        let suggested = loaded.suggested.filter { !have.contains($0.defaultKey) }
        if !suggested.isEmpty {
            Section {
                ForEach(suggested, id: \.defaultKey) { question in
                    HStack {
                        Text(question.text)
                        Spacer()
                        Button(Copy.interview.questions.add) { draft.adopt([question]) }
                            .buttonStyle(.borderless)
                    }
                }
                Button(Copy.interview.questions.addAll) { draft.adopt(suggested) }
            } header: {
                Text(Copy.interview.questions.suggested(suggested.count))
            }
        }
    }

    private func questionRow(_ row: QuestionRow, loaded: InterviewQuestionsResponseDTO) -> some View {
        let usage = row.questionId > 0 ? loaded.usage(of: row.questionId) : nil
        let canDelete = !(usage?.inUse ?? false)
        let mergeTargets = draft.rows.filter { $0.questionId > 0 && $0.questionId != row.questionId && !$0.archived }
        return VStack(alignment: .leading, spacing: 2) {
            TextField(Copy.interview.questions.questionText, text: Binding(
                get: { draft.rows.first { $0.key == row.key }?.text ?? "" },
                set: { value in if let at = draft.index(of: row.key) { draft.rows[at].text = value } }
            ), axis: .vertical)
            Text("\(Copy.interview.questions.ageRange(min: row.minAgeYears, max: row.maxAgeYears)) · \(Copy.interview.questions.asked(usage?.interviews ?? 0))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing) {
            if canDelete {
                Button(Copy.interview.questions.delete, role: .destructive) { delete(row) }
            }
            Button(Copy.interview.questions.retire) { setArchived(row, true) }
                .tint(.orange)
        }
        .contextMenu {
            Button(Copy.interview.questions.moveUp, systemImage: "arrow.up") { draft.step(row.key, by: -1) }
            Button(Copy.interview.questions.moveDown, systemImage: "arrow.down") { draft.step(row.key, by: 1) }
            Menu(Copy.interview.questions.moveTo) {
                ForEach(draft.sections.filter { $0 != row.section }, id: \.self) { section in
                    Button(section) { draft.move(row.key, toSection: section) }
                }
            }
            Button(Copy.interview.questions.ages, systemImage: "number") { editingAges = row }
            if row.questionId > 0, !mergeTargets.isEmpty {
                Menu(Copy.interview.questions.mergeInto) {
                    if hasChanges {
                        Text(Copy.interview.questions.mergeHint)
                    } else {
                        ForEach(mergeTargets) { target in
                            Button(target.text) { merging = (from: row, into: target) }
                        }
                    }
                }
            }
            Button(Copy.interview.questions.retire, systemImage: "archivebox") { setArchived(row, true) }
            if canDelete {
                Button(Copy.interview.questions.delete, systemImage: "trash", role: .destructive) { delete(row) }
            }
        }
    }

    // MARK: - Editing

    private func addQuestion(to section: String) {
        let text = (newText[section] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft.addRow(text: text, section: section, at: draft.endOf(section))
        newText[section] = ""
    }

    private func addSection() {
        if draft.addSection(newSection) { newSection = "" }
    }

    private func setArchived(_ row: QuestionRow, _ archived: Bool) {
        if let at = draft.index(of: row.key) { draft.rows[at].archived = archived }
    }

    private func delete(_ row: QuestionRow) {
        draft.remove(row.key)
        if row.questionId > 0 { deleteIds.append(row.questionId) }
    }

    // MARK: - Server

    private func adopt(_ response: InterviewQuestionsResponseDTO) {
        loaded = response
        draft = QuestionListDraft(response.questions)
        saved = draft
        deleteIds = []
    }

    private func load() async {
        loadError = nil
        do {
            adopt(try await service.questions())
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        guard let loaded else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            adopt(try await service.saveQuestions(SaveInterviewQuestionsRequestDTO(
                familyId: loaded.familyId,
                revision: loaded.revision,
                questions: draft.questionsForSave,
                deleteIds: deleteIds
            )))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func merge(_ from: QuestionRow, into: QuestionRow) async {
        guard let loaded else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            adopt(try await service.mergeQuestions(MergeInterviewQuestionsRequestDTO(fromId: from.questionId, intoId: into.questionId, revision: loaded.revision)))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A question's usual ages. Zero is no bound: outside them a question starts unchecked at setup, and can still be asked.
private struct AgeRangeForm: View {
    let row: QuestionRow
    let onSave: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minAge: Int
    @State private var maxAge: Int

    init(row: QuestionRow, onSave: @escaping (Int, Int) -> Void) {
        self.row = row
        self.onSave = onSave
        _minAge = State(initialValue: row.minAgeYears)
        _maxAge = State(initialValue: row.maxAgeYears)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(row.text)
                    Stepper("\(Copy.interview.questions.minAge): \(minAge == 0 ? Copy.interview.questions.anyAge : String(minAge))", value: $minAge, in: 0...120)
                    Stepper("\(Copy.interview.questions.maxAge): \(maxAge == 0 ? Copy.interview.questions.anyAge : String(maxAge))", value: $maxAge, in: 0...120)
                } footer: {
                    Text(Copy.interview.questions.ageRange(min: minAge, max: maxAge))
                }
            }
            .navigationTitle(Copy.interview.questions.ages)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.interview.view.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.interview.view.save) {
                        onSave(minAge, maxAge)
                        dismiss()
                    }
                    .disabled(maxAge > 0 && minAge > maxAge)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
