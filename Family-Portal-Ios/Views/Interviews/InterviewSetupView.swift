import SwiftUI

/// Setting up an interview — the web's `/interview/new/<personId>`: the date, which questions to ask this year, and whether to see earlier answers while asking.
/// Questions outside the child's usual ages start unchecked but can still be ticked. An interview already in progress is offered instead of a second one, which the server would refuse.
struct InterviewSetupView: View {
    /// The person's server id.
    let personId: Int

    @Environment(InterviewService.self) private var service

    @State private var setup: GetInterviewSetupResponseDTO?
    @State private var loadError: String?
    @State private var date = Date()
    @State private var checked: Set<String> = []
    @State private var oneOffs: [String] = []
    @State private var newOneOff = ""
    @State private var showsPrevious = InterviewDrafts().showsPrevious
    @State private var isStarting = false
    @State private var startError: String?
    /// The interview to ask: the one just started, or the one in progress.
    @State private var asking: Int?

    var body: some View {
        Group {
            if let setup {
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
        .navigationTitle(setup.map { Copy.interview.setup.title($0.person.name.firstName) } ?? Copy.interview.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $asking) { id in
            InterviewAskView(interviewId: id)
        }
        .task { await load() }
    }

    private func form(_ setup: GetInterviewSetupResponseDTO) -> some View {
        let name = setup.person.name.firstName
        let age = Interviews.ageYears(birthday: setup.person.birthday, at: date.localRecordDay())
        let count = setup.questions.filter { checked.contains(Interviews.ref($0)) }.count + oneOffs.count
        let hasInProgress = setup.inProgress.id > 0
        return Form {
            if hasInProgress {
                Section {
                    Text(Copy.interview.setup.inProgress(name, answered: setup.answered, total: setup.inProgress.questionIds.count))
                    Button(Copy.interview.setup.continue) {
                        asking = setup.inProgress.id
                    }
                    .bold()
                }
            }

            if let startError {
                Section {
                    Text(startError).foregroundStyle(.red)
                }
            }

            Section {
                DatePicker(Copy.interview.setup.date, selection: $date, in: ...Date(), displayedComponents: .date)
                Toggle(Copy.interview.setup.showPrevious, isOn: $showsPrevious)
            } footer: {
                Text(Copy.interview.setup.age(name, age))
            }

            ForEach(Interviews.sections(setup.questions), id: \.self) { section in
                let inSection = setup.questions.filter { $0.section == section }
                let allOn = inSection.allSatisfy { checked.contains(Interviews.ref($0)) }
                Section {
                    ForEach(inSection, id: \.self) { question in
                        questionRow(question, age: age)
                    }
                } header: {
                    HStack {
                        Text(section)
                        Spacer()
                        Button(allOn ? Copy.interview.setup.none : Copy.interview.setup.all) {
                            for question in inSection {
                                if allOn {
                                    checked.remove(Interviews.ref(question))
                                } else {
                                    checked.insert(Interviews.ref(question))
                                }
                            }
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }

            Section(Copy.interview.setup.justThisTime) {
                ForEach(Array(oneOffs.enumerated()), id: \.offset) { _, text in
                    Text(text)
                }
                .onDelete { oneOffs.remove(atOffsets: $0) }
                HStack {
                    TextField(Copy.interview.setup.addOneOff, text: $newOneOff)
                        .onSubmit(addOneOff)
                    Button(Copy.interview.setup.add, action: addOneOff)
                        .disabled(newOneOff.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isStarting {
                    ProgressView()
                } else {
                    Button(Copy.interview.setup.start(count)) {
                        Task { await start(setup) }
                    }
                    .disabled(count == 0 || hasInProgress)
                }
            }
        }
        .onChange(of: date) { _, _ in checkForAge(setup) }
        .onChange(of: showsPrevious) { _, on in InterviewDrafts().showsPrevious = on }
    }

    private func questionRow(_ question: InterviewQuestionDTO, age: Int) -> some View {
        let ref = Interviews.ref(question)
        let isOn = checked.contains(ref)
        return Button {
            if isOn { checked.remove(ref) } else { checked.insert(ref) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(question.text)
                        .foregroundStyle(.primary)
                    if !Interviews.fits(question, age: age) {
                        Text(Copy.interview.setup.outsideAges)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Actions

    private func load() async {
        loadError = nil
        do {
            let response = try await service.setup(personId: personId)
            setup = response
            checkForAge(response)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Checks the questions that suit the child's age on the chosen day — redone whenever the date moves, as the web does.
    private func checkForAge(_ setup: GetInterviewSetupResponseDTO) {
        let age = Interviews.ageYears(birthday: setup.person.birthday, at: date.localRecordDay())
        checked = Set(setup.questions.filter { Interviews.fits($0, age: age) }.map(Interviews.ref))
    }

    private func addOneOff() {
        let text = newOneOff.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        oneOffs.append(text)
        newOneOff = ""
    }

    private func start(_ setup: GetInterviewSetupResponseDTO) async {
        let chosen = setup.questions.filter { checked.contains(Interviews.ref($0)) }
        isStarting = true
        startError = nil
        defer { isStarting = false }
        do {
            let interview = try await service.start(StartInterviewRequestDTO(
                personId: personId,
                date: date.localRecordDay().recordDayKey,
                questionIds: chosen.filter { $0.id > 0 }.map(\.id),
                defaultKeys: chosen.filter { $0.id == 0 }.map(\.defaultKey),
                oneOffQuestions: oneOffs
            ))
            asking = interview.id
            // Back from the interview finds it in progress rather than offering a second start.
            await load()
        } catch {
            startError = error.localizedDescription
        }
    }
}
