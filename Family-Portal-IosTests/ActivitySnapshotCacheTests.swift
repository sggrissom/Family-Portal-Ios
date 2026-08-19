import Foundation
import Testing
@testable import Family_Portal_Ios

/// Activities are read online and cached to disk, rather than living in
/// SwiftData behind `SyncQueue`. The venue has no signal, and arriving at a
/// competition to a blank app is the failure the offline story exists to
/// prevent — but reading stale data is safe in a way that replaying stale writes
/// is not, so only the reads get this treatment.
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

        // The same screen again, on a device that can no longer reach the
        // server: it renders, and it says it is showing what it last saw.
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
        // Not an alert: an error over data the reader can still see would
        // interrupt them to tell them something they can already tell.
        #expect(state.error == nil)
    }

    /// The distinction the chat history bug was made of. Offline with nothing
    /// saved and "this family has none of these" are different screens.
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

    /// A key that dropped its arguments would have one season's payload
    /// answering for another's.
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

    /// A payload this build can no longer read is worse than none: it would
    /// fail on every open until the network happened to be up.
    @Test("An unreadable payload is dropped rather than kept")
    func unreadablePayloadIsDropped() async {
        let cache = ActivitySnapshotCache(directory: Self.scratchDirectory())
        let key = ActivitySnapshotKey(.getSeasonOverview, 41)

        await cache.store(Data("not json".utf8), key: key)
        let unreadable = await cache.load(GetSeasonOverviewResponseDTO.self, key: key)
        #expect(unreadable == nil)

        // And the next good payload lands normally.
        await cache.store(Fixture.data(Self.seasonOverview()), key: key)
        let readable = await cache.load(GetSeasonOverviewResponseDTO.self, key: key)
        #expect(readable != nil)
    }

    // MARK: - Erasing

    /// The same problem `LocalAccountOwner` exists for. Nothing in the pull
    /// reconciles this cache — `GetFamilyTimeline` does not carry activities —
    /// so a device that changes hands would otherwise show the previous
    /// account's season.
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
            activityCache: cache
        )

        let afterReset = await cache.load(GetPersonSeasonResponseDTO.self, key: key)
        #expect(afterReset == nil)
    }

    /// `.chatOnly` is for a store that predates any record of who owns it, where
    /// everything except chat is reconciled by the next pull. Activities are not
    /// reconciled by a pull, but that scope is not about a change of account —
    /// it is about a store nothing can vouch for, and the cache is re-fetched on
    /// open anyway.
    @Test("A chat-only reset leaves the cache alone")
    func chatOnlyResetKeepsTheCache() async throws {
        let cache = ActivitySnapshotCache(directory: Self.scratchDirectory())
        let key = ActivitySnapshotKey(.getPersonSeason, 7, 0)
        await cache.store(Fixture.data(Fixture.personSeason(personId: 7)), key: key)

        await LocalDataReset.erase(
            .chatOnly,
            context: try TestStore.makeContext(),
            syncQueue: TestStore.makeQueue(),
            activityCache: cache
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

    /// `familyId: 0` means the caller's primary family, the same convention
    /// `FamilyMembershipService` uses.
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
