import SwiftData
import SwiftUI

/// One interview read as a page — the web's `/interview/<id>`: portrait, title, date and age, notes, what changed since the last one, then the answers by section.
/// The interview comes from `GetInterview` (cached, so it reads offline once opened); an answer opens the local moment when the store holds it, where photos and tags are added.
struct InterviewView: View {
    let interviewId: Int

    @Environment(InterviewService.self) private var service
    @Environment(AuthService.self) private var authService
    @Environment(SyncService.self) private var syncService
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var state = ActivityScreenState<GetInterviewResponseDTO>()
    @State private var isEditingDetails = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var openAnswer: Milestone?

    /// This interview's answers in the store, matched to the response's by server id.
    @Query private var localAnswers: [Milestone]

    init(interviewId: Int) {
        self.interviewId = interviewId
        _localAnswers = Query(filter: #Predicate<Milestone> { $0.interviewId == interviewId })
    }

    var body: some View {
        ActivityScreen(state: state, read: { service.interview(id: interviewId) }) { response in
            page(response)
        }
        .navigationTitle(Copy.interview.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let response = state.value, authService.access.canContribute(response.interview.familyId) {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(Copy.interview.view.editDetails, systemImage: "pencil") {
                            isEditingDetails = true
                        }
                        Button(Copy.interview.view.delete, systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .confirmationDialog(Copy.interview.view.confirmDelete, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(Copy.interview.view.delete, role: .destructive) {
                Task { await delete() }
            }
        }
        .sheet(isPresented: $isEditingDetails) {
            if let response = state.value {
                InterviewDetailsForm(response: response) { updated in
                    await saved(updated, previous: response.interview)
                }
            }
        }
        .sheet(item: $openAnswer) { answer in
            MilestoneDetailSheetView(milestone: answer)
        }
    }

    // MARK: - Page

    private func page(_ response: GetInterviewResponseDTO) -> some View {
        let answers = Dictionary(response.answers.map { ($0.questionId, $0) }, uniquingKeysWith: { first, _ in first })
        let changes = Interviews.changesSincePrevious(questions: response.questions, answers: answers, previous: response.previous(for:))
        return VStack(alignment: .leading, spacing: 24) {
            header(response)

            if !response.interview.notes.isEmpty {
                Text(response.interview.notes)
                    .font(.body)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !changes.isEmpty {
                whatChanged(changes)
            }

            ForEach(Interviews.sections(response.questions), id: \.self) { section in
                let asked = response.questions.filter { question in
                    question.section == section
                        && Interviews.status(of: question.id, in: response.interview, answered: Set(answers.keys)) != .pending
                }
                if !asked.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section)
                            .font(.headline)
                        ForEach(asked) { question in
                            answerRow(question, answer: answers[question.id])
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private func header(_ response: GetInterviewResponseDTO) -> some View {
        let interview = response.interview
        let birthday = response.person.birthday
        var meta = [
            interview.date.displayDay().formatted(date: .long, time: .omitted),
            Copy.interview.view.age(Interviews.ageYears(birthday: birthday, at: interview.date)),
        ]
        if interview.isInProgress { meta.append(Copy.interview.view.inProgress) }
        return HStack(alignment: .top, spacing: 16) {
            if interview.photoId > 0 {
                RemotePhotoView(remoteId: interview.photoId, size: .medium)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(Copy.interview.view.portraitOf(response.person.name))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(Interviews.title(interview, personName: response.person.name, birthday: birthday))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(meta.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func whatChanged(_ changes: [Interviews.AnswerChange]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Copy.interview.view.whatChanged)
                .font(.headline)
            ForEach(changes, id: \.questionId) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.question)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    (Text(change.before).strikethrough().foregroundStyle(.secondary) + Text(" → ") + Text(change.after).bold())
                        .font(.subheadline)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MilestoneCategory.interview.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func answerRow(_ question: InterviewQuestionDTO, answer: MilestoneDTO?) -> some View {
        let label = answer.map { $0.context.isEmpty ? question.text : $0.context } ?? question.text
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let answer {
                if let local = localAnswers.first(where: { $0.serverId == answer.id }) {
                    Button {
                        openAnswer = local
                    } label: {
                        Text(local.descriptionText)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    Text(answer.descriptionText)
                }
            } else {
                Text(Copy.interview.view.skipped)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Writes

    private func saved(_ updated: InterviewDTO, previous: InterviewDTO) async {
        await state.reload()
        // A new date rewrites every answer's date on the server; pull so the store follows.
        if updated.date.recordDayKey != previous.date.recordDayKey {
            await syncService.pullFamilyData()
        }
    }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteInterview(id: interviewId)
        } catch {
            errorPresenter.report(error, title: Copy.interview.view.deleteFailed)
            return
        }
        // The server deleted the answers with the interview. Drop them here too rather than showing them until the next pull.
        for answer in localAnswers {
            modelContext.delete(answer)
        }
        try? modelContext.save()
        dismiss()
    }
}

/// Title, date and notes — the web's "Edit details". The whole interview goes back with the change, since `UpdateInterview` assigns every field.
private struct InterviewDetailsForm: View {
    let response: GetInterviewResponseDTO
    let onSaved: (InterviewDTO) async -> Void

    @Environment(InterviewService.self) private var service
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var date: Date
    @State private var notes: String
    @State private var isSaving = false
    @State private var error: String?

    init(response: GetInterviewResponseDTO, onSaved: @escaping (InterviewDTO) async -> Void) {
        self.response = response
        self.onSaved = onSaved
        _title = State(initialValue: response.interview.title)
        _date = State(initialValue: response.interview.date.displayDay())
        _notes = State(initialValue: response.interview.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                Section(Copy.interview.view.title) {
                    TextField(Copy.interview.view.titlePlaceholder, text: $title)
                }
                Section {
                    DatePicker(Copy.interview.view.date, selection: $date, in: ...Date(), displayedComponents: .date)
                }
                Section(Copy.interview.view.notes) {
                    TextField(Copy.interview.view.notesPlaceholder, text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(Copy.interview.view.editDetails)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.interview.view.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(Copy.interview.view.save) {
                            Task { await save() }
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let updated = try await service.updateInterview(UpdateInterviewRequestDTO(
                response.interview,
                date: date.localRecordDay().recordDayKey,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            await onSaved(updated)
            dismiss()
        } catch {
            self.error = InterviewService.isChangedConflict(error) ? InterviewService.changedMessage : Copy.interview.view.saveFailed
        }
    }
}
