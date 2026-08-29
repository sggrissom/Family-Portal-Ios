import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Activity writes")
struct ActivityWriteTests {

    private static func service(_ server: FakeHTTPServer) -> ActivityService {
        ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("ActivityWrites-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }

    private static func body(_ request: FakeHTTPServer.Request) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: request.body)
        return try #require(json as? [String: Any])
    }

    private static func day(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    // MARK: - Dates on the wire

    @Test("A date is sent as the calendar day the user picked")
    func requestDateFormat() {
        #expect(ServerDateFormat.requestString(Self.day(year: 2026, month: 3, day: 14)) == "2026-03-14")
        #expect(ServerDateFormat.requestString(nil) == nil)
    }

    @Test("The server's zero time is sent as no date at all")
    func serverZeroIsNotADate() {
        let zero = Date(timeIntervalSince1970: -62_135_596_800)
        #expect(zero.isServerZero)
        #expect(ServerDateFormat.requestString(zero) == nil)
    }

    // MARK: - Creating

    @Test("Filing a routine at a competition names both parents")
    func createAppearanceRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/CreateAppearance", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21, eventId: 5, entryId: 11))
        ))

        let appearance = try await Self.service(server).createAppearance(
            eventId: 5,
            entryId: 11,
            occurredAt: Self.day(year: 2026, month: 3, day: 14),
            notes: "  ballroom C  "
        )

        #expect(appearance.appearance.id == 21)

        let body = try Self.body(try #require(server.requests(for: "rpc/CreateAppearance").first))
        #expect(body["eventId"] as? Int == 5)
        #expect(body["entryId"] as? Int == 11)
        #expect(body["occurredAt"] as? String == "2026-03-14")
        #expect(body["notes"] as? String == "ballroom C")
    }

    @Test("A performance with no known day omits the date")
    func createAppearanceWithoutDate() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/CreateAppearance", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21))
        ))

        _ = try await Self.service(server).createAppearance(
            eventId: 5, entryId: 11, occurredAt: nil, notes: ""
        )

        let body = try Self.body(try #require(server.requests(for: "rpc/CreateAppearance").first))
        #expect(body["occurredAt"] == nil)
    }

    @Test("An entry from another season is refused in the backend's own words")
    func createAppearanceRefusal() async {
        let sentence = "That entry is not in the same season as this competition"
        let server = FakeHTTPServer()
        server.route("rpc/CreateAppearance", respond: .status(400, message: sentence))

        do {
            _ = try await Self.service(server).createAppearance(
                eventId: 5, entryId: 11, occurredAt: nil, notes: ""
            )
            Issue.record("Expected the write to be refused")
        } catch {
            #expect(error.localizedDescription == sentence)
        }
    }

    // MARK: - Updating

    @Test("An update always sends the date it is showing")
    func updateAppearanceSendsItsDate() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/UpdateAppearance", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21))
        ))

        _ = try await Self.service(server).updateAppearance(
            id: 21,
            occurredAt: Self.day(year: 2026, month: 3, day: 15),
            notes: "second call"
        )

        let body = try Self.body(try #require(server.requests(for: "rpc/UpdateAppearance").first))
        #expect(body["id"] as? Int == 21)
        #expect(body["occurredAt"] as? String == "2026-03-15")
        #expect(body["notes"] as? String == "second call")
    }

    @Test("Clearing the date omits the key, which is what clears it")
    func updateAppearanceClearsItsDate() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/UpdateAppearance", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21))
        ))

        _ = try await Self.service(server).updateAppearance(id: 21, occurredAt: nil, notes: "")

        let body = try Self.body(try #require(server.requests(for: "rpc/UpdateAppearance").first))
        #expect(body.keys.contains("id"))
        #expect(body["occurredAt"] == nil)
    }

    @Test("The date field reads a server zero as not set")
    func dateFieldReadsServerZero() {
        let unset = ActivityDateField(Date(timeIntervalSince1970: -62_135_596_800))
        #expect(unset.isSet == false)
        #expect(unset.date == nil)

        var known = ActivityDateField(Self.day(year: 2026, month: 3, day: 14))
        #expect(known.isSet)
        #expect(known.date != nil)

        known.isSet = false
        #expect(known.date == nil)
    }

    // MARK: - Deleting

    @Test("Deleting a performance asks by id")
    func deleteAppearanceRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/DeleteAppearance", respond: .json(Fixture.activityDeleteSuccess()))

        try await Self.service(server).deleteAppearance(id: 21)

        let body = try Self.body(try #require(server.requests(for: "rpc/DeleteAppearance").first))
        #expect(body["id"] as? Int == 21)
    }

    // MARK: - Results

    @Test("Saving a results sheet sends the whole set in order")
    func setAppearanceResultsRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SetAppearanceResults", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21))
        ))

        let inputs = ResultSheet.inputs([
            ResultDraft(kind: .placement, rankText: "1", outOfText: "14", category: "Teen Small Group Lyrical"),
            ResultDraft(kind: .adjudication, label: "High Gold"),
            ResultDraft()
        ])
        _ = try await Self.service(server).setAppearanceResults(appearanceId: 21, results: inputs)

        let body = try Self.body(try #require(server.requests(for: "rpc/SetAppearanceResults").first))
        #expect(body["appearanceId"] as? Int == 21)

        let results = try #require(body["results"] as? [[String: Any]])
        #expect(results.count == 2)
        #expect(results[0]["kind"] as? String == "placement")
        #expect(results[0]["rank"] as? Int == 1)
        #expect(results[0]["outOf"] as? Int == 14)
        #expect(results[1]["kind"] as? String == "adjudication")
        #expect(results[0]["sortOrder"] == nil)
        #expect(results[1]["rank"] == nil)
        #expect(results[1]["score"] == nil)
        #expect(results[1]["personId"] == nil)
    }

    @Test("Saving no results clears the sheet")
    func setAppearanceResultsCanClear() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SetAppearanceResults", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21))
        ))

        _ = try await Self.service(server).setAppearanceResults(appearanceId: 21, results: [])

        let body = try Self.body(try #require(server.requests(for: "rpc/SetAppearanceResults").first))
        #expect((body["results"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("A refused results sheet reaches the user as its own sentence")
    func setAppearanceResultsRefusal() async {
        let sentence = "A result can only name someone on this entry's roster"
        let server = FakeHTTPServer()
        server.route("rpc/SetAppearanceResults", respond: .status(400, message: sentence))

        do {
            _ = try await Self.service(server).setAppearanceResults(
                appearanceId: 21,
                results: [ResultDraft(kind: .award, label: "Judges' Choice", personId: 99).input()]
            )
            Issue.record("Expected the write to be refused")
        } catch {
            #expect(error.localizedDescription == sentence)
        }
    }

    // MARK: - Photos

    @Test("Attaching photos sends the whole set, in order")
    func setAppearancePhotosRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SetAppearancePhotos", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21), photoIds: [102, 101])
        ))

        let appearance = try await Self.service(server).setAppearancePhotos(
            appearanceId: 21, photoIds: [102, 101]
        )
        #expect(appearance.photoIds == [102, 101])

        let body = try Self.body(try #require(server.requests(for: "rpc/SetAppearancePhotos").first))
        #expect(body["appearanceId"] as? Int == 21)
        #expect(body["photoIds"] as? [Int] == [102, 101])
    }

    @Test("Detaching every photo sends an empty set")
    func setAppearancePhotosCanClear() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SetAppearancePhotos", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21))
        ))

        _ = try await Self.service(server).setAppearancePhotos(appearanceId: 21, photoIds: [])

        let body = try Self.body(try #require(server.requests(for: "rpc/SetAppearancePhotos").first))
        #expect((body["photoIds"] as? [Int])?.isEmpty == true)
    }

    // MARK: - Vocabulary

    @Test("The vocabulary is asked for by activity and cached with the reads")
    func vocabularyRequestShape() async throws {
        let server = FakeHTTPServer()
        server.routeSequence("rpc/ListActivityVocabulary", [
            .json(Fixture.activityVocabulary(activityId: 1, adjudications: ["Diamond", "High Gold"])),
            .offline()
        ])
        let service = Self.service(server)

        let first = ActivityScreenState<ListActivityVocabularyResponseDTO>()
        await first.load(service.vocabulary(activityId: 1))
        #expect(first.value?.adjudications == ["Diamond", "High Gold"])

        let offline = ActivityScreenState<ListActivityVocabularyResponseDTO>()
        await offline.load(service.vocabulary(activityId: 1))
        #expect(offline.value?.adjudications == ["Diamond", "High Gold"])
        #expect(offline.isShowingCached)

        let body = try Self.body(try #require(server.requests(for: "rpc/ListActivityVocabulary").first))
        #expect(body["activityId"] as? Int == 1)
    }
}
