import PhotosUI
import SwiftUI

/// Asking an interview — the web's `/interview/<id>/ask`, built to be read aloud from a phone held in one hand: one question at a time in large type, the answer field focused, earlier answers faded underneath.
/// Return moves on, as Enter does on the web; dictation never types one. Leaving partway is fine: every answer has already saved, and the interview stays in progress until Finish.
struct InterviewAskView: View {
    let interviewId: Int

    @Environment(InterviewService.self) private var service
    @Environment(SyncService.self) private var syncService

    @State private var session: InterviewSession?
    @State private var loadError: String?
    @State private var isFinished = false

    var body: some View {
        Group {
            if isFinished {
                InterviewView(interviewId: interviewId)
            } else if let session {
                InterviewAskContent(session: session) {
                    isFinished = true
                    // The answers are moments: pull, so History and Story have them now rather than at the next sync.
                    Task { await syncService.pullFamilyData() }
                }
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

    /// Always from the server: asking from a stale copy would offer questions as unanswered that were answered on another phone.
    private func load() async {
        guard session == nil else { return }
        loadError = nil
        do {
            let response = try await service.interview(id: interviewId).live()
            session = InterviewSession(response, service: service)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct InterviewAskContent: View {
    @Bindable var session: InterviewSession
    let onFinished: () -> Void

    @FocusState private var answerFocused: Bool
    @State private var showsPrevious = InterviewDrafts().showsPrevious
    @State private var expandsPrevious = false
    @State private var showsJumpList = false
    @State private var followUp: FollowUpDraft?
    @State private var takesPortrait = false
    @State private var portraitItem: PhotosPickerItem?
    @State private var choosesPortrait = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                progress
                status
                if let question = session.current {
                    questionPanel(question)
                } else {
                    finishPanel
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(Copy.interview.ask.allQuestions) { showsJumpList = true }
            }
        }
        .sheet(isPresented: $showsJumpList) {
            jumpList
        }
        .sheet(item: $followUp) { draft in
            FollowUpForm(draft: draft) { text, keep in
                await session.addFollowUp(text, keep: keep)
            }
        }
        .fullScreenCover(isPresented: $takesPortrait) {
            CameraCaptureView { data in
                takesPortrait = false
                if let data { Task { await session.setPortrait(data) } }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $choosesPortrait, selection: $portraitItem, matching: .images)
        .onChange(of: portraitItem) { _, item in
            guard let item else { return }
            portraitItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await session.setPortrait(data)
                }
            }
        }
        // Whatever is in the field when the screen goes is saved, as moving on would.
        .onDisappear { session.go(to: session.index) }
    }

    // MARK: - Pieces

    private var progress: some View {
        let total = session.questions.count
        return VStack(alignment: .leading, spacing: 6) {
            Text(session.isAtEnd ? Copy.interview.ask.done : Copy.interview.ask.progress(session.index + 1, total))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            ProgressView(value: Double(min(session.index, total)), total: Double(max(total, 1)))
                .tint(MilestoneCategory.interview.color)
        }
    }

    @ViewBuilder
    private var status: some View {
        if !session.failed.isEmpty {
            Label(Copy.interview.ask.retrying, systemImage: "arrow.clockwise")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let error = session.error {
            HStack(alignment: .top) {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Spacer()
                Button {
                    session.dismissError()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(Copy.home.dismiss)
            }
        }
    }

    private func questionPanel(_ question: InterviewQuestionDTO) -> some View {
        let previous = session.previous(for: question.id)
        let answer = Binding(
            get: { session.text[question.id] ?? "" },
            set: { value in
                // Return moves on, as Enter does on the web.
                if value.hasSuffix("\n") {
                    session.edit(question.id, to: String(value.dropLast()))
                    session.next()
                } else {
                    session.edit(question.id, to: value)
                }
            }
        )
        return VStack(alignment: .leading, spacing: 16) {
            Text(question.section)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(question.text)
                .font(.largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            TextField(Copy.interview.ask.answerPlaceholder, text: answer, axis: .vertical)
                .font(.title3)
                .lineLimit(2...6)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .focused($answerFocused)
                .submitLabel(.next)
                .id(question.id)

            if session.status(of: question.id) == .skipped, (session.text[question.id] ?? "").isEmpty {
                Text(Copy.interview.ask.wasSkipped)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if showsPrevious, !previous.isEmpty {
                Button {
                    expandsPrevious.toggle()
                } label: {
                    if expandsPrevious {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(previous, id: \.milestoneId) { earlier in
                                (Text("\(Copy.interview.ask.atAge(earlier.ageYears)) ").bold() + Text(earlier.text))
                            }
                        }
                    } else {
                        Text(Interviews.previousLine(previous))
                            .lineLimit(2)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            }

            HStack(spacing: 12) {
                Button(Copy.interview.ask.back) { session.back() }
                    .buttonStyle(.bordered)
                    .disabled(session.index == 0)
                Button(Copy.interview.ask.skip) { session.skip() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(Copy.interview.ask.next) { session.next() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

            VStack(alignment: .leading, spacing: 14) {
                Button(Copy.interview.ask.addFollowUp) {
                    followUp = FollowUpDraft()
                }
                portraitButton
                Toggle(Copy.interview.ask.showPrevious, isOn: $showsPrevious)
                    .onChange(of: showsPrevious) { _, on in InterviewDrafts().showsPrevious = on }
            }
            .font(.subheadline)
            .padding(.top, 8)
        }
        .onAppear { answerFocused = true }
        .onChange(of: question.id) { _, _ in
            expandsPrevious = false
            answerFocused = true
        }
    }

    @ViewBuilder
    private var portraitButton: some View {
        let label = session.isUploading
            ? Copy.interview.ask.uploading
            : session.interview.photoId > 0 ? Copy.interview.ask.retakePortrait : Copy.interview.ask.takePortrait
        if CameraCaptureView.isAvailable {
            Menu(label) {
                Button(Copy.interview.ask.takePortrait, systemImage: "camera") { takesPortrait = true }
                Button(Copy.interview.view.addPortrait, systemImage: "photo.on.rectangle") { choosesPortrait = true }
            }
            .disabled(session.isUploading)
        } else {
            Button(label) { choosesPortrait = true }
                .disabled(session.isUploading)
        }
    }

    private var finishPanel: some View {
        let pending = session.pending
        return VStack(alignment: .leading, spacing: 16) {
            Text(Copy.interview.ask.allDone(session.person.name.firstName))
                .font(.largeTitle.weight(.semibold))
            Text(Copy.interview.ask.answeredCount(session.answers.count, session.questions.count))
            if !pending.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Copy.interview.ask.pendingIntro(pending.count))
                    ForEach(pending) { question in
                        HStack {
                            Text(question.text)
                            Spacer()
                            Button(Copy.interview.ask.askNow) {
                                session.go(to: session.questions.firstIndex { $0.id == question.id } ?? 0)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    Text(Copy.interview.ask.leaveBlank)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Button(Copy.interview.ask.back) { session.go(to: session.questions.count - 1) }
                    .buttonStyle(.bordered)
                Spacer()
                Button(session.isFinishing ? Copy.interview.ask.finishing : Copy.interview.ask.finish) {
                    Task {
                        if await session.finish() { onFinished() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isFinishing)
            }
            .controlSize(.large)
        }
    }

    private var jumpList: some View {
        NavigationStack {
            List {
                ForEach(Array(session.questions.enumerated()), id: \.element.id) { offset, question in
                    let state = session.status(of: question.id)
                    Button {
                        showsJumpList = false
                        session.go(to: offset)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Self.color(state))
                                .frame(width: 10, height: 10)
                                .accessibilityLabel(Self.label(state))
                            Text(question.text)
                                .foregroundStyle(.primary)
                                .fontWeight(offset == session.index ? .semibold : .regular)
                        }
                    }
                }
            }
            .navigationTitle(Copy.interview.ask.allQuestions)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.interview.ask.done) { showsJumpList = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static func color(_ state: Interviews.QuestionStatus) -> Color {
        switch state {
        case .answered: MilestoneCategory.interview.color
        case .skipped: .secondary
        case .pending: Color(.systemGray4)
        }
    }

    private static func label(_ state: Interviews.QuestionStatus) -> String {
        switch state {
        case .answered: Copy.interview.ask.statusAnswered
        case .skipped: Copy.interview.ask.statusSkipped
        case .pending: Copy.interview.ask.statusPending
        }
    }
}

/// A follow-up question being written, as a sheet over the conversation.
private struct FollowUpDraft: Identifiable {
    let id = UUID()
}

private struct FollowUpForm: View {
    let draft: FollowUpDraft
    let onAdd: (String, Bool) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var keep = false
    @State private var isAdding = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(Copy.interview.ask.followUpText, text: $text, axis: .vertical)
                    .focused($focused)
                Picker(Copy.interview.ask.followUpText, selection: $keep) {
                    Text(Copy.interview.ask.justOnce).tag(false)
                    Text(Copy.interview.ask.keepIt).tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .navigationTitle(Copy.interview.ask.followUpText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.interview.ask.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button(Copy.interview.ask.addQuestion) {
                            Task {
                                isAdding = true
                                let added = await onAdd(text, keep)
                                isAdding = false
                                if added { dismiss() }
                            }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
