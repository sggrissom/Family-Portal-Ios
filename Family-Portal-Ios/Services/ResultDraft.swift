import Foundation

/// Why a results sheet cannot be saved as it stands.
///
/// The messages are the backend's own sentences, word for word
/// (backend/activity_results.go). That is the point: the same refusal has to
/// read the same whether the device caught it or the server did, or a user who
/// hits both learns that the app and the server disagree about the rules when
/// they do not.
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

/// One editable row of a results sheet.
///
/// The numbers are held as text rather than as `Int?`/`Double?` bound through a
/// formatter, because an empty field and a zero have to stay different things
/// all the way to the wire: `rank` is `*int` with `omitempty` precisely so "no
/// placement" is not "1st", and a `TextField` bound to a number would turn a
/// cleared field into 0 and send a rank the server refuses.
nonisolated struct ResultDraft: Identifiable, Equatable, Sendable {
    /// Local only. Results have no stable server identity across a save —
    /// `SetAppearanceResults` deletes every row and rewrites it — so nothing
    /// here can be keyed on the id the server hands back.
    let id: UUID
    var kind: ActivityResultKind
    var label: String
    var rankText: String
    var outOfText: String
    var category: String
    var scoreText: String
    /// The one person this result names, when it narrows an award to a single
    /// dancer inside a group. `nil` is "the whole entry", which is the usual
    /// case.
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

    /// Reads a row the server already holds back into an editable one.
    ///
    /// A `kind` this build does not recognize falls to `.adjudication` rather
    /// than dropping the row: `normalizeResultKind` refuses unknown kinds on
    /// write, so re-saving the sheet would otherwise fail on a row the user
    /// cannot even see.
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

    /// A score as text the editor can hand straight back to `Double(_:)`.
    ///
    /// Deliberately *not* `ActivityResultText.number`, which formats for the
    /// reader and would use the device's decimal separator: a phone set to a
    /// locale that writes 92,5 would put a string in the field that parses back
    /// as `nil`, and the next save would report "a score result needs a score"
    /// for a score the user never touched. `String(_: Double)` and
    /// `Double(_: String)` are both locale-independent, so they round-trip.
    private static func editableScore(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(value)
    }

    // MARK: - Parsed values

    /// `nil` for an empty *or* unparseable field. Unparseable reads as absent on
    /// purpose: for a placement that surfaces as "a placement needs a rank",
    /// which is the truth the user needs, rather than as a silent 0.
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

    /// Whether the row carries nothing at all — an accidental extra row in the
    /// form. The server refuses these through the per-kind checks; the editor
    /// can just drop them.
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

    /// The rules from `validateResultInput` and `resultPersonId`, checked here so
    /// the user gets an inline error instead of a round-trip 400.
    ///
    /// This is a mirror, not a replacement: the server checks all of it again,
    /// and it is the server that decides. What this buys is that the common
    /// mistakes never cost a round trip in a building with no signal.
    func validate(roster: [Int]) -> ResultValidationError? {
        switch kind {
        case .adjudication, .award:
            if trimmedLabel.isEmpty { return .labelRequired }
        case .placement:
            if rank == nil { return .rankRequired }
        case .score:
            if score == nil { return .scoreRequired }
        }

        // Checked for every kind, not just placements: a rank on an award is
        // odd but legal, and the server bounds it either way.
        if let rank, rank < 1 { return .rankOutOfRange }
        if let outOf, outOf < 1 { return .rankOutOfRange }
        if let rank, let outOf, rank > outOf { return .rankOutOfRange }

        // A zero or negative id reads as "names nobody" server-side, so only a
        // real id has to be on the roster.
        if let personId, personId > 0, !roster.contains(personId) {
            return .personNotOnEntry
        }

        return nil
    }

    /// The wire row. Truncated to the server's caps rather than sent long:
    /// over-length text is silently *truncated* on write, not refused, so a
    /// field that let the user type 300 characters would quietly lose 100 of
    /// them somewhere they never see.
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

/// The caps `trimField` applies server-side (backend/activity_procs.go,
/// activity_results.go, activity_photos.go).
///
/// Mirrored in the UI because the server *truncates* rather than refuses. A form
/// that lets the user type past the limit does not fail — it silently keeps less
/// than they wrote, which they find out about later, if ever.
nonisolated struct ActivityFieldLimit: Sendable {
    let characters: Int

    static let name = ActivityFieldLimit(characters: 200)
    static let label = ActivityFieldLimit(characters: 100)
    static let notes = ActivityFieldLimit(characters: 4000)

    /// `maxResultsPerAppearance`. A sanity bound rather than a domain limit: a
    /// routine collects an adjudication, a placement or two and a handful of
    /// special awards, and anything past this is a paste accident.
    static let resultsPerAppearance = 50

    /// `maxPhotosPerSubject`, per request rather than per record.
    static let photosPerSubject = 200

    func clamp(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > characters ? String(trimmed.prefix(characters)) : trimmed
    }
}

/// A whole results sheet, ready to save.
nonisolated enum ResultSheet {

    /// Drops the blank rows, then validates what is left.
    ///
    /// Returns the row that failed alongside the reason, so the editor can put
    /// the message under that row rather than at the top of a list where the
    /// reader has to work out which one it means.
    static func validate(_ drafts: [ResultDraft], roster: [Int]) -> (row: ResultDraft.ID, error: ResultValidationError)? {
        let rows = drafts.filter { !$0.isBlank }

        if rows.count > ActivityFieldLimit.resultsPerAppearance {
            // Charged to the last row, which is the one that put the sheet over.
            return rows.last.map { ($0.id, .tooManyResults) }
        }

        for row in rows {
            if let error = row.validate(roster: roster) {
                return (row.id, error)
            }
        }
        return nil
    }

    /// What the save sends: the non-blank rows, in the order they are on screen.
    /// Array position *is* `sortOrder`, which is why `ResultInput` carries none.
    static func inputs(_ drafts: [ResultDraft]) -> [ResultInputDTO] {
        drafts.filter { !$0.isBlank }.map { $0.input() }
    }
}
