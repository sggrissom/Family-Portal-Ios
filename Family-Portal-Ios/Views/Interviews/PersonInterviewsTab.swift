import SwiftData
import SwiftUI

/// A person's Interviews tab — the web's `?tab=interviews`: start a new interview or pick one up, the interviews so far, then how the answers changed, as **Questions** (one card per question, its answers by age) or **Years** (a grid of questions by year).
/// Questions comes first here, where the web starts on Years: a grid of years does not fit a phone, which is why the web switches to the cards on narrow screens too.
struct PersonInterviewsTab: View {
    /// The person's server id.
    let personId: Int
    let personName: String
    let canContribute: Bool

    enum Mode: String, CaseIterable, Identifiable {
        case questions, years

        var id: String { rawValue }
        var label: String { self == .questions ? Copy.interview.tab.questions : Copy.interview.tab.years }
    }

    @Environment(InterviewService.self) private var service
    @State private var state = ActivityScreenState<GetPersonInterviewsResponseDTO>()
    @State private var mode = Mode.questions
    @State private var sort = InterviewTimelineSort.list
    @State private var query = ""
    @State private var openAnswer: Milestone?

    /// Every answer in the store, so a tapped one opens as the moment it is.
    @Query(filter: #Predicate<Milestone> { $0.interviewId > 0 }) private var localAnswers: [Milestone]

    var body: some View {
        ActivityScreen(state: state, read: { service.personInterviews(personId: personId) }) { bundle in
            content(bundle)
                .padding(.horizontal)
        }
        .sheet(item: $openAnswer) { MilestoneDetailSheetView(milestone: $0) }
    }

    private func content(_ bundle: GetPersonInterviewsResponseDTO) -> some View {
        let inProgress = bundle.interviews.last { $0.isInProgress }
        return VStack(alignment: .leading, spacing: 16) {
            if canContribute {
                startButton(bundle, inProgress: inProgress)
            }

            if bundle.interviews.isEmpty {
                Text(Copy.interview.tab.empty(personName.firstName))
                    .foregroundStyle(.secondary)
            } else {
                interviewList(bundle)

                NavigationLink {
                    InterviewCompareView(questionId: 0)
                } label: {
                    Label(Copy.interview.compare.link, systemImage: "person.2")
                        .font(.subheadline)
                }

                Picker(Copy.interview.tab.questions, selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .questions: questionsView(bundle)
                case .years: yearsView(bundle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func startButton(_ bundle: GetPersonInterviewsResponseDTO, inProgress: InterviewDTO?) -> some View {
        if let inProgress {
            NavigationLink {
                InterviewAskView(interviewId: inProgress.id)
            } label: {
                Label(Copy.interview.tab.continue, systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            NavigationLink {
                InterviewSetupView(personId: personId)
            } label: {
                Label(bundle.interviews.isEmpty ? Copy.interview.tab.startFirst : Copy.interview.tab.start, systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Newest first, one line each — the web's interview list above the views.
    private func interviewList(_ bundle: GetPersonInterviewsResponseDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(bundle.interviews.reversed())) { interview in
                NavigationLink {
                    InterviewView(interviewId: interview.id)
                } label: {
                    HStack(spacing: 12) {
                        if interview.photoId > 0 {
                            RemotePhotoView(remoteId: interview.photoId, size: .thumb)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            Image(systemName: MilestoneCategory.interview.icon)
                                .foregroundStyle(MilestoneCategory.interview.color)
                                .frame(width: 40, height: 40)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Interviews.title(interview, personName: bundle.person.name, birthday: bundle.person.birthday))
                                .foregroundStyle(.primary)
                            Text(Interviews.columnLabel(interview, birthday: bundle.person.birthday)
                                + (interview.isInProgress ? " · \(Copy.interview.tab.inProgress)" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Questions

    private func questionsView(_ bundle: GetPersonInterviewsResponseDTO) -> some View {
        let timelines = Interviews.sorted(Interviews.filtered(Interviews.timelines(bundle), query: query), by: sort)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(Copy.interview.tab.filter, text: $query)
                    .textFieldStyle(.roundedBorder)
                Menu {
                    Picker(Copy.interview.tab.sortLabel, selection: $sort) {
                        ForEach(InterviewTimelineSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel(Copy.interview.tab.sortLabel)
            }
            if timelines.isEmpty {
                Text(Copy.interview.tab.noMatches)
                    .foregroundStyle(.secondary)
            }
            ForEach(timelines) { timeline in
                questionCard(timeline)
            }
        }
    }

    private func questionCard(_ timeline: InterviewTimeline) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                InterviewCompareView(questionId: timeline.question.id)
            } label: {
                Text(timeline.label)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
            }
            ForEach(Array(timeline.points.enumerated()), id: \.element.answer.id) { offset, point in
                let same = offset > 0
                    && Interviews.normalizeAnswer(timeline.points[offset - 1].answer.descriptionText) == Interviews.normalizeAnswer(point.answer.descriptionText)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(point.age)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    answerButton(point.answer)
                        .opacity(same ? 0.55 : 1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func answerButton(_ answer: MilestoneDTO) -> some View {
        if let local = localAnswers.first(where: { $0.serverId == answer.id }) {
            Button(answer.descriptionText) { openAnswer = local }
                .multilineTextAlignment(.leading)
        } else {
            Text(answer.descriptionText)
        }
    }

    // MARK: - Years

    private static let questionWidth: CGFloat = 140
    private static let cellWidth: CGFloat = 120

    /// The grid scrolls sideways as a whole. A new answer is drawn bold in the interview colour; one the same as the year before is faded, so "pizza, pizza, pizza, tacos" reads at a glance.
    private func yearsView(_ bundle: GetPersonInterviewsResponseDTO) -> some View {
        let sections = Interviews.grid(bundle)
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Color.clear.frame(width: Self.questionWidth, height: 1)
                        ForEach(bundle.interviews) { interview in
                            NavigationLink {
                                InterviewView(interviewId: interview.id)
                            } label: {
                                Text(Interviews.columnLabel(interview, birthday: bundle.person.birthday))
                                    .font(.caption.weight(.semibold))
                                    .frame(width: Self.cellWidth, alignment: .leading)
                            }
                        }
                    }
                    ForEach(sections) { section in
                        GridRow {
                            Text(section.name)
                                .font(.subheadline.weight(.semibold))
                                .gridCellColumns(bundle.interviews.count + 1)
                                .padding(.top, 6)
                        }
                        ForEach(section.rows) { row in
                            GridRow {
                                Text(row.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: Self.questionWidth, alignment: .leading)
                                ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                                    gridCell(cell)
                                        .frame(width: Self.cellWidth, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Text("\(Copy.interview.tab.legendChanged) · \(Copy.interview.tab.legendSame)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func gridCell(_ cell: InterviewGridCell) -> some View {
        if let answer = cell.answer {
            answerButton(answer)
                .font(.subheadline.weight(cell.trend == .changed ? .semibold : .regular))
                .foregroundStyle(cell.trend == .changed ? MilestoneCategory.interview.color : .primary)
                .opacity(cell.trend == .same ? 0.55 : 1)
        } else if cell.skipped {
            Text("–")
                .foregroundStyle(.tertiary)
                .accessibilityLabel(Copy.interview.tab.skipped)
        } else {
            Color.clear.frame(height: 1)
        }
    }
}
