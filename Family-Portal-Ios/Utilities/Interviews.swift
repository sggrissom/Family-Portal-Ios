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

/// What is being typed into an answer, held until it saves — the web's localStorage drafts. Keyed by interview and question, so a phone that sleeps or loses signal mid-sentence finds the words again on the way back in.
/// Also remembers "show earlier answers while asking", which, like the web's, belongs to this device rather than the account.
struct InterviewDrafts {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static let prefix = "interview-draft:"
    private static let showPreviousKey = "interview-show-previous"

    private static func key(_ interviewId: Int, _ questionId: Int) -> String {
        "\(prefix)\(interviewId):\(questionId)"
    }

    func save(_ text: String, interviewId: Int, questionId: Int) {
        defaults.set(text, forKey: Self.key(interviewId, questionId))
    }

    func clear(interviewId: Int, questionId: Int) {
        defaults.removeObject(forKey: Self.key(interviewId, questionId))
    }

    /// Every draft held for one interview, by question id.
    func drafts(interviewId: Int) -> [Int: String] {
        let prefix = "\(Self.prefix)\(interviewId):"
        var drafts: [Int: String] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            if let questionId = Int(key.dropFirst(prefix.count)), let text = value as? String {
                drafts[questionId] = text
            }
        }
        return drafts
    }

    var showsPrevious: Bool {
        get { defaults.object(forKey: Self.showPreviousKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.showPreviousKey) }
    }
}

extension Interviews {
    /// "Age 6: Goldfish · Age 5: apple slices" — the faded line under an answer — `previousLine`.
    static func previousLine(_ previous: [PreviousAnswerDTO], limit: Int = 3) -> String {
        previous.prefix(limit).map { "\(Copy.interview.ask.atAge($0.ageYears)): \($0.text)" }.joined(separator: " · ")
    }

    /// Zero is no bound — `questionFitsAge`. Outside the range a question starts unchecked; the parent can still ask it.
    static func fits(_ question: InterviewQuestionDTO, age: Int) -> Bool {
        (question.minAgeYears == 0 || age >= question.minAgeYears) && (question.maxAgeYears == 0 || age <= question.maxAgeYears)
    }

    /// How setup names a question before the family's list is saved: by id, or by its built-in key — `questionRef`.
    static func ref(_ question: InterviewQuestionDTO) -> String {
        question.id > 0 ? "id:\(question.id)" : "key:\(question.defaultKey)"
    }
}

// MARK: - Over the years

/// One answer cell of the Years grid — `GridCell`.
struct InterviewGridCell {
    enum Trend: Equatable { case none, first, same, changed }

    var answer: MilestoneDTO?
    var skipped = false
    var asked = false
    /// Against the last earlier answer to the same question: new, the same again, or changed.
    var trend: Trend = .none
}

struct InterviewGridRow: Identifiable {
    let question: InterviewQuestionDTO
    let cells: [InterviewGridCell]

    var id: Int { question.id }

    /// The question as it was last asked (the newest answer's context), else the list's wording — `rowLabel`.
    var label: String {
        if let context = cells.reversed().compactMap({ $0.answer?.context }).first(where: { !$0.isEmpty }) {
            return context
        }
        return question.text.replacingOccurrences(of: "{name}", with: "you").replacingOccurrences(of: "{age}", with: "your age")
    }
}

struct InterviewGridSection: Identifiable {
    let name: String
    var rows: [InterviewGridRow]

    var id: String { name }
}

/// One question's answers in age order, for the Questions view — `QuestionTimeline`.
struct InterviewTimeline: Identifiable {
    struct Point {
        let interview: InterviewDTO
        let answer: MilestoneDTO
        let age: Int
    }

    let question: InterviewQuestionDTO
    let points: [Point]
    /// The longest run of the same answer.
    let streak: Int
    /// How many different answers.
    let distinct: Int

    var id: Int { question.id }

