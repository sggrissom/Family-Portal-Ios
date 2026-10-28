import Foundation

/// A head-to-head round on an appearance: a battle bracket or a tournament game. A port of frontend/lib/matchups.ts, with its test table, so both clients word a record and a run the same way.
nonisolated struct Matchup: Equatable, Sendable {
    var round = ""
    var opponent = ""
    /// `""`, or one of `MatchupOutcome`.
    var outcome = ""
    /// `nil` means no score was kept — a dance battle has an outcome and no score. Never read it as 0.
    var scoreFor: Int?
    var scoreAgainst: Int?

    init(round: String = "", opponent: String = "", outcome: String = "", scoreFor: Int? = nil, scoreAgainst: Int? = nil) {
        self.round = round
        self.opponent = opponent
        self.outcome = outcome
        self.scoreFor = scoreFor
        self.scoreAgainst = scoreAgainst
    }

    init(_ appearance: AppearanceDTO) {
        self.init(
            round: appearance.round,
            opponent: appearance.opponent,
            outcome: appearance.outcome,
            scoreFor: appearance.scoreFor,
            scoreAgainst: appearance.scoreAgainst
        )
    }

    var isRecorded: Bool {
        !round.isEmpty || !opponent.isEmpty || !outcome.isEmpty || scoreFor != nil || scoreAgainst != nil
    }

    var scoreText: String {
        guard scoreFor != nil || scoreAgainst != nil else { return "" }
        return "\(scoreFor.map(String.init) ?? "?")–\(scoreAgainst.map(String.init) ?? "?")"
    }

    /// Round, opponent, then the result, leaving out what wasn't recorded: `["Final", "vs Crew Z", "Won 3–1"]`.
    var parts: [String] {
        let result = [MatchupOutcome.label(outcome), scoreText].filter { !$0.isEmpty }.joined(separator: " ")
        return [round, opponent.isEmpty ? "" : "vs \(opponent)", result].filter { !$0.isEmpty }
    }

    /// What the write sends: the whole matchup, so an empty one clears it.
    var input: MatchupInputDTO {
        MatchupInputDTO(
            round: ActivityFieldLimit.label.clamp(round),
            opponent: ActivityFieldLimit.label.clamp(opponent),
            outcome: outcome,
            scoreFor: scoreFor,
            scoreAgainst: scoreAgainst
        )
    }
}

/// The `outcome` values backend/activity.go accepts.
nonisolated enum MatchupOutcome {
    static let win = "win"
    static let loss = "loss"
    static let draw = "draw"

    /// In the order the editor offers them, "not recorded" first.
    static let all = ["", win, loss, draw]

    /// "Won", "Lost" or "Draw"; empty for no outcome or one this build doesn't know.
    static func label(_ outcome: String) -> String {
        switch outcome {
        case win: return "Won"
        case loss: return "Lost"
        case draw: return "Draw"
        default: return ""
        }
    }

    /// The editor's wording, where no outcome is a choice of its own.
    static func optionLabel(_ outcome: String) -> String {
        outcome.isEmpty ? "—" : label(outcome)
    }
}

nonisolated enum Matchups {
    /// Offered when naming a round; anything typed is fine too.
    static let commonRounds = ["Round 1", "Round 2", "Quarterfinal", "Semifinal", "Final"]
    /// backend/activity_results.go `maxMatchupScore`.
    static let maxScore = 9999

    struct Tally: Equatable, Sendable {
        var wins = 0
        var losses = 0
        var draws = 0
    }

    static func tally(_ matchups: [Matchup]) -> Tally {
        var tally = Tally()
        for matchup in matchups {
            switch matchup.outcome {
            case MatchupOutcome.win: tally.wins += 1
            case MatchupOutcome.loss: tally.losses += 1
            case MatchupOutcome.draw: tally.draws += 1
            default: break
            }
        }
        return tally
    }

    /// `2–1`, or `2–1–1` once there is a draw; empty with nothing decided.
    static func recordText(_ tally: Tally) -> String {
        guard tally.wins + tally.losses + tally.draws > 0 else { return "" }
        var parts = [tally.wins, tally.losses]
        if tally.draws > 0 { parts.append(tally.draws) }
        return parts.map(String.init).joined(separator: "–")
    }

    static func recordLabel(_ tally: Tally) -> String {
        tally.draws > 0 ? "W–L–D" : "W–L"
    }

    /// How an entry's rounds at one event went, named by the last decided one: "Went 2–1, lost in the Final".
    static func runSummary(_ matchups: [Matchup]) -> String {
        let decided = matchups.filter { !$0.outcome.isEmpty }
        guard let last = decided.last else { return "" }
        let record = recordText(tally(decided))
        guard !last.round.isEmpty else { return "Went \(record)" }
        let round = last.round.lowercased().hasPrefix("round") ? last.round : "the \(last.round)"
        switch last.outcome {
        case MatchupOutcome.win: return "Went \(record), won \(round)"
        case MatchupOutcome.loss: return "Went \(record), lost in \(round)"
        default: return "Went \(record), drew in \(round)"
        }
    }

    /// Each key's rows together, in first-seen order — an entry's rounds at one event.
    static func group<Row, Key: Hashable>(_ rows: [Row], by key: (Row) -> Key) -> [[Row]] {
        var order: [Key] = []
        var groups: [Key: [Row]] = [:]
        for row in rows {
            let k = key(row)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(row)
        }
        return order.map { groups[$0] ?? [] }
    }
}

/// The head-to-head fields as typed: scores are text until saved.
nonisolated struct MatchupDraft: Equatable, Sendable {
    var round = ""
    var opponent = ""
    var outcome = ""
    var scoreFor = ""
    var scoreAgainst = ""

    init() {}

    init(_ matchup: Matchup) {
        round = matchup.round
        opponent = matchup.opponent
        outcome = matchup.outcome
        scoreFor = matchup.scoreFor.map(String.init) ?? ""
        scoreAgainst = matchup.scoreAgainst.map(String.init) ?? ""
    }

    /// Why this can't be saved, or nil.
    var error: String? {
        let scores = [Self.parseScore(scoreFor), Self.parseScore(scoreAgainst)]
        if scores.contains(where: { $0 == .invalid }) { return "A score must be a whole number." }
        if scores.contains(where: { if case .score(let value) = $0 { return value > Matchups.maxScore }; return false }) {
            return "A score must be between 0 and \(Matchups.maxScore)."
        }
        return nil
    }

    var matchup: Matchup {
        Matchup(
            round: round.trimmingCharacters(in: .whitespacesAndNewlines),
            opponent: opponent.trimmingCharacters(in: .whitespacesAndNewlines),
            outcome: outcome,
            scoreFor: Self.parseScore(scoreFor).value,
            scoreAgainst: Self.parseScore(scoreAgainst).value
        )
    }

    /// The outcome two scores imply, or empty until both are in.
    var outcomeFromScore: String {
        guard let ours = Self.parseScore(scoreFor).value, let theirs = Self.parseScore(scoreAgainst).value else { return "" }
        if ours > theirs { return MatchupOutcome.win }
        if ours < theirs { return MatchupOutcome.loss }
        return MatchupOutcome.draw
    }

    private enum ParsedScore: Equatable {
        case none
        case score(Int)
        case invalid

        var value: Int? {
            if case .score(let value) = self { return value }
            return nil
        }
    }

    private static func parseScore(_ text: String) -> ParsedScore {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .none }
        guard trimmed.allSatisfy(\.isASCIIDigit), let value = Int(trimmed) else { return .invalid }
        return .score(value)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
