import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/history.test.ts, over store records. Year paging is the web's alone — the app renders every year — so those cases become the year list.
@MainActor
@Suite("History")
struct HistoryTests {

    private struct Family {
        let clara: Person
        let jake: Person
        let tagged: Milestone
        let old: Milestone
        let growth: GrowthData
        let shared: Photo
        let solo: Photo
        let untagged: Photo
        let appearance: TimelineAppearanceDTO

        init() throws {
            clara = DaySummaryTests.person("Clara", born: "2020-06-15T00:00:00Z")
            clara.remoteId = "1"
            jake = DaySummaryTests.person("Jake", born: "2020-06-15T00:00:00Z")
            jake.remoteId = "2"
            tagged = DaySummaryTests.milestone(clara, "2026-03-01T00:00:00Z")
            tagged.tagRemoteIds = [9]
            old = DaySummaryTests.milestone(clara, "2024-03-01T00:00:00Z")
            growth = DaySummaryTests.growth(clara, .height, 40, "2026-02-01T00:00:00Z")
            shared = DaySummaryTests.photo("2026-04-01T00:00:00Z", [clara, jake])
            shared.tagRemoteIds = [9]
            solo = DaySummaryTests.photo("2026-05-01T00:00:00Z", [clara])
            untagged = DaySummaryTests.photo("2026-05-02T00:00:00Z", [])
            appearance = try APIClient.decode(TimelineAppearanceDTO.self, from: Fixture.data([
                "detail": Fixture.appearanceDetail(
                    Fixture.appearance(id: 5, eventId: 6),
                    entry: Fixture.activityEntry(id: 1),
                    event: Fixture.eventSummary(id: 6, startDate: "2026-06-01T00:00:00Z")
                ),
                "personIds": [2],
            ]))
        }

        func view(_ filters: HistoryFilters? = nil) -> HistoryContent {
            History.view(
                people: [clara, jake],
                milestones: [tagged, old],
                growth: [growth],
                photos: [shared, solo, untagged],
                appearances: [appearance],
                filters: filters ?? HistoryFilters(),
                today: "2026-09-27"
            )
        }
    }

    @Test("Everything shows by default, and birthdays run from the first year")
    func everything() throws {
        let view = try Family().view()
        #expect(view.records.milestones.count == 2)
        #expect(view.records.growth.count == 1)
        #expect(view.records.appearances.count == 1)
        #expect(view.range?.from == "2024-01-01")
        #expect(view.range?.to == "2026-09-27")
    }

    @Test("A photo shows once, and only when someone is tagged in it")
    func photosOnce() throws {
        let family = try Family()
        #expect(family.view().records.photos.map(\.id) == [family.shared.id, family.solo.id])
    }

    @Test("Filtering to people keeps their records, events and birthdays")
    func people() throws {
        let family = try Family()
        var filters = HistoryFilters()
        filters.personIds = [family.jake.id]

        let view = family.view(filters)

        #expect(view.records.milestones.isEmpty)
        #expect(view.records.photos.map(\.id) == [family.shared.id])
        #expect(view.records.appearances.map(\.id) == [5])
        #expect(view.birthdayPeople.map(\.id) == [family.jake.id])
    }

    @Test("With tags, only tagged milestones and photos stay")
    func tags() throws {
        let family = try Family()
        var filters = HistoryFilters()
        filters.tagIds = [9]

        let view = family.view(filters)

        #expect(view.records.milestones.map(\.id) == [family.tagged.id])
        #expect(view.records.photos.map(\.id) == [family.shared.id])
        #expect(view.records.growth.isEmpty)
        #expect(view.records.appearances.isEmpty)
        #expect(view.range == nil)
    }

    @Test("Types switched off drop out")
    func types() throws {
        let family = try Family()
        var filters = HistoryFilters()
        filters.types = [.measurements]

        let view = family.view(filters)

        #expect(view.records.growth.count == 1)
        #expect(view.records.milestones.isEmpty)
        #expect(view.records.photos.isEmpty)
        #expect(view.range == nil)
    }

    @Test("A search finds milestones and nothing else")
    func search() throws {
        let family = try Family()
        family.old.descriptionText = "Rode a bike"
        var filters = HistoryFilters()
        filters.search = "bike"

        let view = family.view(filters)

        #expect(view.records.milestones.map(\.id) == [family.old.id])
        #expect(view.records.photos.isEmpty)
        #expect(Copy.history.resultsFor("bike", 1) == "1 milestone matching \"bike\"")
    }

    @Test("Years are listed newest first")
    func years() throws {
        let family = try Family()
        #expect(History.years(milestones: [family.tagged, family.old], growth: [family.growth], photos: [family.untagged]) == [2026, 2024])
    }
}
