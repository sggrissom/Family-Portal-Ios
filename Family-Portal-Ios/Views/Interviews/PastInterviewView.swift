import SwiftUI

/// Typing in a past interview — the web's `/interview/past/<personId>`: when it was (a date, or just an age), then every question on the list with a field beside it. Fill in whatever was asked; blank means not asked. Retired questions wait behind a toggle, since old interviews often asked what the family has since dropped.
/// One save creates the interview and all its answers together, so nothing half-entered is ever left behind.
struct PastInterviewView: View {
    /// The person's server id.
    let personId: Int

    @Environment(InterviewService.self) private var service
    @Environment(SyncService.self) private var syncService

    @State private var setup: GetInterviewSetupResponseDTO?
    @State private var loadError: String?
    @State private var when = WhenEntry(mode: .age)
    @State private var draft = PastInterviewDraft()
    @State private var showsRetired = false
    @State private var title = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saved: Int?

    var body: some View {
        Group {
            if let saved {
                InterviewView(interviewId: saved)
            } else if let setup {
                form(setup)
            } else if let loadError {
                ContentUnavailableView {
                    Label(Copy.interview.title, systemImage: "wifi.slash")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func questions(_ setup: GetInterviewSetupResponseDTO) -> [InterviewQuestionDTO] {
        showsRetired ? setup.questions + setup.retired : setup.questions
    }

    private func form(_ setup: GetInterviewSetupResponseDTO) -> some View {
        let shown = questions(setup)
        return Form {
            Section {
                Text(Copy.interview.past.intro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Section {
                    Text(saveError).foregroundStyle(.red)
                }
            }

            Section(Copy.interview.past.when) {
                WhenControl(entry: $when, birthday: setup.person.birthday)
            }

            ForEach(Interviews.sections(shown), id: \.self) { section in
                Section(section) {
                    ForEach(shown.filter { $0.section == section }, id: \.self) { question in
                        answerField(question)
                    }
                }
            }

            if !setup.retired.isEmpty {
                Section {
                    Toggle(Copy.interview.past.showRetired(setup.retired.count), isOn: $showsRetired)
                }
            }

            Section(Copy.interview.past.notOnList) {
                ForEach($draft.extras) { $extra in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(Copy.interview.past.question, text: $extra.question)
                        TextField(Copy.interview.past.answer, text: $extra.answer)
                        Toggle(Copy.interview.past.addToList, isOn: $extra.keep)
                            .font(.subheadline)
                    }
                }
                .onDelete { draft.extras.remove(atOffsets: $0) }
                Button(Copy.interview.past.addQuestion) {
                    draft.extras.append(PastInterviewDraft.Extra())
                }
            }

            Section(Copy.interview.past.titleAndNotes) {
                TextField(Copy.interview.view.titlePlaceholder, text: $title)
                TextField(Copy.interview.view.notesPlaceholder, text: $notes, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
        .navigationTitle(Copy.interview.past.title(setup.person.name.firstName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(Copy.interview.past.save(draft.filled)) {
                        Task { await save(setup) }
                    }
                    .disabled(draft.filled == 0)
                }
            }
        }
    }

    private func answerField(_ question: InterviewQuestionDTO) -> some View {
        let ref = Interviews.ref(question)
        return VStack(alignment: .leading, spacing: 4) {
            Text(question.text + (question.archived ? " · \(Copy.interview.past.retired)" : ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(Copy.interview.past.answer, text: Binding(
                get: { draft.answers[ref] ?? "" },
                set: { draft.answers[ref] = $0 }
            ))
        }
    }

    // MARK: - Actions

    private func load() async {
        loadError = nil
        do {
            let response = try await service.setup(personId: personId)
            if setup == nil, response.person.birthday.isServerZero {
                when = WhenEntry(mode: .date)
            }
            setup = response
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save(_ setup: GetInterviewSetupResponseDTO) async {
        if let problem = when.problem {
            saveError = problem
            return
        }
        let request = when.request(now: Date())
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let interview = try await service.saveHistorical(SaveHistoricalInterviewRequestDTO(
                personId: personId,
                interview: HistoricalInterviewDTO(
                    inputType: request.inputType,
                    date: request.date ?? "",
                    ageYears: request.ageYears ?? 0,
                    ageMonths: request.ageMonths ?? 0,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    answers: draft.importAnswers(listOrder: setup.questions + setup.retired)
                )
            ))
            saved = interview.id
            // The answers are moments: pull, so History and Story have them now.
            await syncService.pullFamilyData()
        } catch {
            saveError = error.localizedDescription.isEmpty ? Copy.interview.past.saveFailed : error.localizedDescription
        }
    }
}
