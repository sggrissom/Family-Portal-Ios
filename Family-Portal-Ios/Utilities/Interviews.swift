import Foundation

/// The answers of one interview, folded into one card wherever moments are listed — `InterviewGroup` in frontend/lib/interviews.ts. Generic so the store's `Milestone`s and a response's `MilestoneDTO`s fold the same way.
struct InterviewAnswers<Item>: Identifiable {
    let interviewId: Int
    /// Oldest answer first, which is the order they were asked in.
    var answers: [Item]

    var id: Int { interviewId }
}

/// Ports of frontend/lib/interviews.ts, with its fixture cases in `InterviewsTests`, so the phone and the site fold, title and compare interviews the same way.
enum Interviews {

    /// Folds answers into one group per interview and leaves every other moment loose — `groupInterviewAnswers`. Groups keep the order their first answer arrived in; answers within one are ordered by `order`, the server id, as the web orders them.
    static func fold<Item>(
        _ items: [Item],
        interviewId: (Item) -> Int,
        order: (Item) -> Int
    ) -> (groups: [InterviewAnswers<Item>], loose: [Item]) {
        var groups: [InterviewAnswers<Item>] = []
        var index: [Int: Int] = [:]
        var loose: [Item] = []
        for item in items {
            let id = interviewId(item)
            guard id > 0 else {
                loose.append(item)
                continue
            }
            if let at = index[id] {
                groups[at].answers.append(item)
            } else {
                index[id] = groups.count
                groups.append(InterviewAnswers(interviewId: id, answers: [item]))
            }
        }
        for at in groups.indices {
            groups[at].answers.sort { order($0) < order($1) }
        }
        return (groups, loose)
    }

    static func fold(_ milestones: [Milestone]) -> (groups: [InterviewAnswers<Milestone>], loose: [Milestone]) {
        fold(milestones, interviewId: \.interviewId, order: { $0.serverId ?? .max })
    }

    static func fold(_ milestones: [MilestoneDTO]) -> (groups: [InterviewAnswers<MilestoneDTO>], loose: [MilestoneDTO]) {
        fold(milestones, interviewId: \.interviewId, order: \.id)
    }

    /// Whole years old on a record day — `ageYearsAt`, read in UTC because both dates are record dates. Never negative.
    static func ageYears(birthday: Date?, at date: Date) -> Int {
        guard let birthday, date >= birthday else { return 0 }
        let b = birthday.recordDay
        let d = date.recordDay
        var years = (d.year ?? 0) - (b.year ?? 0)
        if (d.month ?? 0, d.day ?? 0) < (b.month ?? 0, b.day ?? 0) {
            years -= 1
        }
        return max(0, years)
    }

    /// The interview's own title, else "Clara's interview at 7" — `interviewTitle`.
    static func title(_ interview: InterviewDTO, personName: String, birthday: Date?) -> String {
        interview.title.isEmpty ? fallbackTitle(personName: personName, birthday: birthday, date: interview.date) : interview.title
    }

    /// The title an untitled interview goes by, which is also what an answer can say without fetching its interview.
    static func fallbackTitle(personName: String, birthday: Date?, date: Date) -> String {
        "\(personName.firstName)'s interview at \(ageYears(birthday: birthday, at: date))"
    }

    /// "favorite snack" for "What's your favorite snack?" — the question as a card's highlight line labels it.
    static func shortQuestion(_ context: String) -> String {
        var text = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = text.range(of: #"^(what's|what is|who's|who is)\s+(your\s+)?"#, options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(match)
        }
        if text.hasSuffix("?") { text.removeLast() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased, accents and punctuation gone, runs of anything else one space — what "the same answer" means when comparing years.
    static func normalizeAnswer(_ text: String) -> String {
        let folded = text.lowercased().folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var words: [String] = []
        var word = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                word.unicodeScalars.append(scalar)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        return words.joined(separator: " ")
    }

    enum QuestionStatus: Equatable {
        case answered, skipped, pending
    }

    static func status(of questionId: Int, in interview: InterviewDTO, answered: Set<Int>) -> QuestionStatus {
        if answered.contains(questionId) { return .answered }
        if interview.skippedIds.contains(questionId) { return .skipped }
        return .pending
    }

    struct AnswerChange: Equatable {
        let questionId: Int
        let question: String
        let before: String
        let after: String
    }

    /// The answers that differ from the person's most recent earlier interview — `changesSincePrevious`, the "What changed since last time" strip.
    static func changesSincePrevious(
        questions: [InterviewQuestionDTO],
        answers: [Int: MilestoneDTO],
        previous: (Int) -> [PreviousAnswerDTO]
    ) -> [AnswerChange] {
        let earlier = questions.flatMap { previous($0.id) }
        guard let last = earlier.max(by: { $0.date < $1.date }), last.interviewId > 0 else { return [] }
        return questions.compactMap { question in
            guard let now = answers[question.id],
                  let before = previous(question.id).first(where: { $0.interviewId == last.interviewId }),
                  normalizeAnswer(now.descriptionText) != normalizeAnswer(before.text)
            else { return nil }
            let label = now.context.isEmpty ? question.text : now.context
            return AnswerChange(questionId: question.id, question: label, before: before.text, after: now.descriptionText)
        }
    }

    /// Section names in the order their first question appears.
    static func sections(_ questions: [InterviewQuestionDTO]) -> [String] {
        var names: [String] = []
        for question in questions where !names.contains(question.section) {
            names.append(question.section)
        }
        return names
    }
}
