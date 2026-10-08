import Foundation
import Testing
@testable import Family_Portal_Ios

/// Payloads shaped field for field on backend/dashboard.go, backend/same_age.go and `GetFamilyTimelineResponse`.
@Suite("Overview DTO decoding")
struct OverviewDTODecodingTests {

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try APIClient.decode(T.self, from: Fixture.data(object))
    }

    private func encodeObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    // MARK: - GetDashboard

    @Test("A full dashboard decodes")
    func dashboardDecodes() throws {
        let payload: [String: Any] = [
            "today": "2026-09-27",
            "people": [Fixture.person(id: 4, name: "Mia")],
            "relations": [Fixture.relation(id: 1, fromId: 2, toId: 4)],
            "nudges": [
                ["kind": "birthday", "key": "birthday:4:2026", "text": "Mia turns 10 tomorrow", "personId": 4, "count": 0],
                ["kind": "faces", "key": "faces:3", "text": "3 photos have faces to review", "personId": 0, "count": 3],
            ],
            "seasons": [[
                "season": Fixture.seasonSummary(id: 41),
                "activityName": "Dance",
                "event": Fixture.eventSummary(id: 9, startDate: "2026-09-27T00:00:00Z"),
                "eventTiming": "now",
                "canContribute": true,
                "canAddResults": true,
            ]],
            "onThisDay": [[
                "yearsAgo": 1,
                "photos": [Fixture.image(id: 50)],
                "milestones": [Fixture.milestone(id: 60, personId: 4)],
            ]],
            "recent": [
                "from": "2026-09-14",
                "photos": [["image": Fixture.image(id: 51), "people": [Fixture.person(id: 4)]]],
                "milestones": [],
                "growth": [Fixture.growthData(id: 70, personId: 4)],
            ],
        ]

        let dashboard = try decode(GetDashboardResponseDTO.self, payload)

        #expect(dashboard.today == "2026-09-27")
        #expect(dashboard.people.map(\.id) == [4])
        #expect(dashboard.relations.count == 1)
        #expect(dashboard.nudges.map(\.key) == ["birthday:4:2026", "faces:3"])
        #expect(dashboard.nudges[1].count == 3)
        #expect(dashboard.seasons.first?.event?.id == 9)
        #expect(dashboard.seasons.first?.eventTiming == "now")
        #expect(dashboard.seasons.first?.canContribute == true)
        #expect(dashboard.seasons.first?.canAddResults == true)
        #expect(dashboard.onThisDay.first?.photos.map(\.id) == [50])
        #expect(dashboard.recent.photos.first?.image.id == 51)
        #expect(dashboard.recent.growth.map(\.id) == [70])
    }

    @Test("Null lists and a season with no events decode as empty")
    func dashboardNulls() throws {
        let payload: [String: Any] = [
            "today": "2026-09-27",
            "people": NSNull(),
            "relations": NSNull(),
            "nudges": NSNull(),
            "seasons": [["season": Fixture.seasonSummary(id: 41), "activityName": "Dance", "event": NSNull(), "eventTiming": "", "canAddResults": false]],
            "onThisDay": NSNull(),
            "recent": ["from": "2026-09-14", "photos": NSNull(), "milestones": NSNull(), "growth": NSNull()],
        ]

        let dashboard = try decode(GetDashboardResponseDTO.self, payload)

        #expect(dashboard.people.isEmpty)
        #expect(dashboard.nudges.isEmpty)
        #expect(dashboard.seasons.first?.event == nil)
        #expect(dashboard.onThisDay.isEmpty)
        #expect(dashboard.recent.photos.isEmpty)
    }

    @Test("A view-only season says so, and a server too old to send the flag keeps the add buttons")
    func dashboardCanContribute() throws {
        func season(_ extra: [String: Any]) -> [String: Any] {
            ["season": Fixture.seasonSummary(id: 41), "activityName": "Dance", "event": NSNull(), "eventTiming": "", "canAddResults": false]
                .merging(extra) { _, new in new }
        }
        let payload: [String: Any] = [
            "today": "2026-09-27",
            "people": NSNull(),
            "relations": NSNull(),
            "nudges": NSNull(),
            "seasons": [season(["canContribute": false]), season([:])],
            "onThisDay": NSNull(),
            "recent": ["from": "2026-09-14", "photos": NSNull(), "milestones": NSNull(), "growth": NSNull()],
        ]

        let dashboard = try decode(GetDashboardResponseDTO.self, payload)

        #expect(dashboard.seasons.map(\.canContribute) == [false, true])
    }

    @Test("The request sends the device's day")
    func todayRequest() throws {
        let object = try encodeObject(TodayRequestDTO(today: "2026-09-27"))
        #expect(object["today"] as? String == "2026-09-27")
    }

    // MARK: - ListOpenEvents

    @Test("Open events decode, and null reads as none")
    func openEvents() throws {
        let events = try decode(ListOpenEventsResponseDTO.self, [
            "events": [["event": Fixture.eventSummary(id: 9), "activityName": "Dance"]],
        ])
        #expect(events.events.map(\.id) == [9])
        #expect(events.events.first?.activityName == "Dance")

        let none = try decode(ListOpenEventsResponseDTO.self, ["events": NSNull()])
        #expect(none.events.isEmpty)
    }

    // MARK: - GetSameAge

    @Test("Same-age rows decode with their nearest records")
    func sameAge() throws {
        let response = try decode(GetSameAgeResponseDTO.self, [
            "ageMonths": 40,
            "fromPersonId": 4,
            "maxAgeMonths": 120,
            "rows": [
                [
                    "person": Fixture.person(id: 4, name: "Mia"),
                    "date": "2019-12-04T00:00:00Z",
                    "height": Fixture.growthData(id: 70, personId: 4),
                    "weight": NSNull(),
                    "milestones": [Fixture.milestone(id: 60, personId: 4)],
                    "photoIds": [1, 2],
                ],
                [
                    "person": Fixture.person(id: 5, name: "Ben"),
                    "date": "2022-12-01T00:00:00Z",
                    "height": NSNull(),
                    "weight": NSNull(),
                    "milestones": [],
                    "photoIds": [],
                ],
            ],
        ])

        #expect(response.ageMonths == 40)
        #expect(response.maxAgeMonths == 120)
        #expect(response.rows.map(\.id) == [4, 5])
        #expect(response.rows[0].height?.id == 70)
        #expect(response.rows[0].weight == nil)
        #expect(response.rows[0].photoIds == [1, 2])
        #expect(response.rows[0].isEmpty == false)
        #expect(response.rows[1].isEmpty)
        // A server that predates discovery: unknown, not "no ages".
        #expect(response.availableAges == nil)
        #expect(response.portraitAges == nil)
        #expect(response.peopleCount == nil)
    }

    @Test("Discovered ages decode with their counts, and a null list is an empty one")
    func sameAgeDiscovery() throws {
        let response = try decode(GetSameAgeResponseDTO.self, [
            "ageMonths": 3,
            "fromPersonId": 4,
            "maxAgeMonths": 120,
            "peopleCount": 3,
            "availableAges": [["ageMonths": 0, "peopleCount": 2], ["ageMonths": 3, "peopleCount": 3]],
            "portraitAges": NSNull(),
            "rows": [],
        ])
        #expect(response.availableAges == [SameAgeOptionDTO(ageMonths: 0, peopleCount: 2), SameAgeOptionDTO(ageMonths: 3, peopleCount: 3)])
        #expect(response.portraitAges == [])
        #expect(response.peopleCount == 3)
    }

    @Test("A row with only a portrait has records")
    func portraitOnlyRow() throws {
        let row = try decode(SameAgeRowDTO.self, [
            "person": Fixture.person(id: 4),
            "date": "2019-12-04T00:00:00Z",
            "height": NSNull(),
            "weight": NSNull(),
            "milestones": [],
            "photoIds": [],
            "portraits": [["photoId": 9, "box": ["left": 0.3, "top": 0.2, "right": 0.7, "bottom": 0.6], "date": "2019-12-04T00:00:00Z", "ageMonths": 3, "year": 2019]],
        ])
        #expect(row.isEmpty == false)
    }

    @Test("A missing age is sent as null, and birth as zero")
    func sameAgeRequest() throws {
        let current = try encodeObject(GetSameAgeRequestDTO(ageMonths: nil, fromPersonId: 4, today: "2026-09-27"))
        #expect(current["ageMonths"] is NSNull)
        #expect(current["fromPersonId"] as? Int == 4)

        let birth = try encodeObject(GetSameAgeRequestDTO(ageMonths: 0, fromPersonId: 4, today: "2026-09-27"))
        #expect(birth["ageMonths"] as? Int == 0)
        // A strip's request is the body it always was.
        #expect(birth["includeAvailableAges"] == nil)
        #expect(birth["details"] == nil)
    }

    @Test("The browse page asks for discovery, and for Details only when it is showing")
    func sameAgeDiscoveryRequest() throws {
        let browse = try encodeObject(GetSameAgeRequestDTO(ageMonths: nil, fromPersonId: 0, today: "2026-09-27", includeAvailableAges: true, details: true))
        #expect(browse["includeAvailableAges"] as? Bool == true)
        #expect(browse["details"] as? Bool == true)
        #expect(browse["ageMonths"] is NSNull)
    }

    // MARK: - GetFamilyTimeline

    @Test("The timeline's years and appearances decode")
    func timelineAdditions() throws {
        let appearance = Fixture.appearanceDetail(
            Fixture.appearance(id: 9),
            results: [Fixture.activityResult(id: 1)],
            entry: Fixture.activityEntry(id: 1),
            event: Fixture.eventSummary(id: 3)
        )
        var payload = Fixture.timeline([])
        payload["years"] = [2026, 2025]
        payload["appearances"] = [["detail": appearance, "personIds": [4, 5]]]

        let timeline = try decode(GetFamilyTimelineResponseDTO.self, payload)

        #expect(timeline.years == [2026, 2025])
        #expect(timeline.appearances.first?.id == 9)
        #expect(timeline.appearances.first?.personIds == [4, 5])
    }

    @Test("A server predating years and appearances still pulls")
    func timelineWithoutAdditions() throws {
        let timeline = try decode(GetFamilyTimelineResponseDTO.self, Fixture.timeline([]))
        #expect(timeline.years.isEmpty)
        #expect(timeline.appearances.isEmpty)
    }

    @Test("An unwindowed timeline request is still an empty object")
    func timelineRequest() throws {
        #expect(try encodeObject(GetFamilyTimelineRequestDTO()).isEmpty)

        let windowed = try encodeObject(GetFamilyTimelineRequestDTO(from: "2026-01-01", to: "2026-12-31", includeActivities: true))
        #expect(windowed["from"] as? String == "2026-01-01")
        #expect(windowed["includeActivities"] as? Bool == true)
        #expect(windowed["skipPhotos"] == nil)
    }
}
