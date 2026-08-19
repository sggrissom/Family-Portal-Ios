import Foundation
import Testing
@testable import Family_Portal_Ios

/// The activities payloads carry three shapes nothing else in this app does, and
/// each one has a wrong answer that looks like a right one.
@Suite("Activity DTO decoding")
struct ActivityDTODecodingTests {

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try APIClient.decode(T.self, from: Fixture.data(object))
    }

    // MARK: - Trap 1: the year-1 date

    /// The test the suite exists for. `Season.StartDate`, `Event.EndDate` and
    /// `Appearance.OccurredAt` are non-pointer `time.Time`, so "not known yet" —
    /// an explicitly normal state — marshals as `"0001-01-01T00:00:00Z"`, which
    /// the ISO8601 decoder accepts and hands back as a `Date` in the year 1.
    /// Formatting one prints *Jan 1, 1* wherever the web prints nothing.
    @Test("An unset date decodes and reads as unset, not as the year 1")
    func unsetDatesAreRecognized() throws {
        let season = try decode(SeasonDTO.self, Fixture.season(id: 41))

        #expect(season.startDate.isServerZero)
        #expect(season.endDate.isServerZero)
        #expect(season.startDate.serverDate == nil)
        #expect(ActivityDateText.range(from: season.startDate, to: season.endDate) == nil)
    }

    @Test("Every activities date field carries the unset check")
    func everyDateFieldCanBeUnset() throws {
        let event = try decode(ActivityEventDTO.self, Fixture.activityEvent(id: 5))
        let appearance = try decode(AppearanceDTO.self, Fixture.appearance(id: 9))
        let summary = try decode(SeasonSummaryDTO.self, Fixture.seasonSummary(id: 41))

        #expect(event.startDate.isServerZero)
        #expect(event.endDate.isServerZero)
        #expect(appearance.occurredAt.isServerZero)
        #expect(summary.startDate.isServerZero)
        #expect(summary.endDate.isServerZero)
    }

    @Test("A real date is not mistaken for the unset one")
    func realDatesSurvive() throws {
        let season = try decode(SeasonDTO.self, Fixture.season(
            id: 41,
            startDate: "2025-09-01T00:00:00Z",
            endDate: "2026-06-30T00:00:00Z"
        ))

        #expect(season.startDate.isServerZero == false)
        #expect(season.endDate.isServerZero == false)
        #expect(ActivityDateText.range(from: season.startDate, to: season.endDate) != nil)
    }

    /// A single-day competition has a start and no end, which is the common
    /// case — the range must collapse to the start rather than read as
    /// open-ended or print the year 1.
    @Test("An event with no end date reads as one day")
    func singleDayEventCollapses() throws {
        let event = try decode(ActivityEventDTO.self, Fixture.activityEvent(
            id: 5,
            startDate: "2026-03-14T00:00:00Z"
        ))

        let text = ActivityDateText.range(from: event.startDate, to: event.endDate)
        #expect(text != nil)
        #expect(text?.contains("–") == false)
    }

    /// `appearanceOrder` on the server falls back to the event's start date when
    /// `OccurredAt` is zero, and the row has to say the same thing.
    @Test("A performance with no time of its own falls back to the competition's date")
    func occurredFallsBackToEvent() throws {
        let appearance = try decode(AppearanceDTO.self, Fixture.appearance(id: 9))
        let event = try decode(EventSummaryDTO.self, Fixture.eventSummary(
            id: 5,
            startDate: "2026-03-14T00:00:00Z"
        ))

        #expect(ActivityDateText.occurred(appearance, at: event) != nil)
    }

    // MARK: - Trap 2: the omitted number

    /// `Rank`, `OutOf`, `Score` and `PersonId` are `*T` with `omitempty`. The
    /// backend packs them through `packOptionalInt` specifically so "no
    /// placement" stays distinguishable from "1st"; decoding an absent key as 0
    /// throws that away.
    @Test("Absent optional numbers stay nil rather than becoming zero")
    func absentNumbersStayNil() throws {
        let result = try decode(ActivityResultDTO.self, Fixture.activityResult(id: 1))

        #expect(result.rank == nil)
        #expect(result.outOf == nil)
        #expect(result.score == nil)
        #expect(result.personId == nil)
    }

    @Test("Present optional numbers decode")
    func presentNumbersDecode() throws {
        let result = try decode(ActivityResultDTO.self, Fixture.activityResult(
            id: 1,
            kind: "placement",
            label: "",
            rank: 1,
            outOf: 14,
            category: "Teen Small Group Lyrical",
            personId: 7
        ))

        #expect(result.rank == 1)
        #expect(result.outOf == 14)
        #expect(result.personId == 7)
        #expect(result.score == nil)
    }

    @Test("A score decodes as a Double, including a whole one")
    func scoreDecodes() throws {
        let result = try decode(ActivityResultDTO.self, Fixture.activityResult(
            id: 1, kind: "score", label: "", score: 92
        ))

        #expect(result.score == 92)
        #expect(ActivityResultText.score(result.score, label: result.label) == "92")
    }

    // MARK: - Trap 3: the empty collection

    @Test("Empty collections decode as empty")
    func emptyCollectionsDecode() throws {
        let response = try decode(GetPersonSeasonResponseDTO.self, Fixture.personSeason(personId: 7))

        #expect(response.personId == 7)
        #expect(response.seasonId == 0)
        #expect(response.seasons.isEmpty)
        #expect(response.entries.isEmpty)
        #expect(response.appearances.isEmpty)
    }

    /// Insurance rather than a fix: every list-bearing getter in
    /// backend/activity.go returns `[]T{}` today. If one ever returns a nil
    /// slice, an empty list is the cheap direction to be wrong in — a decode
    /// failure takes the whole screen down.
    @Test("An omitted collection decodes as empty rather than throwing")
    func omittedCollectionsDecode() throws {
        let response = try decode(
            GetEventDetailResponseDTO.self,
            [
                "event": Fixture.activityEvent(id: 5),
                "season": Fixture.seasonSummary(id: 41)
            ]
        )

        #expect(response.photoIds.isEmpty)
        #expect(response.appearances.isEmpty)
    }

    // MARK: - Whole payloads

    @Test("A season overview decodes with its parents shipped once each")
    func seasonOverviewDecodes() throws {
        let response = try decode(GetSeasonOverviewResponseDTO.self, Fixture.seasonOverview(
            activity: Fixture.activity(id: 1),
            season: Fixture.season(id: 41),
            events: [Fixture.activityEvent(id: 5), Fixture.activityEvent(id: 6, name: "Showstopper Orlando")],
            entries: [Fixture.entryView(Fixture.activityEntry(id: 11), personIds: [7, 8])],
            appearances: [
                Fixture.appearanceView(
                    Fixture.appearance(id: 21, eventId: 5, entryId: 11),
                    results: [Fixture.activityResult(id: 31, appearanceId: 21)],
                    photoIds: [101, 102]
                )
            ]
        ))

        #expect(response.activity.kind == "dance")
        #expect(response.events.count == 2)
        #expect(response.entries.first?.personIds == [7, 8])
        #expect(response.appearances.first?.results.first?.label == "High Gold")
        #expect(response.appearances.first?.photoIds == [101, 102])

        // The join the client does instead of the server repeating each parent
        // on every row.
        let byEvent = Dictionary(grouping: response.appearances) { $0.appearance.eventId }
        #expect(byEvent[5]?.count == 1)
        #expect(byEvent[6] == nil)
    }

    @Test("An appearance detail carries both parents")
    func appearanceDetailDecodes() throws {
        let response = try decode(GetEntryHistoryResponseDTO.self, Fixture.entryHistory(
            entry: Fixture.entryView(Fixture.activityEntry(id: 11), personIds: [7]),
            season: Fixture.seasonSummary(id: 41),
            appearances: [
                Fixture.appearanceDetail(
                    Fixture.appearance(id: 21, eventId: 5, entryId: 11),
                    results: [
                        Fixture.activityResult(id: 31, kind: "placement", label: "", rank: 1, outOf: 14),
                        Fixture.activityResult(id: 32, sortOrder: 1)
                    ],
                    entry: Fixture.activityEntry(id: 11),
                    event: Fixture.eventSummary(id: 5)
                )
            ]
        ))

        #expect(response.entry.entry.name == "Rise Up")
        #expect(response.season.kind == "dance")
        #expect(response.appearances.first?.event.name == "Nuvo Nashville")
        #expect(response.appearances.first?.entry.id == 11)
        #expect(response.appearances.first?.results.count == 2)
    }

    @Test("The vocabulary lists decode")
    func vocabularyDecodes() throws {
        let response = try decode(ListActivityVocabularyResponseDTO.self, Fixture.activityVocabulary(
            adjudications: ["Diamond", "High Gold"],
            hosts: ["Nuvo"]
        ))

        #expect(response.adjudications == ["Diamond", "High Gold"])
        #expect(response.hosts == ["Nuvo"])
        #expect(response.awards.isEmpty)
    }

    // MARK: - Result rendering

    @Test("A placement reads out of the fields it exists for")
    func placementText() {
        #expect(ActivityResultText.placement(rank: 1, outOf: 14, label: "") == "1st of 14")
        #expect(ActivityResultText.placement(rank: 2, outOf: nil, label: "") == "2nd")
        #expect(ActivityResultText.placement(rank: 3, outOf: 9, label: "Overall") == "3rd of 9 · Overall")
        // A rank the server would refuse on write, but which an older row can
        // hold: the label is still worth reading.
        #expect(ActivityResultText.placement(rank: nil, outOf: nil, label: "Overall") == "Overall")
    }

    @Test("A score drops the precision it never claimed")
    func scoreText() {
        #expect(ActivityResultText.score(92, label: "") == "92")
        #expect(ActivityResultText.score(92.5, label: "") == "92.5")
        #expect(ActivityResultText.score(nil, label: "Time") == "Time")
    }
}
