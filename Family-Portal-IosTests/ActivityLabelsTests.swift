import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Activity labels")
struct ActivityLabelsTests {

    @Test("Dance gets the dance vocabulary")
    func danceLabels() {
        let labels = ActivityLabels.forKind(ActivityKind.dance)

        #expect(labels.event == "Competition")
        #expect(labels.eventPlural == "Competitions")
        #expect(labels.entry == "Routine")
        #expect(labels.entryPlural == "Routines")
        #expect(labels.appearance == "Performance")
        #expect(labels.appearancePlural == "Performances")
        #expect(labels.roster == "Dancers")
    }

    @Test("Sport gets the sport vocabulary")
    func sportLabels() {
        let labels = ActivityLabels.forKind(ActivityKind.sport)

        #expect(labels.event == "Game")
        #expect(labels.entry == "Team")
        #expect(labels.appearance == "Game")
        #expect(labels.roster == "Players")
    }

    @Test("Generic gets the neutral vocabulary")
    func genericLabels() {
        #expect(ActivityLabels.forKind(ActivityKind.generic) == .generic)
        #expect(ActivityLabels.generic.event == "Event")
        #expect(ActivityLabels.generic.roster == "Members")
    }

    @Test("An unknown kind falls to generic")
    func unknownKindFallsBack() {
        #expect(ActivityLabels.forKind("swim") == .generic)
        #expect(ActivityLabels.forKind("") == .generic)
        #expect(ActivityLabels.forKind("Dance ") == .dance)
        #expect(ActivityLabels.forKind("SPORT") == .sport)
    }

    @Test("A season summary selects the pack where there is no activity")
    func seasonSummaryDrivesLabels() throws {
        let response = try APIClient.decode(
            GetEventDetailResponseDTO.self,
            from: Fixture.data(Fixture.eventDetail(
                event: Fixture.activityEvent(id: 5),
                season: Fixture.seasonSummary(id: 41, kind: "dance")
            ))
        )

        #expect(ActivityLabels.forKind(response.season.kind) == .dance)
    }

    @Test("A season summary with no kind still renders neutrally")
    func seasonSummaryWithoutKind() throws {
        let response = try APIClient.decode(
            GetEntryHistoryResponseDTO.self,
            from: Fixture.data(Fixture.entryHistory(
                entry: Fixture.entryView(Fixture.activityEntry(id: 11)),
                season: Fixture.seasonSummary(id: 41, kind: "")
            ))
        )

        #expect(ActivityLabels.forKind(response.season.kind) == .generic)
    }

    @Test("A kind names itself for a picker")
    func kindDisplayNames() {
        #expect(ActivityKind.displayName("dance") == "Dance")
        #expect(ActivityKind.displayName("sport") == "Sport")
        #expect(ActivityKind.displayName("generic") == "Other")
        #expect(ActivityKind.displayName("swim") == "Other")
    }
}
