import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Activity snapshot cache")
struct ActivitySnapshotCacheTests {

    private static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivitySnapshots-\(UUID().uuidString)", isDirectory: true)
    }

    private static func seasonOverview(eventName: String = "Nuvo Nashville") -> [String: Any] {
        Fixture.seasonOverview(
            activity: Fixture.activity(id: 1),
            season: Fixture.season(id: 41),
            events: [Fixture.activityEvent(id: 5, name: eventName)],
            entries: [Fixture.entryView(Fixture.activityEntry(id: 11), personIds: [7])],
            appearances: [Fixture.appearanceView(Fixture.appearance(id: 21, eventId: 5, entryId: 11))]
        )
    }

    // MARK: - Reading offline

    @Test("A screen opened once still renders with no signal")
    func cachedPayloadRendersOffline() async {
        let server = FakeHTTPServer()
        server.routeSequence("rpc/GetSeasonOverview", [
            .json(Self.seasonOverview()),
            .offline()
        ])
        let service = ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(directory: Self.scratchDirectory())
        )

        let first = ActivityScreenState<GetSeasonOverviewResponseDTO>()
        await first.load(service.seasonOverview(seasonId: 41))

        #expect(first.value?.events.first?.name == "Nuvo Nashville")
        #expect(first.isShowingCached == false)
        #expect(first.error == nil)

        let second = ActivityScreenState<GetSeasonOverviewResponseDTO>()
        await second.load(service.seasonOverview(seasonId: 41))

        #expect(second.value?.events.first?.name == "Nuvo Nashville")
        #expect(second.isShowingCached)
        #expect(second.error == nil)
    }

    @Test("A failed refresh keeps what is already on screen")
    func failedRefreshKeepsTheCache() async {
        let server = FakeHTTPServer()
        server.routeSequence("rpc/GetSeasonOverview", [
            .json(Self.seasonOverview()),
            .status(500, message: "boom")
        ])
        let service = ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(directory: Self.scratchDirectory())
        )

        let state = ActivityScreenState<GetSeasonOverviewResponseDTO>()
        await state.load(service.seasonOverview(seasonId: 41))
        await state.reload()

        #expect(state.value?.events.first?.name == "Nuvo Nashville")
        #expect(state.isShowingCached)
        #expect(state.error == nil)
    }

    @Test("A cache miss is not the same as no data")
    func cacheMissIsNotEmpty() async {
        let server = FakeHTTPServer()
        server.route("rpc/GetSeasonOverview", respond: .offline())
        let service = ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(directory: Self.scratchDirectory())
        )

        let state = ActivityScreenState<GetSeasonOverviewResponseDTO>()
        await state.load(service.seasonOverview(seasonId: 41))

        #expect(state.value == nil)
        #expect(state.error != nil)
    }

    // MARK: - Keys

    @Test("Two reads of the same proc keep separate payloads")
    func keysIncludeTheirArguments() async {
        let cache = ActivitySnapshotCache(directory: Self.scratchDirectory())

        await cache.store(Fixture.data(Self.seasonOverview(eventName: "Nuvo Nashville")),
                          key: ActivitySnapshotKey(.getSeasonOverview, 41))
        await cache.store(Fixture.data(Self.seasonOverview(eventName: "Showstopper Orlando")),
                          key: ActivitySnapshotKey(.getSeasonOverview, 42))

        let first = await cache.load(GetSeasonOverviewResponseDTO.self,
                                     key: ActivitySnapshotKey(.getSeasonOverview, 41))
        let second = await cache.load(GetSeasonOverviewResponseDTO.self,
                                      key: ActivitySnapshotKey(.getSeasonOverview, 42))

        #expect(first?.value.events.first?.name == "Nuvo Nashville")
        #expect(second?.value.events.first?.name == "Showstopper Orlando")
    }

    @Test("A key that names no file is never written")
    func keysStayInsideTheDirectory() {
        let key = ActivitySnapshotKey(.getPersonSeason, 7, 0)

        #expect(key.rawValue == "GetPersonSeason-7-0")
        #expect(key.fileName == "GetPersonSeason-7-0.json")
        #expect(key.fileName.contains("/") == false)
    }

    @Test("An unreadable payload is dropped rather than kept")
    func unreadablePayloadIsDropped() async {
        let cache = ActivitySnapshotCache(directory: Self.scratchDirectory())
        let key = ActivitySnapshotKey(.getSeasonOverview, 41)

        await cache.store(Data("not json".utf8), key: key)
        let unreadable = await cache.load(GetSeasonOverviewResponseDTO.self, key: key)
        #expect(unreadable == nil)

        await cache.store(Fixture.data(Self.seasonOverview()), key: key)
        let readable = await cache.load(GetSeasonOverviewResponseDTO.self, key: key)
        #expect(readable != nil)
    }

    // MARK: - Erasing

    @Test("A full local reset drops every cached read")
    func fullResetClearsTheCache() async throws {
        let cache = ActivitySnapshotCache(directory: Self.scratchDirectory())
        let key = ActivitySnapshotKey(.getPersonSeason, 7, 0)
        await cache.store(Fixture.data(Fixture.personSeason(personId: 7)), key: key)
        let beforeReset = await cache.load(GetPersonSeasonResponseDTO.self, key: key)
        #expect(beforeReset != nil)

        await LocalDataReset.erase(
            .everything,
            context: try TestStore.makeContext(),
            syncQueue: TestStore.makeQueue(),
            activityCache: cache,
            photoCache: PhotoImageCache(session: URLSession(configuration: .ephemeral))
        )

        let afterReset = await cache.load(GetPersonSeasonResponseDTO.self, key: key)
        #expect(afterReset == nil)
    }

    @Test("A chat-only reset leaves the cache alone")
    func chatOnlyResetKeepsTheCache() async throws {
        let cache = ActivitySnapshotCache(directory: Self.scratchDirectory())
        let key = ActivitySnapshotKey(.getPersonSeason, 7, 0)
        await cache.store(Fixture.data(Fixture.personSeason(personId: 7)), key: key)

        await LocalDataReset.erase(
            .chatOnly,
            context: try TestStore.makeContext(),
            syncQueue: TestStore.makeQueue(),
            activityCache: cache,
            photoCache: PhotoImageCache(session: URLSession(configuration: .ephemeral))
        )

        let survivor = await cache.load(GetPersonSeasonResponseDTO.self, key: key)
        #expect(survivor != nil)
    }

    // MARK: - What reaches the wire

    @Test("A person's season is asked for by server id, with every season")
    func personSeasonRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetPersonSeason", respond: .json(Fixture.personSeason(personId: 7)))
        let service = ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(directory: Self.scratchDirectory())
        )

        let state = ActivityScreenState<GetPersonSeasonResponseDTO>()
        await state.load(service.personSeason(personId: 7))

        let request = try #require(server.requests(for: "rpc/GetPersonSeason").first)
        let json = try JSONSerialization.jsonObject(with: request.body)
        let body = try #require(json as? [String: Any])
        #expect(body["personId"] as? Int == 7)
        #expect(body["seasonId"] as? Int == 0)
    }

    @Test("Listing activities defaults to the primary family")
    func listActivitiesRequestShape() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/ListActivities", respond: .json(Fixture.listActivities([Fixture.activity(id: 1)])))
        let service = ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(directory: Self.scratchDirectory())
        )

        let state = ActivityScreenState<ListActivitiesResponseDTO>()
        await state.load(service.activities())

        #expect(state.value?.activities.count == 1)
        let request = try #require(server.requests(for: "rpc/ListActivities").first)
        let json = try JSONSerialization.jsonObject(with: request.body)
        let body = try #require(json as? [String: Any])
        #expect(body["familyId"] as? Int == 0)
    }
}
