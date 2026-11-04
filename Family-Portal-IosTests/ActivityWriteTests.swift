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
        return Calendar.current.date(from: components)!.localRecordDay()
    }

    // MARK: - Dates on the wire

    @Test("A record date is sent as its calendar day")
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

    // MARK: - Saving a performance

    private static func save(
        _ server: FakeHTTPServer,
        id: Int = 0,
        occurredAt: Date? = nil,
        notes: String = "",
        matchup: Matchup = Matchup(),
        results: [ResultInputDTO] = [],
        photoIds: [Int] = []
    ) async throws -> AppearanceViewDTO {
        try await service(server).saveAppearance(
            id: id, eventId: 5, entryId: 11, occurredAt: occurredAt, notes: notes,
            matchup: matchup, results: results, photoIds: photoIds
        )
    }

    @Test("A new performance names both parents and carries its results and photos in the same call")
    func saveNewAppearanceRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveAppearance", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21, eventId: 5, entryId: 11), photoIds: [102, 101])
        ))

        let inputs = ResultSheet.inputs([
            ResultDraft(kind: .placement, rankText: "1", outOfText: "14", category: "Teen Small Group Lyrical"),
            ResultDraft(kind: .adjudication, label: "High Gold"),
            ResultDraft()
        ])
        let appearance = try await Self.save(
            server,
            occurredAt: Self.day(year: 2026, month: 3, day: 14),
            notes: "  ballroom C  ",
            results: inputs,
            photoIds: [102, 101]
        )
        #expect(appearance.appearance.id == 21)

        let requests = server.requests(for: "rpc/SaveAppearance")
        #expect(requests.count == 1)
        let body = try Self.body(try #require(requests.first))
        #expect(body["id"] as? Int == 0)
        #expect(body["eventId"] as? Int == 5)
        #expect(body["entryId"] as? Int == 11)
        #expect(body["occurredAt"] as? String == "2026-03-14")
        #expect(body["notes"] as? String == "ballroom C")
        #expect(body["photoIds"] as? [Int] == [102, 101])
        // Nothing recorded head-to-head on a new performance: left out rather than sent empty.
        #expect(body["matchup"] == nil)

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

    @Test("An update with nothing left sends empty sets and an empty matchup, which clear them")
    func saveExistingAppearanceClears() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SaveAppearance", respond: .json(
            Fixture.appearanceResponse(Fixture.appearance(id: 21))
        ))

        _ = try await Self.save(server, id: 21)

        let body = try Self.body(try #require(server.requests(for: "rpc/SaveAppearance").first))
        #expect(body["id"] as? Int == 21)
        #expect(body["occurredAt"] == nil)
        #expect((body["results"] as? [[String: Any]])?.isEmpty == true)
        #expect((body["photoIds"] as? [Int])?.isEmpty == true)
        #expect(body["matchup"] != nil)
    }

    @Test("A refused performance reaches the user in the backend's own words")
    func saveAppearanceRefusal() async {
        let sentence = "A result can only name someone on this entry's roster"
        let server = FakeHTTPServer()
        server.route("rpc/SaveAppearance", respond: .status(400, message: sentence))

        do {
            _ = try await Self.save(
                server,
                results: [ResultDraft(kind: .award, label: "Judges' Choice", personId: 99).input()]
            )
            Issue.record("Expected the write to be refused")
        } catch {
            #expect(error.localizedDescription == sentence)
        }
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

    @Test("An activity's end before its start is caught; an unknown end never is")
    func activityDatesOutOfOrder() {
        var start = ActivityDateField()
        start.isSet = true
        start.day = Self.day(year: 2026, month: 3, day: 14)
        var end = ActivityDateField()
        #expect(!ActivityDateField.endsBeforeStart(start, end))
        end.isSet = true
        end.day = Self.day(year: 2026, month: 3, day: 13)
        #expect(ActivityDateField.endsBeforeStart(start, end))
        end.day = Self.day(year: 2026, month: 3, day: 14)
        #expect(!ActivityDateField.endsBeforeStart(start, end))
    }

    @Test("A new dance program offers the common adjudications; a family's own replace them")
    func quickLabels() {
        #expect(ActivityResults.quickLabels(kind: "dance", used: ["Diamond", "Elite"]) == ["Diamond", "Elite"])
        #expect(ActivityResults.quickLabels(kind: "dance", used: []) == ["Platinum", "High Gold", "Gold"])
        #expect(ActivityResults.quickLabels(kind: "sport", used: []) == [])
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
