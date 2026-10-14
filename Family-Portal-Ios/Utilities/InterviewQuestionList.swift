import Foundation

/// One question being edited. `key` is local and stable, and is its identity: a new question has no server id yet.
struct QuestionRow: Identifiable, Equatable {
    let key: Int
    /// The server's id; 0 until saved.
    var questionId: Int
    var text: String
    var section: String
    var minAgeYears: Int
    var maxAgeYears: Int
    var defaultKey: String
    var archived: Bool

    var id: Int { key }
}

/// The question list as the editor holds it — a port of frontend/lib/interviewQuestions.ts, with its cases in `InterviewQuestionListTests`. Rows keep their order across sections; `sections` is the order sections are shown and saved in, and may name an empty one.
struct QuestionListDraft: Equatable {
    var rows: [QuestionRow] = []
    var sections: [String] = []
    private var nextKey = 1

    init(_ questions: [InterviewQuestionDTO] = []) {
        for question in questions {
            addRow(text: question.text, section: question.section, from: question)
        }
    }

    @discardableResult
    mutating func addRow(text: String, section: String, from question: InterviewQuestionDTO? = nil, at index: Int? = nil) -> QuestionRow {
        let row = QuestionRow(
            key: nextKey,
            questionId: question?.id ?? 0,
            text: text,
            section: section,
            minAgeYears: question?.minAgeYears ?? 0,
            maxAgeYears: question?.maxAgeYears ?? 0,
            defaultKey: question?.defaultKey ?? "",
            archived: question?.archived ?? false
        )
        nextKey += 1
        rows.insert(row, at: min(index ?? rows.count, rows.count))
        if !sections.contains(section) { sections.append(section) }
        return row
    }

    func active(in section: String) -> [QuestionRow] {
        rows.filter { $0.section == section && !$0.archived }
    }

    var retired: [QuestionRow] {
        rows.filter(\.archived)
    }

    func index(of key: Int) -> Int? {
        rows.firstIndex { $0.key == key }
    }

    private mutating func take(_ key: Int) -> QuestionRow? {
        index(of: key).map { rows.remove(at: $0) }
    }

    /// Just past the section's last row; for an empty section, before the first row of any section after it.
    func endOf(_ section: String) -> Int {
        if let last = rows.lastIndex(where: { $0.section == section }) { return last + 1 }
        let later = Set(sections.drop(while: { $0 != section }).dropFirst())
        return rows.firstIndex { later.contains($0.section) } ?? rows.count
    }

    /// Puts a question before another, taking that one's section.
    mutating func move(_ key: Int, before targetKey: Int) {
        guard key != targetKey, var row = take(key) else { return }
        guard let at = index(of: targetKey) else {
            rows.append(row)
            return
        }
        row.section = rows[at].section
        rows.insert(row, at: at)
    }

    /// To the end of a section, even an empty or new one.
    mutating func move(_ key: Int, toSection section: String) {
        guard var row = take(key) else { return }
        if !sections.contains(section) { sections.append(section) }
        row.section = section
        rows.insert(row, at: endOf(section))
    }

    /// Up and down step past neighbours in the same section, then across the section edge, so a question can travel the whole list with two buttons.
    mutating func step(_ key: Int, by step: Int) {
        guard let row = rows.first(where: { $0.key == key }), !row.archived else { return }
        let siblings = active(in: row.section)
        if let at = siblings.firstIndex(of: row), siblings.indices.contains(at + step) {
            let neighbour = siblings[at + step]
            if step < 0 { move(key, before: neighbour.key) } else { move(neighbour.key, before: key) }
            return
        }
        guard let here = sections.firstIndex(of: row.section), sections.indices.contains(here + step) else { return }
        let next = sections[here + step]
        if step > 0, let first = active(in: next).first {
            move(key, before: first.key)
        } else {
            move(key, toSection: next)
        }
    }

    mutating func rename(section from: String, to name: String) {
        let to = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !to.isEmpty, to != from else { return }
        for index in rows.indices where rows[index].section == from {
            rows[index].section = to
        }
        sections = sections.contains(to) ? sections.filter { $0 != from } : sections.map { $0 == from ? to : $0 }
    }

    /// False for a blank name or one already there.
    @discardableResult
    mutating func addSection(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !sections.contains(name) else { return false }
        sections.append(name)
        return true
    }

    /// Restores every retired built-in and adds the built-ins that are missing. The family's own questions are never touched.
    mutating func resetToDefaults(_ defaults: [InterviewQuestionDTO]) {
        let have = Set(rows.map(\.defaultKey))
        for index in rows.indices where !rows[index].defaultKey.isEmpty {
            rows[index].archived = false
        }
        for question in defaults where !have.contains(question.defaultKey) {
            if !sections.contains(question.section) { sections.append(question.section) }
            addRow(text: question.text, section: question.section, from: question, at: endOf(question.section))
        }
    }

    /// Suggested built-ins, each added to the end of its section.
    mutating func adopt(_ questions: [InterviewQuestionDTO]) {
        for question in questions {
            if !sections.contains(question.section) { sections.append(question.section) }
            addRow(text: question.text, section: question.section, from: question, at: endOf(question.section))
        }
    }

    mutating func remove(_ key: Int) {
        _ = take(key)
    }

    /// Every row in section order — what `SaveInterviewQuestions` takes, the list's new order.
    var questionsForSave: [InterviewQuestionInputDTO] {
        sections.flatMap { section in
            rows.filter { $0.section == section }.map { row in
                InterviewQuestionInputDTO(
                    id: row.questionId, text: row.text, section: row.section,
                    minAgeYears: row.minAgeYears, maxAgeYears: row.maxAgeYears,
                    defaultKey: row.defaultKey, archived: row.archived
                )
            }
        }
    }
}
