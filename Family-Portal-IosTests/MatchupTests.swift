import Foundation
import Testing
@testable import Family_Portal_Ios

/// frontend/lib/matchups.test.ts, case for case, plus the wire shape.
@MainActor
@Suite("Matchups")
struct MatchupTests {

    private static func m(
        round: String = "",
        opponent: String = "",
        outcome: String = "",
        scoreFor: Int? = nil,
        scoreAgainst: Int? = nil
    ) -> Matchup {
        Matchup(round: round, opponent: opponent, outcome: outcome, scoreFor: scoreFor, scoreAgainst: scoreAgainst)
    }

    // MARK: - Wording

    @Test("Reads round, opponent, then the result")
    func parts() {
        #expect(Self.m(round: "Final", opponent: "Crew Z", outcome: "win", scoreFor: 3, scoreAgainst: 1).parts == ["Final", "vs Crew Z", "Won 3–1"])
    }

    @Test("Leaves out what was not recorded")
    func partsLeaveOutBlanks() {
        #expect(Self.m(outcome: "loss").parts == ["Lost"])
        #expect(Self.m(scoreFor: 2, scoreAgainst: 2).parts == ["2–2"])
        #expect(Self.m().parts.isEmpty)
    }

    @Test("A zero score counts as recorded")
    func zeroScoreIsRecorded() {
        #expect(!Self.m().isRecorded)
        #expect(Self.m(scoreAgainst: 0).isRecorded)
    }

    @Test("A record shows draws only when there are any")
    func recordText() {
        #expect(Matchups.recordText(Matchups.tally([Self.m(outcome: "win"), Self.m(outcome: "loss")])) == "1–1")
        #expect(Matchups.recordText(Matchups.tally([Self.m(outcome: "win"), Self.m(outcome: "draw")])) == "1–0–1")
        #expect(Matchups.recordText(Matchups.tally([Self.m(round: "Final")])) == "")
    }

    @Test("The draw column is named only when it is shown")
    func recordLabel() {
        #expect(Matchups.recordLabel(Matchups.Tally(wins: 2, losses: 1, draws: 0)) == "W–L")
        #expect(Matchups.recordLabel(Matchups.Tally(wins: 2, losses: 1, draws: 1)) == "W–L–D")
    }

    @Test("A run is named by how it ended")
    func runSummary() {
        let bracket = [
            Self.m(round: "Round 1", outcome: "win"),
            Self.m(round: "Semifinal", outcome: "win"),
            Self.m(round: "Final", outcome: "loss"),
        ]
        #expect(Matchups.runSummary(bracket) == "Went 2–1, lost in the Final")
        #expect(Matchups.runSummary(Array(bracket.prefix(2))) == "Went 2–0, won the Semifinal")
        #expect(Matchups.runSummary([Self.m(round: "Round 2", outcome: "loss")]) == "Went 0–1, lost in Round 2")
    }

    @Test("A run ignores undecided rounds and unnamed ones")
    func runSummaryIgnoresUndecided() {
        #expect(Matchups.runSummary([Self.m(outcome: "win"), Self.m(round: "Final")]) == "Went 1–0")
        #expect(Matchups.runSummary([Self.m(round: "Final")]) == "")
    }

    @Test("Each entry's rows stay together in first-seen order")
    func groupByEntry() {
        let rows = [1, 2, 1, 3, 2].enumerated().map { (index: $0.offset, entry: $0.element) }
        #expect(Matchups.group(rows) { $0.entry }.map { $0.map(\.index) } == [[0, 2], [1, 4], [3]])
    }

    // MARK: - Drafts

    @Test("A matchup round-trips through a draft, keeping a zero score")
    func draftRoundTrip() {
        let matchup = Self.m(round: "Final", outcome: "win", scoreFor: 1, scoreAgainst: 0)
        #expect(MatchupDraft(matchup).matchup == matchup)
    }

    @Test("A draft trims, and refuses a score that isn't a whole number")
    func draftValidation() {
        var draft = MatchupDraft(Self.m())
        draft.round = " Final "
        draft.scoreFor = "two"
        #expect(draft.error != nil)
        draft.scoreFor = " 2 "
        #expect(draft.error == nil)
        #expect(draft.matchup.round == "Final")
        #expect(draft.matchup.scoreFor == 2)
        draft.scoreFor = "-1"
        #expect(draft.error != nil)
        draft.scoreFor = "10000"
        #expect(draft.error != nil)
    }

