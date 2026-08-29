import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Result validation")
struct ResultValidationTests {

    private static let roster = [7, 8]

    // MARK: - The five rules

    @Test("An adjudication needs a label")
    func adjudicationNeedsLabel() {
        var draft = ResultDraft(kind: .adjudication, label: "   ", category: "Teen Jazz")
        #expect(draft.validate(roster: Self.roster) == .labelRequired)

        draft.label = "High Gold"
        #expect(draft.validate(roster: Self.roster) == nil)
    }

    @Test("An award needs a label")
    func awardNeedsLabel() {
        var draft = ResultDraft(kind: .award, notes: "for the lift")
        #expect(draft.validate(roster: Self.roster) == .labelRequired)

        draft.label = "Judges' Choice"
        #expect(draft.validate(roster: Self.roster) == nil)
    }

    @Test("A placement needs a rank")
    func placementNeedsRank() {
        var draft = ResultDraft(kind: .placement, label: "Overall", category: "Teen Small Group")
        #expect(draft.validate(roster: Self.roster) == .rankRequired)

        draft.rankText = "1"
        #expect(draft.validate(roster: Self.roster) == nil)
    }

    @Test("An unparseable rank reads as no rank at all")
    func unparseableRankIsAbsent() {
        let draft = ResultDraft(kind: .placement, rankText: "first")
        #expect(draft.rank == nil)
        #expect(draft.validate(roster: Self.roster) == .rankRequired)
    }

    @Test("A rank must be at least 1")
    func rankMustBePositive() {
        #expect(ResultDraft(kind: .placement, rankText: "0").validate(roster: Self.roster) == .rankOutOfRange)
        #expect(ResultDraft(kind: .placement, rankText: "-3").validate(roster: Self.roster) == .rankOutOfRange)
        #expect(ResultDraft(kind: .placement, rankText: "1").validate(roster: Self.roster) == nil)
    }

    @Test("A rank cannot exceed the field it placed in")
    func rankCannotExceedField() {
        #expect(ResultDraft(kind: .placement, rankText: "15", outOfText: "14").validate(roster: Self.roster) == .rankOutOfRange)
        #expect(ResultDraft(kind: .placement, rankText: "14", outOfText: "14").validate(roster: Self.roster) == nil)
        // No field size given is not a violation — most sheets do not print one.
        #expect(ResultDraft(kind: .placement, rankText: "15").validate(roster: Self.roster) == nil)
    }

    @Test("A field size must itself be at least 1")
    func fieldSizeMustBePositive() {
        #expect(ResultDraft(kind: .placement, rankText: "1", outOfText: "0").validate(roster: Self.roster) == .rankOutOfRange)
    }

    @Test("A score result needs a score")
    func scoreNeedsScore() {
        var draft = ResultDraft(kind: .score, label: "Technical")
        #expect(draft.validate(roster: Self.roster) == .scoreRequired)

        draft.scoreText = "92.5"
        #expect(draft.validate(roster: Self.roster) == nil)
        #expect(draft.score == 92.5)
    }

    @Test("A result can only name someone on the entry's roster")
    func personMustBeOnRoster() {
        var draft = ResultDraft(kind: .award, label: "Judges' Choice", personId: 99)
        #expect(draft.validate(roster: Self.roster) == .personNotOnEntry)

        draft.personId = 8
        #expect(draft.validate(roster: Self.roster) == nil)

        draft.personId = nil
        #expect(draft.validate(roster: Self.roster) == nil)
    }

    @Test("A person id of zero names nobody")
    func zeroPersonIdNamesNobody() {
        #expect(ResultDraft(kind: .award, label: "Overall", personId: 0).validate(roster: Self.roster) == nil)
    }

    // MARK: - The sheet as a whole

    @Test("A sheet longer than one performance can hold is refused")
    func tooManyResults() {
        let rows = (0..<(ActivityFieldLimit.resultsPerAppearance + 1)).map {
            ResultDraft(kind: .adjudication, label: "Gold \($0)")
        }
        let failure = ResultSheet.validate(rows, roster: Self.roster)

        #expect(failure?.error == .tooManyResults)
        // Charged to the last row, which is the one that put the sheet over.
        #expect(failure?.row == rows.last?.id)
    }

    @Test("Exactly the maximum is allowed")
    func maximumIsAllowed() {
        let rows = (0..<ActivityFieldLimit.resultsPerAppearance).map {
            ResultDraft(kind: .adjudication, label: "Gold \($0)")
        }
        #expect(ResultSheet.validate(rows, roster: Self.roster) == nil)
    }

