import SwiftUI

/// A person's Interviews tab — the web's `?tab=interviews`: start a new interview or pick one up, then every interview so far, newest first, each as one card.
struct PersonInterviewsTab: View {
    /// The person's server id.
    let personId: Int
    let personName: String
    let canContribute: Bool

    @Environment(InterviewService.self) private var service
    @State private var state = ActivityScreenState<GetPersonInterviewsResponseDTO>()

    var body: some View {
        ActivityScreen(state: state, read: { service.personInterviews(personId: personId) }) { bundle in
            content(bundle)
                .padding(.horizontal)
        }
    }

    private func content(_ bundle: GetPersonInterviewsResponseDTO) -> some View {
        let inProgress = bundle.interviews.last { $0.isInProgress }
        let byInterview = Dictionary(grouping: bundle.answers, by: \.interviewId)
        let newestFirst = Array(bundle.interviews.reversed())
        return VStack(alignment: .leading, spacing: 16) {
            if canContribute {
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

            if bundle.interviews.isEmpty {
                Text(Copy.interview.tab.empty(personName.firstName))
                    .foregroundStyle(.secondary)
            }

            ForEach(newestFirst) { interview in
                let answers = (byInterview[interview.id] ?? []).sorted { $0.id < $1.id }
                InterviewCardView(model: InterviewCardModel(
                    answers: InterviewAnswers(interviewId: interview.id, answers: answers),
                    personName: nil,
                    birthday: bundle.person.birthday,
                    interview: interview
                ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