    @Test("An outcome is derived only from two scores")
    func outcomeFromScore() {
        func draft(_ ours: String, _ theirs: String) -> MatchupDraft {
            var draft = MatchupDraft()
            draft.scoreFor = ours
            draft.scoreAgainst = theirs
            return draft
        }
        #expect(draft("3", "1").outcomeFromScore == "win")
        #expect(draft("0", "1").outcomeFromScore == "loss")
        #expect(draft("2", "2").outcomeFromScore == "draw")
        #expect(draft("2", "").outcomeFromScore == "")
    }

    @Test("An outcome the score contradicts is refused; a level score can still be won on penalties")
    func outcomeContradictingScore() {
        var draft = MatchupDraft()
        draft.scoreFor = "1"
        draft.scoreAgainst = "3"
        draft.outcome = "win"
        #expect(draft.error == "The outcome doesn't match the score.")
        draft.outcome = "loss"
        #expect(draft.error == nil)
        draft.scoreFor = "3"
        draft.outcome = "win"
        #expect(draft.error == nil)
        draft.scoreFor = ""
        draft.outcome = "loss"
        #expect(draft.error == nil)
    }

    // MARK: - The wire

    @Test("An appearance decodes its matchup, and one from before matchups decodes as none")
    func decoding() throws {
        var object = Fixture.appearance(id: 9)
        let plain = try APIClient.decode(AppearanceDTO.self, from: Fixture.data(object))
        #expect(!Matchup(plain).isRecorded)

        object["round"] = "Final"
        object["opponent"] = "Crew Z"
        object["outcome"] = "win"
        object["scoreFor"] = 0
        let full = try APIClient.decode(AppearanceDTO.self, from: Fixture.data(object))
        #expect(Matchup(full) == Self.m(round: "Final", opponent: "Crew Z", outcome: "win", scoreFor: 0))
    }

    private static func service(_ server: FakeHTTPServer) -> ActivityService {
        ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("Matchups-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }

    private static func body(_ server: FakeHTTPServer, _ path: String) throws -> [String: Any] {
        let request = try #require(server.requests(for: path).first)
        return try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    private static func save(_ service: ActivityService, id: Int, matchup: Matchup) async throws {
        _ = try await service.saveAppearance(
            id: id, eventId: 5, entryId: 11, occurredAt: nil, notes: "",
            matchup: matchup, results: [], photoIds: []
        )
    }

    @Test("Saving sends a recorded matchup, leaving an absent score out")
    func createSendsMatchup() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveAppearance", respond: .json(Fixture.appearanceResponse(Fixture.appearance(id: 21))))

        try await Self.save(Self.service(server), id: 0, matchup: Self.m(round: " Final ", outcome: "win", scoreFor: 3))

        let matchup = try #require(try Self.body(server, "rpc/SaveAppearance")["matchup"] as? [String: Any])
        #expect(matchup["round"] as? String == "Final")
        #expect(matchup["outcome"] as? String == "win")
        #expect(matchup["scoreFor"] as? Int == 3)
        #expect(matchup["scoreAgainst"] == nil)
    }

    @Test("A new performance without a matchup sends none")
    func createWithoutMatchup() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveAppearance", respond: .json(Fixture.appearanceResponse(Fixture.appearance(id: 21))))

        try await Self.save(Self.service(server), id: 0, matchup: Self.m())

        #expect(try Self.body(server, "rpc/SaveAppearance")["matchup"] == nil)
    }

    @Test("An update sends an emptied matchup, which clears it")
    func updateMatchup() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveAppearance", respond: .json(Fixture.appearanceResponse(Fixture.appearance(id: 21))))

        try await Self.save(Self.service(server), id: 21, matchup: Self.m())

        let cleared = try #require(try Self.body(server, "rpc/SaveAppearance")["matchup"] as? [String: Any])
        #expect(cleared["outcome"] as? String == "")
    }
}