    var label: String {
        points.last.map { $0.answer.context.isEmpty ? question.text : $0.answer.context } ?? question.text
    }
}

enum InterviewTimelineSort: String, CaseIterable, Identifiable {
    case list, consistent, changed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: Copy.interview.tab.sortList
        case .consistent: Copy.interview.tab.sortConsistent
        case .changed: Copy.interview.tab.sortChanged
        }
    }
}

/// Everyone's answers at one age, for comparing — `AgeGroup`.
struct InterviewAgeGroup: Identifiable {
    struct Entry {
        let person: PersonDTO
        let text: String
        let date: Date
        let milestoneId: Int
    }

    let age: Int
    var answers: [Entry]

    var id: Int { age }

    /// Everyone said the same thing.
    var allSame: Bool {
        answers.count > 1 && Set(answers.map { Interviews.normalizeAnswer($0.text) }).count == 1
    }
}

extension Interviews {
    static let alsoAsked = "Also asked"

    /// The Years grid: questions by section in list order with one-offs collected last under "Also asked", one column per interview, oldest first — `interviewGrid`. A question never answered or skipped is left out, so a retired one shows only in the years it was asked.
    static func grid(_ bundle: GetPersonInterviewsResponseDTO) -> [InterviewGridSection] {
        var byCell: [String: MilestoneDTO] = [:]
        for answer in bundle.answers {
            byCell["\(answer.interviewId):\(answer.questionId)"] = answer
        }
        let questions = bundle.questions.sorted { a, b in
            if a.oneOff != b.oneOff { return !a.oneOff }
            if a.position != b.position { return a.position < b.position }
            return a.id < b.id
        }
        var sections: [InterviewGridSection] = []
        for question in questions {
            var last = ""
            let cells = bundle.interviews.map { interview -> InterviewGridCell in
                let answer = byCell["\(interview.id):\(question.id)"]
                var cell = InterviewGridCell(
                    answer: answer,
                    skipped: answer == nil && interview.skippedIds.contains(question.id),
                    asked: interview.questionIds.contains(question.id) || answer != nil
                )
                if let answer {
                    let normalized = normalizeAnswer(answer.descriptionText)
                    cell.trend = last.isEmpty ? .first : normalized == last ? .same : .changed
                    last = normalized
                }
                return cell
            }
            guard cells.contains(where: { $0.answer != nil || $0.skipped }) else { continue }
            let name = question.oneOff ? alsoAsked : question.section
            let row = InterviewGridRow(question: question, cells: cells)
            if let at = sections.firstIndex(where: { $0.name == name }) {
                sections[at].rows.append(row)
            } else {
                sections.append(InterviewGridSection(name: name, rows: [row]))
            }
        }
        if let at = sections.firstIndex(where: { $0.name == alsoAsked }) {
            sections.append(sections.remove(at: at))
        }
        return sections
    }

    /// One timeline per question, in grid order — `questionTimelines`.
    static func timelines(_ bundle: GetPersonInterviewsResponseDTO) -> [InterviewTimeline] {
        grid(bundle).flatMap(\.rows).map { row in
            let points = zip(bundle.interviews, row.cells).compactMap { interview, cell -> InterviewTimeline.Point? in
                cell.answer.map {
                    InterviewTimeline.Point(interview: interview, answer: $0, age: ageYears(birthday: bundle.person.birthday, at: interview.date))
                }
            }
            var streak = 0
            var run = 0
            var previous: String?
            var seen = Set<String>()
            for point in points {
                let normalized = normalizeAnswer(point.answer.descriptionText)
                run = normalized == previous ? run + 1 : 1
                previous = normalized
                streak = max(streak, run)
                seen.insert(normalized)
            }
            return InterviewTimeline(question: row.question, points: points, streak: streak, distinct: seen.count)
        }
    }