    @Test("Blank rows are dropped rather than refused")
    func blankRowsAreDropped() {
        let rows = [
            ResultDraft(kind: .adjudication, label: "High Gold"),
            ResultDraft(),
            ResultDraft(kind: .placement, rankText: "1", outOfText: "14")
        ]

        #expect(ResultSheet.validate(rows, roster: Self.roster) == nil)
        #expect(ResultSheet.inputs(rows).count == 2)
    }

    @Test("The failing row is named so the message can sit under it")
    func failureNamesItsRow() {
        let good = ResultDraft(kind: .adjudication, label: "High Gold")
        let bad = ResultDraft(kind: .placement, label: "Overall")
        let failure = ResultSheet.validate([good, bad], roster: Self.roster)

        #expect(failure?.row == bad.id)
        #expect(failure?.error == .rankRequired)
    }

    // MARK: - What reaches the wire

    @Test("Rows are sent in the order they are on screen")
    func orderIsPreserved() {
        let inputs = ResultSheet.inputs([
            ResultDraft(kind: .placement, rankText: "1", outOfText: "14"),
            ResultDraft(kind: .adjudication, label: "High Gold"),
            ResultDraft(kind: .award, label: "Judges' Choice")
        ])

        #expect(inputs.map(\.kind) == ["placement", "adjudication", "award"])
    }

    @Test("An empty number field sends nothing, not zero")
    func emptyNumbersAreAbsent() throws {
        let input = ResultDraft(kind: .adjudication, label: "High Gold").input()

        #expect(input.rank == nil)
        #expect(input.outOf == nil)
        #expect(input.score == nil)
        #expect(input.personId == nil)

        // And `encodeIfPresent` keeps them off the wire, which is what `omitempty` expects.
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(input)
        ) as? [String: Any]
        #expect(encoded?["rank"] == nil)
        #expect(encoded?["score"] == nil)
        #expect(encoded?["personId"] == nil)
    }

    @Test("Text is clamped to the caps the server would truncate at")
    func textIsClamped() {
        let input = ResultDraft(
            kind: .adjudication,
            label: String(repeating: "a", count: 300),
            category: String(repeating: "b", count: 300),
            notes: String(repeating: "c", count: 5000)
        ).input()

        #expect(input.label.count == ActivityFieldLimit.label.characters)
        #expect(input.category.count == ActivityFieldLimit.label.characters)
        #expect(input.notes.count == ActivityFieldLimit.notes.characters)
    }

    // MARK: - Round trip

    @Test("A saved sheet reopens as the same sheet")
    func roundTrip() throws {
        let stored = try APIClient.decode(
            [ActivityResultDTO].self,
            from: Fixture.data([
                Fixture.activityResult(id: 1, kind: "placement", label: "", rank: 1, outOf: 14, category: "Teen Jazz"),
                Fixture.activityResult(id: 2, kind: "adjudication", label: "High Gold", sortOrder: 1),
                Fixture.activityResult(id: 3, kind: "score", label: "", score: 92.5, sortOrder: 2),
                Fixture.activityResult(id: 4, kind: "award", label: "Judges' Choice", personId: 7, sortOrder: 3)
            ])
        )

        let drafts = stored.map(ResultDraft.init)
        #expect(ResultSheet.validate(drafts, roster: Self.roster) == nil)

        let inputs = ResultSheet.inputs(drafts)
        #expect(inputs.count == 4)
        #expect(inputs[0].rank == 1)
        #expect(inputs[0].outOf == 14)
        #expect(inputs[1].label == "High Gold")
        #expect(inputs[2].score == 92.5)
        #expect(inputs[3].personId == 7)
    }

    @Test("A score round-trips through the text field")
    func scoreRoundTrips() throws {
        let whole = try APIClient.decode(
            ActivityResultDTO.self,
            from: Fixture.data(Fixture.activityResult(id: 1, kind: "score", label: "", score: 92))
        )
        let fractional = try APIClient.decode(
            ActivityResultDTO.self,
            from: Fixture.data(Fixture.activityResult(id: 2, kind: "score", label: "", score: 92.5))
        )

        #expect(ResultDraft(whole).scoreText == "92")
        #expect(ResultDraft(whole).score == 92)
        #expect(ResultDraft(fractional).score == 92.5)
    }

    @Test("An unrecognized kind still opens as an editable row")
    func unknownKindSurvives() throws {
        let stored = try APIClient.decode(
            ActivityResultDTO.self,
            from: Fixture.data(Fixture.activityResult(id: 1, kind: "vibes", label: "Blown Speaker"))
        )
        let draft = ResultDraft(stored)

        #expect(draft.kind == .adjudication)
        #expect(draft.label == "Blown Speaker")
        #expect(draft.validate(roster: Self.roster) == nil)
    }
}
