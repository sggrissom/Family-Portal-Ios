import SwiftUI

/// What a folded interview card says — the web's `InterviewCard`. Built from the store's answers (History, Story, Home's recent) or a response's (on this day, same age); only a response carries the `InterviewDTO`, so the store's cards go without a portrait or a title until the interview is opened.
struct InterviewCardModel: Identifiable {
    let interviewId: Int
    /// Left off when the card sits on that person's own Story.
    var personName: String?
    var age: Int?
    var interview: InterviewDTO?
    /// (question, answer), oldest answer first.
    var highlights: [(question: String, answer: String)]
    var answerCount: Int

    var id: Int { interviewId }

    static let highlightCount = 3

    init(answers: InterviewAnswers<Milestone>, showsPerson: Bool) {
        let person = answers.answers.first?.person
        interviewId = answers.interviewId
        personName = showsPerson ? person?.name.firstName : nil
        if let person, let birthday = person.birthday, let first = answers.answers.first {
            age = Interviews.ageYears(birthday: birthday, at: first.date)
        }
        highlights = answers.answers.prefix(Self.highlightCount).map { (question: $0.context, answer: $0.descriptionText) }
        answerCount = answers.answers.count
    }

    init(answers: InterviewAnswers<MilestoneDTO>, personName: String?, birthday: Date?, interview: InterviewDTO?) {
        interviewId = answers.interviewId
        self.personName = personName
        if let birthday, let date = interview?.date ?? answers.answers.first?.milestoneDate {
            age = Interviews.ageYears(birthday: birthday, at: date)
        }
        self.interview = interview
        highlights = answers.answers.prefix(Self.highlightCount).map { (question: $0.context, answer: $0.descriptionText) }
        answerCount = answers.answers.count
    }

    var title: String {
        var line: String
        if let custom = interview?.title, !custom.isEmpty {
            line = personName.map { "\($0) · \(custom)" } ?? custom
        } else {
            line = personName.map(Copy.interview.card.whose) ?? Copy.interview.card.title
        }
        if let age { line += " · \(Copy.interview.card.age(age))" }
        if interview?.isInProgress == true { line += " · \(Copy.interview.card.inProgress)" }
        return line
    }

    var countLine: String {
        let total = interview?.questionIds.count ?? 0
        return total > answerCount
            ? Copy.interview.card.someAnswers(answerCount, total)
            : Copy.interview.card.answers(answerCount)
    }
}

/// One interview as one card, opening the interview's page. Its own `NavigationLink` destination rather than an `AppRoute`, because it also sits in sheets whose stacks register no app routes.
struct InterviewCardView: View {
    let model: InterviewCardModel

    var body: some View {
        NavigationLink {
            InterviewView(interviewId: model.interviewId)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                cover
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.title)
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(model.highlights.enumerated()), id: \.offset) { _, line in
                        (Text("\(Interviews.shortQuestion(line.question)): ").foregroundStyle(.secondary) + Text(line.answer))
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                    Text(model.countLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(14)
            .background(MilestoneCategory.interview.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cover: some View {
        if let photoId = model.interview?.photoId, photoId > 0 {
            RemotePhotoView(remoteId: photoId, size: .thumb)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        } else {
            Image(systemName: MilestoneCategory.interview.icon)
                .font(.title3)
                .foregroundStyle(MilestoneCategory.interview.color)
                .frame(width: 40, height: 40)
                .background(MilestoneCategory.interview.color.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
        }
    }
}
