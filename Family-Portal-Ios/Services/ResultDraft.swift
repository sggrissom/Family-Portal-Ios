import Foundation

nonisolated enum ResultValidationError: LocalizedError, Equatable, Sendable {
    case labelRequired
    case rankRequired
    case scoreRequired
    case rankOutOfRange
    case personNotOnEntry
    case tooManyResults

    var errorDescription: String? {
        switch self {
        case .labelRequired:
            return "An adjudication or award needs a label"
        case .rankRequired:
            return "A placement needs a rank"
        case .scoreRequired:
            return "A score result needs a score"
        case .rankOutOfRange:
            return "A rank must be 1 or greater, and no greater than the field size"
        case .personNotOnEntry:
            return "A result can only name someone on this entry's roster"
        case .tooManyResults:
            return "That is more results than one performance can hold"
        }
    }
}

/// One editable row of a results sheet. The numbers are held as text so an empty field and a zero stay different all the way to the wire.
nonisolated struct ResultDraft: Identifiable, Equatable, Sendable {
    /// Local only: `SetAppearanceResults` deletes every row and rewrites it, so nothing here can be keyed on a server id.
    let id: UUID
    var kind: ActivityResultKind
    var label: String
    var rankText: String
    var outOfText: String
    var category: String
    var scoreText: String
    var personId: Int?
    var notes: String

    init(
        id: UUID = UUID(),
        kind: ActivityResultKind = .adjudication,
        label: String = "",
        rankText: String = "",
        outOfText: String = "",
        category: String = "",
        scoreText: String = "",
        personId: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.rankText = rankText
        self.outOfText = outOfText
        self.category = category
        self.scoreText = scoreText
        self.personId = personId
        self.notes = notes
    }

    init(_ result: ActivityResultDTO) {
        self.init(
            kind: ActivityResultKind(rawValue: result.kind) ?? .adjudication,
            label: result.label,
            rankText: result.rank.map(String.init) ?? "",
            outOfText: result.outOf.map(String.init) ?? "",
            category: result.category,
            scoreText: result.score.map { Self.editableScore($0) } ?? "",
            personId: result.personId,
            notes: result.notes
        )
    }

    /// A score as text the editor can hand straight back to `Double(_:)`. Not `ActivityResultText.number`, which formats for the reader and would use the device's decimal separator.
    private static func editableScore(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(value)
    }

    // MARK: - Parsed values

    /// `nil` for an empty *or* unparseable field, so a bad rank surfaces as "a placement needs a rank" rather than as a silent 0.
    var rank: Int? { Self.int(rankText) }
    var outOf: Int? { Self.int(outOfText) }
    var score: Double? { Self.double(scoreText) }

    private static func int(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    private static func double(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces))
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmedLabel.isEmpty
            && rankText.trimmingCharacters(in: .whitespaces).isEmpty
            && outOfText.trimmingCharacters(in: .whitespaces).isEmpty
            && scoreText.trimmingCharacters(in: .whitespaces).isEmpty
            && category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && personId == nil
    }

    // MARK: - Validation

    /// The rules from `validateResultInput` and `resultPersonId`, mirrored here so the common mistakes never cost a round trip. The server still decides.
    func validate(roster: [Int]) -> ResultValidationError? {
        switch kind {
        case .adjudication, .award:
            if trimmedLabel.isEmpty { return .labelRequired }
        case .placement:
            if rank == nil { return .rankRequired }
        case .score:
            if score == nil { return .scoreRequired }
        }

        if let rank, rank < 1 { return .rankOutOfRange }
        if let outOf, outOf < 1 { return .rankOutOfRange }
        if let rank, let outOf, rank > outOf { return .rankOutOfRange }

        if let personId, personId > 0, !roster.contains(personId) {
            return .personNotOnEntry
        }

        return nil
    }

    /// The wire row, truncated to the server's caps: over-length text is silently truncated on write rather than refused.
    func input() -> ResultInputDTO {
        ResultInputDTO(
            kind: kind.rawValue,
            label: ActivityFieldLimit.label.clamp(label),
            rank: rank,
            outOf: outOf,
            category: ActivityFieldLimit.label.clamp(category),
            score: score,
            personId: personId,
            notes: ActivityFieldLimit.notes.clamp(notes)
        )
    }
}

/// The caps `trimField` applies server-side. Mirrored in the UI because the server truncates rather than refuses.
nonisolated struct ActivityFieldLimit: Sendable {
    let characters: Int

    static let name = ActivityFieldLimit(characters: 200)
    static let label = ActivityFieldLimit(characters: 100)
    static let notes = ActivityFieldLimit(characters: 4000)

    static let resultsPerAppearance = 50

    static let photosPerSubject = 200

    func clamp(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > characters ? String(trimmed.prefix(characters)) : trimmed
    }
}

nonisolated enum ResultSheet {

    static func validate(_ drafts: [ResultDraft], roster: [Int]) -> (row: ResultDraft.ID, error: ResultValidationError)? {
        let rows = drafts.filter { !$0.isBlank }

        if rows.count > ActivityFieldLimit.resultsPerAppearance {
            return rows.last.map { ($0.id, .tooManyResults) }
        }

        for row in rows {
            if let error = row.validate(roster: roster) {
                return (row.id, error)
            }
        }
        return nil
    }

    /// What the save sends: the non-blank rows in screen order. Array position *is* `sortOrder`, which is why `ResultInput` carries none.
    static func inputs(_ drafts: [ResultDraft]) -> [ResultInputDTO] {
        drafts.filter { !$0.isBlank }.map { $0.input() }
    }
}