    /// Questions answered more than once come first either way. "Most consistent" then puts the longest run of the same answer first; "Most changed", the most different answers for the times asked — `sortTimelines`. Ties keep list order.
    static func sorted(_ timelines: [InterviewTimeline], by sort: InterviewTimelineSort) -> [InterviewTimeline] {
        func multi(_ t: InterviewTimeline) -> Int { t.points.count > 1 ? 1 : 0 }
        func ratio(_ t: InterviewTimeline) -> Double { t.points.isEmpty ? 0 : Double(t.distinct) / Double(t.points.count) }
        let indexed = Array(timelines.enumerated())
        let ordered: [(offset: Int, element: InterviewTimeline)]
        switch sort {
        case .list:
            return timelines
        case .consistent:
            ordered = indexed.sorted { a, b in
                (multi(b.element), b.element.streak, a.offset) < (multi(a.element), a.element.streak, b.offset)
            }
        case .changed:
            ordered = indexed.sorted { a, b in
                (multi(b.element), ratio(b.element), b.element.distinct, a.offset) < (multi(a.element), ratio(a.element), a.element.distinct, b.offset)
            }
        }
        return ordered.map(\.element)
    }

    /// Questions whose wording or any answer contains the query — `filterTimelines`.
    static func filtered(_ timelines: [InterviewTimeline], query: String) -> [InterviewTimeline] {
        let wanted = normalizeAnswer(query)
        guard !wanted.isEmpty else { return timelines }
        return timelines.filter { timeline in
            normalizeAnswer(timeline.question.text).contains(wanted)
                || timeline.points.contains { normalizeAnswer($0.answer.descriptionText).contains(wanted) }
        }
    }

    /// "Age 5 · 2024", or just the year without a birthday — `columnLabel`.
    static func columnLabel(_ interview: InterviewDTO, birthday: Date?) -> String {
        let year = interview.date.recordDay.year ?? 0
        guard let birthday else { return String(year) }
        return "Age \(ageYears(birthday: birthday, at: interview.date)) · \(year)"
    }

    /// Each person's answers lined up by age, youngest age first — `compareByAge`.
    static func byAge(_ rows: [CompareRowDTO]) -> [InterviewAgeGroup] {
        var groups: [Int: InterviewAgeGroup] = [:]
        for row in rows {
            for answer in row.answers {
                let entry = InterviewAgeGroup.Entry(person: row.person, text: answer.text, date: answer.date, milestoneId: answer.milestoneId)
                groups[answer.ageYears, default: InterviewAgeGroup(age: answer.ageYears, answers: [])].answers.append(entry)
            }
        }
        return groups.values.sorted { $0.age < $1.age }
    }
}

// MARK: - Past interviews

/// What the past-interview form holds: an answer per listed question (by `Interviews.ref`), and questions that are not on the list. Blank means "not asked" and is never sent.
struct PastInterviewDraft {
    struct Extra: Identifiable {
        let id = UUID()
        var question = ""
        var answer = ""
        /// Add it to the family's list; otherwise it is kept for this interview only.
        var keep = true

        var isFilled: Bool {
            !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var answers: [String: String] = [:]
    var extras: [Extra] = []

    /// How many answers a save would send — the count on the Save button.
    var filled: Int {
        answers.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            + extras.filter(\.isFilled).count
    }

    /// The answers to send, in list order, then the extras in the order they were added.
    func importAnswers(listOrder questions: [InterviewQuestionDTO]) -> [ImportAnswerDTO] {
        let listed = questions.compactMap { question -> ImportAnswerDTO? in
            let ref = Interviews.ref(question)
            let answer = (answers[ref] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return answer.isEmpty ? nil : ImportAnswerDTO(ref: ref, answer: answer, newText: "", keep: false)
        }
        let added = extras.filter(\.isFilled).map { extra in
            ImportAnswerDTO(
                ref: "",
                answer: extra.answer.trimmingCharacters(in: .whitespacesAndNewlines),
                newText: extra.question.trimmingCharacters(in: .whitespacesAndNewlines),
                keep: extra.keep
            )
        }
        return listed + added
    }
}
