import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Activity structure writes")
struct ActivityStructureWriteTests {

    private static func service(_ server: FakeHTTPServer) -> ActivityService {
        ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("ActivityStructure-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }

    private static func body(_ request: FakeHTTPServer.Request) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: request.body)
        return try #require(json as? [String: Any])
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    // MARK: - Activity

    @Test("Creating a program defaults to the primary family")
    func createActivityRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/CreateActivity", respond: .json(
            Fixture.activityResponse(Fixture.activity(id: 1))
        ))

        let activity = try await Self.service(server).createActivity(name: "  Dance  ", kind: "dance")
        #expect(activity.id == 1)

        let body = try Self.body(try #require(server.requests(for: "rpc/CreateActivity").first))
        #expect(body["familyId"] as? Int == 0)
        #expect(body["name"] as? String == "Dance")
        #expect(body["kind"] as? String == "dance")
    }

    @Test("A name longer than the cap is clamped before it is sent")
    func nameIsClamped() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/CreateActivity", respond: .json(
            Fixture.activityResponse(Fixture.activity(id: 1))
        ))

        _ = try await Self.service(server).createActivity(
            name: String(repeating: "a", count: 400), kind: "dance"
        )

        let body = try Self.body(try #require(server.requests(for: "rpc/CreateActivity").first))
        #expect((body["name"] as? String)?.count == ActivityFieldLimit.name.characters)
    }

    @Test("Deleting a program asks by id")
    func deleteActivityRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/DeleteActivity", respond: .json(Fixture.activityDeleteSuccess()))

        try await Self.service(server).deleteActivity(id: 1)

        let body = try Self.body(try #require(server.requests(for: "rpc/DeleteActivity").first))
        #expect(body["id"] as? Int == 1)
    }

    // MARK: - Season

    @Test("Creating a season names its program and sends both dates")
    func createSeasonRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/CreateSeason", respond: .json(
            Fixture.seasonResponse(Fixture.season(id: 41))
        ))

        _ = try await Self.service(server).createSeason(
            activityId: 1,
            name: "2025-26 Competition Season",
            startDate: Self.day(2025, 9, 1),
            endDate: Self.day(2026, 6, 30),
            notes: ""
        )

        let body = try Self.body(try #require(server.requests(for: "rpc/CreateSeason").first))
        #expect(body["activityId"] as? Int == 1)
        #expect(body["startDate"] as? String == "2025-09-01")
        #expect(body["endDate"] as? String == "2026-06-30")
    }

    @Test("Updating a season sends the dates it is showing")
    func updateSeasonSendsBothDates() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/UpdateSeason", respond: .json(
            Fixture.seasonResponse(Fixture.season(id: 41))
        ))

        _ = try await Self.service(server).updateSeason(
            id: 41, name: "2025-26", startDate: Self.day(2025, 9, 1), endDate: nil, notes: "x"
        )

        let body = try Self.body(try #require(server.requests(for: "rpc/UpdateSeason").first))
        #expect(body["startDate"] as? String == "2025-09-01")
        #expect(body["endDate"] == nil)
    }

    @Test("A season with no name is refused in the backend's own words")
    func seasonNameRequired() async {
        let server = FakeHTTPServer()
        server.route("rpc/CreateSeason", respond: .status(400, message: "A name is required"))

        do {
            _ = try await Self.service(server).createSeason(
                activityId: 1, name: "   ", startDate: nil, endDate: nil, notes: ""
            )
            Issue.record("Expected the write to be refused")
        } catch {
            #expect(error.localizedDescription == "A name is required")
        }
    }

    // MARK: - Competition

    @Test("Creating a competition names its season and carries its free text")
    func createEventRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/CreateEvent", respond: .json(
            Fixture.activityEventResponse(Fixture.activityEvent(id: 5))
        ))

        _ = try await Self.service(server).createEvent(
            seasonId: 41,
            name: "Nuvo Nashville",
            host: "Nuvo",
            location: "Nashville, TN",
            startDate: Self.day(2026, 3, 14),
            endDate: nil,
            notes: ""
        )

        let body = try Self.body(try #require(server.requests(for: "rpc/CreateEvent").first))
        #expect(body["seasonId"] as? Int == 41)
        #expect(body["host"] as? String == "Nuvo")
        #expect(body["location"] as? String == "Nashville, TN")
        #expect(body["startDate"] as? String == "2026-03-14")
        #expect(body["endDate"] == nil)
    }

    @Test("Deleting a competition asks by id")
    func deleteEventRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/DeleteEvent", respond: .json(Fixture.activityDeleteSuccess()))

        try await Self.service(server).deleteEvent(id: 5)

        let body = try Self.body(try #require(server.requests(for: "rpc/DeleteEvent").first))
        #expect(body["id"] as? Int == 5)
    }

    // MARK: - Routine and roster

    @Test("Creating a routine can set its roster in the same call")
    func createEntryCarriesItsRoster() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/CreateEntry", respond: .json(
            Fixture.activityEntryResponse(Fixture.activityEntry(id: 11), personIds: [7, 8])
        ))

        let entry = try await Self.service(server).createEntry(
            seasonId: 41, name: "Rise Up", format: "group", style: "Lyrical",
            division: "Teen", level: "Elite", notes: "", personIds: [7, 8]
        )
        #expect(entry.personIds == [7, 8])

        let body = try Self.body(try #require(server.requests(for: "rpc/CreateEntry").first))
        #expect(body["seasonId"] as? Int == 41)
        #expect(body["personIds"] as? [Int] == [7, 8])
        #expect(body["style"] as? String == "Lyrical")
    }

    @Test("Updating a routine leaves the roster alone")
    func updateEntryOmitsTheRoster() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/UpdateEntry", respond: .json(
            Fixture.activityEntryResponse(Fixture.activityEntry(id: 11), personIds: [7, 8])
        ))

        _ = try await Self.service(server).updateEntry(
            id: 11, name: "Rise Up", format: "group", style: "Jazz",
            division: "Teen", level: "Elite", notes: ""
        )

        let body = try Self.body(try #require(server.requests(for: "rpc/UpdateEntry").first))
        #expect(body["id"] as? Int == 11)
        #expect(body["personIds"] == nil)
    }

    @Test("Setting a roster replaces the whole set, in order")
    func setEntryRosterRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SetEntryRoster", respond: .json(
            Fixture.activityEntryResponse(Fixture.activityEntry(id: 11), personIds: [8, 7])
        ))

        _ = try await Self.service(server).setEntryRoster(entryId: 11, personIds: [8, 7])

        let body = try Self.body(try #require(server.requests(for: "rpc/SetEntryRoster").first))
        #expect(body["entryId"] as? Int == 11)
        #expect(body["personIds"] as? [Int] == [8, 7])
    }

    @Test("Emptying a roster sends an empty set")
    func setEntryRosterCanClear() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SetEntryRoster", respond: .json(
            Fixture.activityEntryResponse(Fixture.activityEntry(id: 11))
        ))

        _ = try await Self.service(server).setEntryRoster(entryId: 11, personIds: [])

        let body = try Self.body(try #require(server.requests(for: "rpc/SetEntryRoster").first))
        #expect((body["personIds"] as? [Int])?.isEmpty == true)
    }

    @Test("A person off the family's roster is refused in the backend's own words")
    func rosterRefusal() async {
        let sentence = "That person is not on this family's roster"
        let server = FakeHTTPServer()
        server.route("rpc/SetEntryRoster", respond: .status(400, message: sentence))

        do {
            _ = try await Self.service(server).setEntryRoster(entryId: 11, personIds: [999])
            Issue.record("Expected the write to be refused")
        } catch {
            #expect(error.localizedDescription == sentence)
        }
    }

    @Test("Deleting a routine asks by id")
    func deleteEntryRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/DeleteEntry", respond: .json(Fixture.activityDeleteSuccess()))

        try await Self.service(server).deleteEntry(id: 11)

        let body = try Self.body(try #require(server.requests(for: "rpc/DeleteEntry").first))
        #expect(body["id"] as? Int == 11)
    }

    // MARK: - Competition photos

    @Test("Competition photos are a whole set, and the response carries the ids back")
    func setEventPhotosRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SetEventPhotos", respond: .json(
            Fixture.eventPhotosResponse(eventId: 5, photoIds: [201, 202])
        ))

        let photoIds = try await Self.service(server).setEventPhotos(eventId: 5, photoIds: [201, 202])
        #expect(photoIds == [201, 202])

        let body = try Self.body(try #require(server.requests(for: "rpc/SetEventPhotos").first))
        #expect(body["eventId"] as? Int == 5)
        #expect(body["photoIds"] as? [Int] == [201, 202])
    }

    @Test("An event-photos response with no ids decodes as empty")
    func eventPhotosResponseTolerance() throws {
        let response = try APIClient.decode(
            SetEventPhotosResponseDTO.self,
            from: Fixture.data(["eventId": 5])
        )
        #expect(response.eventId == 5)
        #expect(response.photoIds.isEmpty)
    }
}
