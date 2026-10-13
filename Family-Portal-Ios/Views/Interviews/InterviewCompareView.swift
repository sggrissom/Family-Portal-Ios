import SwiftUI

/// Compare at the same age — the web's `/interview/compare`: one question, everyone's answers, lined up by how old they were. A parent's own childhood interview lines up too, since parents are people.
struct InterviewCompareView: View {
    /// 0 lets the server choose the first question anyone has answered.
    @State var questionId: Int

    @Environment(InterviewService.self) private var service
    @State private var state = ActivityScreenState<CompareInterviewAnswersResponseDTO>()
    /// People unticked in "Who to compare", by server id.
    @State private var hidden: Set<Int> = []

    var body: some View {
        ActivityScreen(state: state, read: { service.compare(questionId: questionId) }) { response in
            content(response)
                .padding(.horizontal)
        }
        .id(questionId)
        .navigationTitle(Copy.interview.compare.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ response: CompareInterviewAnswersResponseDTO) -> some View {
        let questions = response.questions.filter { !$0.oneOff }
        let groups = Interviews.byAge(response.rows.filter { !hidden.contains($0.person.id) })
        return VStack(alignment: .leading, spacing: 16) {
            Text(Copy.interview.compare.intro)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if questions.isEmpty {
                Text(Copy.interview.compare.empty)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    ForEach(Interviews.sections(questions), id: \.self) { section in
                        Section(section) {
                            ForEach(questions.filter { $0.section == section }) { question in
                                Button(question.text) {
                                    hidden = []
                                    questionId = question.id
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(response.question.text)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                }
                .accessibilityLabel("\(Copy.interview.compare.question): \(response.question.text)")

                if response.rows.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(response.rows) { row in
                                let on = !hidden.contains(row.person.id)
                                Button {
                                    if on { hidden.insert(row.person.id) } else { hidden.remove(row.person.id) }
                                } label: {
                                    Label(row.person.name.firstName, systemImage: on ? "checkmark.circle.fill" : "circle")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    .accessibilityLabel(Copy.interview.compare.who)
                }

                if groups.isEmpty {
                    Text(Copy.interview.compare.noAnswers)
                        .foregroundStyle(.secondary)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Copy.interview.compare.atAge(group.age))
                            .font(.headline)
                        ForEach(group.answers, id: \.milestoneId) { entry in
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.person.name.firstName).bold()
                                Text(entry.text)
                                Text("· \(String(entry.date.recordDay.year ?? 0))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if group.allSame {
                            Text(Copy.interview.compare.allSame)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
