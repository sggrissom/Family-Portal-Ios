import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Activity local store")
struct ActivityLocalStoreTests {

    private static let owner = ActivityScope(userId: 1, familyId: 7)
    private static let otherAccount = ActivityScope(userId: 2, familyId: 7)

    private struct Failure: Error {}

    private static func scratchURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityStore-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Activities.store")
    }

    private static func snapshot(_ label: String, notes: String = "", photoIds: [Int] = []) -> PerformanceSnapshot {
        PerformanceSnapshot(
            occurredAt: nil,
            notes: notes,
            matchup: nil,
            results: [LocalResultRow(id: UUID(), serverId: nil, input: ResultInputDTO(
                kind: "adjudication", label: label, rank: nil, outOf: nil,
                category: "", score: nil, personId: nil, notes: ""
            ))],
            photoIds: photoIds
        )
    }

    private static func label(_ performance: LocalPerformance?) -> String? {
        performance?.snapshot?.results.first?.input.label
    }

    @discardableResult
    private static func create(_ store: ActivityLocalStore, _ label: String, scope: ActivityScope = owner, eventId: Int = 5) throws -> LocalPerformance {
        try store.save(snapshot(label), localId: nil, scope: scope, eventId: eventId, entryId: 11)
    }

    private static func detail(id: Int, revision: Int, label: String, eventId: Int = 5) throws -> AppearanceDetailDTO {
        var appearance = Fixture.appearance(id: id, eventId: eventId, entryId: 11)
        appearance["revision"] = revision
        return try APIClient.decode(AppearanceDetailDTO.self, from: Fixture.data(Fixture.appearanceDetail(
            appearance,
            results: [Fixture.activityResult(id: id * 10, appearanceId: id, label: label)],
            photoIds: [3],
            entry: Fixture.activityEntry(id: 11),
            event: Fixture.eventSummary(id: eventId)
        )))
    }

    // MARK: - Saving

    @Test("A new performance and its queued create are saved together")
    func createQueuesASave() throws {
        let store = ActivityLocalStore.inMemory()
        let performance = try Self.create(store, "Platinum")

        #expect(performance.serverId == nil)
        #expect(performance.hasUnsyncedChanges)
        #expect(Self.label(store.performances(eventId: 5, userId: 1).first) == "Platinum")

        let queued = store.mutations(userId: 1)
        #expect(queued.count == 1)
        let create = try #require(queued.first)
        #expect(create.kind == .save)
        #expect(create.performanceLocalId == performance.localId)
        #expect(create.expectedRevision == nil)
        #expect(create.dependsOnMutationId == nil)
        #expect(create.generation == performance.localGeneration)
    }

    @Test("Saved work is still there after a relaunch")
    func survivesRelaunch() throws {
        let url = Self.scratchURL()
        let localId: UUID
        do {
            let store = ActivityLocalStore.open(at: url)
            #expect(store.isDurable)
            localId = try Self.create(store, "Platinum").localId
        }

        let reopened = ActivityLocalStore.open(at: url)
        #expect(Self.label(reopened.performance(localId)) == "Platinum")
        #expect(reopened.mutations(userId: 1).count == 1)
        #expect(reopened.recoveredStoreURL == nil)
    }

    @Test("Edits before anything is sent fold into the one queued save")
    func unsentEditsCoalesce() throws {
        let store = ActivityLocalStore.inMemory()
        let performance = try Self.create(store, "Gold")
        try store.save(Self.snapshot("Platinum"), localId: performance.localId, scope: Self.owner, eventId: 5, entryId: 11)

        let queued = store.mutations(userId: 1)
        #expect(queued.count == 1)
        let only = try #require(queued.first)
        let payload = try PerformanceSnapshot.decoder.decode(PerformanceSnapshot.self, from: try #require(only.snapshotData))
        #expect(payload.results.first?.input.label == "Platinum")
        #expect(only.generation == 2)
        #expect(performance.localGeneration == 2)
    }

    @Test("An edit after a save may have reached the server is queued behind it, payload untouched")
    func editAfterSendIsSeparate() throws {
        let store = ActivityLocalStore.inMemory()
        let performance = try Self.create(store, "Gold")
        let create = try #require(store.mutations(userId: 1).first)
        create.sentRequest = Data("frozen".utf8)
        let frozenPayload = create.snapshotData

        try store.save(Self.snapshot("Platinum"), localId: performance.localId, scope: Self.owner, eventId: 5, entryId: 11)

        let queued = store.mutations(userId: 1)
        #expect(queued.count == 2)
        #expect(queued[0].snapshotData == frozenPayload)
        #expect(queued[1].dependsOnMutationId == create.id)
        // Its revision comes from the create's acknowledgement.
        #expect(queued[1].expectedRevision == nil)
    }

    @Test("An edit of the server's copy names the revision it was made against")
    func editOfServerCopyCarriesRevision() throws {
        let store = ActivityLocalStore.inMemory()
        try store.mergeServerPerformances([try Self.detail(id: 40, revision: 6, label: "Gold")], eventId: 5, userId: 1, readStartedAt: Date())
        let pulled = try #require(store.performance(serverId: 40, userId: 1))
        #expect(!pulled.hasUnsyncedChanges)
        #expect(store.mutations(userId: 1).isEmpty)

        try store.save(Self.snapshot("Platinum"), localId: pulled.localId, scope: Self.owner, eventId: 5, entryId: 11)

        let edit = try #require(store.mutations(userId: 1).first)
        #expect(edit.expectedRevision == 6)
        #expect(edit.dependsOnMutationId == nil)
    }

    // MARK: - Deleting

    @Test("Deleting a performance the server never heard of leaves nothing to send")
    func deleteNeverSentCreate() throws {
        let store = ActivityLocalStore.inMemory()
        let performance = try Self.create(store, "Gold")

        try store.delete(performance.localId, userId: 1)

        #expect(store.performance(performance.localId) == nil)
        #expect(store.mutations(userId: 1).isEmpty)
    }

    @Test("Deleting while a create may be in flight keeps the create and queues the delete behind it")
    func deleteDuringCreate() throws {
        let store = ActivityLocalStore.inMemory()
        let performance = try Self.create(store, "Gold")
        let create = try #require(store.mutations(userId: 1).first)
        create.attemptCount = 1
        try store.save(Self.snapshot("Platinum"), localId: performance.localId, scope: Self.owner, eventId: 5, entryId: 11)
        #expect(store.mutations(userId: 1).count == 2)

        try store.delete(performance.localId, userId: 1)

        let queued = store.mutations(userId: 1)
        #expect(queued.map(\.kind) == [.save, .delete])
        #expect(queued[0].id == create.id)
        #expect(queued[1].dependsOnMutationId == create.id)
        #expect(performance.isLocallyDeleted)
        #expect(store.performances(eventId: 5, userId: 1).isEmpty)
    }

    @Test("Deleting the server's copy queues a delete against its revision")
    func deleteServerCopy() throws {
        let store = ActivityLocalStore.inMemory()
        try store.mergeServerPerformances([try Self.detail(id: 40, revision: 3, label: "Gold")], eventId: 5, userId: 1, readStartedAt: Date())
        let pulled = try #require(store.performance(serverId: 40, userId: 1))

        try store.delete(pulled.localId, userId: 1)

        let delete = try #require(store.mutations(userId: 1).first)
        #expect(delete.kind == .delete)
        #expect(delete.expectedRevision == 3)
        #expect(store.performances(eventId: 5, userId: 1).isEmpty)
    }

    // MARK: - Failure

    @Test("A save that fails to persist leaves neither the change nor its outbox entry")
    func failedSaveRollsBack() throws {
        let store = ActivityLocalStore.inMemory()
        let existing = try Self.create(store, "Gold")
        store.persist = { _ in throw Failure() }

        #expect(throws: ActivityStoreError.self) { try Self.create(store, "Silver") }
        #expect(throws: ActivityStoreError.self) {
            try store.save(Self.snapshot("Platinum"), localId: existing.localId, scope: Self.owner, eventId: 5, entryId: 11)
        }
        #expect(throws: ActivityStoreError.self) { try store.delete(existing.localId, userId: 1) }

        store.persist = { try $0.save() }
        let performances = store.performances(eventId: 5, userId: 1)
        #expect(performances.count == 1)
        #expect(Self.label(performances.first) == "Gold")
        #expect(performances.first?.localGeneration == 1)
        let queued = store.mutations(userId: 1)
        #expect(queued.count == 1)
        let payload = try PerformanceSnapshot.decoder.decode(PerformanceSnapshot.self, from: try #require(queued.first?.snapshotData))
        #expect(payload.results.first?.input.label == "Gold")
    }

    @Test("A store that could not open on disk refuses to claim a save")
    func notDurableRefuses() throws {
        let schema = ActivityLocalStore.makeSchema()
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let store = ActivityLocalStore(container: container, isDurable: false)

        #expect(throws: ActivityStoreError.unavailable) { try Self.create(store, "Gold") }
    }

    @Test("An unreadable store is set aside, not read as no pending work")
    func unreadableStoreIsQuarantined() throws {
        let url = Self.scratchURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: url)

        let store = ActivityLocalStore.open(at: url)

        let recovered = try #require(store.recoveredStoreURL)
        #expect(FileManager.default.fileExists(atPath: recovered.path))
        #expect(try Data(contentsOf: recovered) == Data("not a database".utf8))
        #expect(store.isDurable)
        try Self.create(store, "Gold")
        #expect(store.mutations(userId: 1).count == 1)
    }

    // MARK: - Server copies

    @Test("A pull never overwrites a local change, an older revision, or a newer acknowledgement")
    func mergePreservesNewerLocalState() throws {
        let store = ActivityLocalStore.inMemory()
        let start = Date(timeIntervalSince1970: 1_000)
        try store.mergeServerPerformances(
            [try Self.detail(id: 40, revision: 4, label: "Gold"), try Self.detail(id: 41, revision: 4, label: "Gold")],
            eventId: 5, userId: 1, readStartedAt: start
        )
        let edited = try #require(store.performance(serverId: 40, userId: 1))
        try store.save(Self.snapshot("Mine"), localId: edited.localId, scope: Self.owner, eventId: 5, entryId: 11)

        // A later read with an older revision of 41 and the server's 40.
        try store.mergeServerPerformances(
            [try Self.detail(id: 40, revision: 5, label: "Theirs"), try Self.detail(id: 41, revision: 3, label: "Stale")],
            eventId: 5, userId: 1, readStartedAt: start.addingTimeInterval(10)
        )
        #expect(Self.label(store.performance(serverId: 40, userId: 1)) == "Mine")
        #expect(Self.label(store.performance(serverId: 41, userId: 1)) == "Gold")

        // A read that began before the phone last heard of 41 is older than what it has.
        let clean = try #require(store.performance(serverId: 41, userId: 1))
        clean.serverUpdatedAt = start.addingTimeInterval(100)
        try store.mergeServerPerformances(
            [try Self.detail(id: 41, revision: 9, label: "Earlier read")],
            eventId: 5, userId: 1, readStartedAt: start.addingTimeInterval(50)
        )
        #expect(Self.label(store.performance(serverId: 41, userId: 1)) == "Gold")

        // A newer read of a clean copy replaces it.
        try store.mergeServerPerformances(
            [try Self.detail(id: 41, revision: 9, label: "Fresh")],
            eventId: 5, userId: 1, readStartedAt: start.addingTimeInterval(200)
        )
        #expect(Self.label(store.performance(serverId: 41, userId: 1)) == "Fresh")
        #expect(store.performance(serverId: 41, userId: 1)?.serverRevision == 9)
    }

    @Test("A pull does not bring back a local delete, nor drop a performance it began too early to see")
    func mergeRespectsTombstonesAndTiming() throws {
        let store = ActivityLocalStore.inMemory()
        let start = Date(timeIntervalSince1970: 1_000)
        try store.mergeServerPerformances(
            [try Self.detail(id: 40, revision: 1, label: "Gold"), try Self.detail(id: 41, revision: 1, label: "Gold")],
            eventId: 5, userId: 1, readStartedAt: start
        )
        let deleted = try #require(store.performance(serverId: 40, userId: 1))
        try store.delete(deleted.localId, userId: 1)
        let acknowledged = try #require(store.performance(serverId: 41, userId: 1))
        acknowledged.serverUpdatedAt = start.addingTimeInterval(100)

        // Still lists 40 (the delete hasn't been sent) and, begun too early, misses 41.
        try store.mergeServerPerformances(
            [try Self.detail(id: 40, revision: 1, label: "Gold")],
            eventId: 5, userId: 1, readStartedAt: start.addingTimeInterval(50)
        )
        #expect(store.performances(eventId: 5, userId: 1).compactMap(\.serverId) == [41])
        #expect(store.performance(serverId: 40, userId: 1)?.isLocallyDeleted == true)

        // A read after that which misses 41 means it is gone on the server.
        try store.mergeServerPerformances([], eventId: 5, userId: 1, readStartedAt: start.addingTimeInterval(200))
        #expect(store.performance(serverId: 41, userId: 1) == nil)
        #expect(store.performance(serverId: 40, userId: 1)?.isLocallyDeleted == true)
    }

    @Test("A pulled copy keeps its row identities across refreshes")
    func rowIdsAreStable() throws {
        let store = ActivityLocalStore.inMemory()
        try store.mergeServerPerformances([try Self.detail(id: 40, revision: 1, label: "Gold")], eventId: 5, userId: 1, readStartedAt: Date(timeIntervalSince1970: 1))
        let first = try #require(store.performance(serverId: 40, userId: 1)?.snapshot?.results.first?.id)

        try store.mergeServerPerformances([try Self.detail(id: 40, revision: 2, label: "Gold")], eventId: 5, userId: 1, readStartedAt: Date(timeIntervalSince1970: 2))

        #expect(store.performance(serverId: 40, userId: 1)?.snapshot?.results.first?.id == first)
        #expect(store.performance(serverId: 40, userId: 1)?.snapshot?.photoIds == [3])
    }

    // MARK: - Accounts

    @Test("Each account sees only its own performances and outbox")
    func accountsArePartitioned() throws {
        let store = ActivityLocalStore.inMemory()
        try Self.create(store, "Mine")
        try Self.create(store, "Theirs", scope: Self.otherAccount)

        #expect(store.performances(eventId: 5, userId: 1).map { Self.label($0) } == ["Mine"])
        #expect(store.performances(eventId: 5, userId: 2).map { Self.label($0) } == ["Theirs"])
        #expect(store.mutations(userId: 1).count == 1)
        let theirs = try #require(store.performances(eventId: 5, userId: 2).first)
        #expect(throws: ActivityStoreError.notFound) {
            try store.save(Self.snapshot("Hijack"), localId: theirs.localId, scope: Self.owner, eventId: 5, entryId: 11)
        }
        #expect(throws: ActivityStoreError.notFound) { try store.delete(theirs.localId, userId: 1) }
    }

    @Test("Switching accounts drops what the server has and keeps each account's unsent work")
    func switchingAccountsKeepsUnsentWork() throws {
        let store = ActivityLocalStore.inMemory()
        try store.mergeServerPerformances([try Self.detail(id: 40, revision: 1, label: "Synced")], eventId: 5, userId: 1, readStartedAt: Date())
        try store.recordPreparation(eventId: 5, userId: 1) { $0.hasEventDetail = true }
        try Self.create(store, "Unsent", scope: Self.otherAccount)

        try store.discardSyncedData()

        #expect(store.performance(serverId: 40, userId: 1) == nil)
        #expect(store.preparedCompetition(eventId: 5, userId: 1) == nil)
        #expect(store.performances(eventId: 5, userId: 2).map { Self.label($0) } == ["Unsent"])
        #expect(store.accountsWithUnsyncedWork() == [2])
    }

    @Test("A deleted account's work goes with it")
    func discardAllForAnAccount() throws {
        let store = ActivityLocalStore.inMemory()
        try Self.create(store, "Mine")
        try Self.create(store, "Theirs", scope: Self.otherAccount)

        try store.discardAll(userId: 1)

        #expect(store.performances(eventId: 5, userId: 1).isEmpty)
        #expect(store.mutations(userId: 1).isEmpty)
        #expect(store.accountsWithUnsyncedWork() == [2])
    }

    @Test("A full erase hands the activity store to the account sweep")
    func localDataResetSweepsActivities() async throws {
        let store = ActivityLocalStore.inMemory()
        try store.mergeServerPerformances([try Self.detail(id: 40, revision: 1, label: "Synced")], eventId: 5, userId: 1, readStartedAt: Date())
        try Self.create(store, "Unsent")
        try Self.create(store, "Deleted account's", scope: Self.otherAccount)

        await LocalDataReset.erase(
            .everything,
            context: try TestStore.makeContext(),
            syncQueue: TestStore.makeQueue(),
            activityCache: ActivitySnapshotCache(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ActivityReset-\(UUID().uuidString)", isDirectory: true)),
            photoCache: PhotoImageCache(session: URLSession(configuration: .ephemeral)),
            activityStore: store,
            discardingActivitiesOf: 2
        )

        #expect(store.performance(serverId: 40, userId: 1) == nil)
        #expect(store.performances(eventId: 5, userId: 1).map { Self.label($0) } == ["Unsent"])
        #expect(store.performances(eventId: 5, userId: 2).isEmpty)
    }
}

@MainActor
@Suite("Preparing a competition")
struct CompetitionPreparationTests {

    private static func service(_ server: FakeHTTPServer) -> ActivityService {
        ActivityService(
            apiClient: server.apiClient(),
            cache: ActivitySnapshotCache(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("Preparation-\(UUID().uuidString)", isDirectory: true)
            )
        )
    }

    private static let access = FamilyAccess(families: [FamilyRefDTO(id: 7, role: FamilyAccess.contribute, isPrimary: true)], primaryFamilyId: 7)

    private static func routeCompetition(_ server: FakeHTTPServer) {
        server.route("rpc/GetEventDetail", respond: .json(Fixture.eventDetail(
            event: Fixture.activityEvent(id: 5, seasonId: 1),
            season: Fixture.seasonSummary(id: 1),
            appearances: [Fixture.appearanceDetail(
                Fixture.appearance(id: 40, eventId: 5, entryId: 11),
                results: [Fixture.activityResult(id: 400, appearanceId: 40)],
                entry: Fixture.activityEntry(id: 11),
                event: Fixture.eventSummary(id: 5)
            )]
        )))
        server.route("rpc/GetSeasonOverview", respond: .json(Fixture.seasonOverview(
            activity: Fixture.activity(id: 3),
            season: Fixture.season(id: 1, activityId: 3),
            entries: [Fixture.entryView(Fixture.activityEntry(id: 11), personIds: [21])]
        )))
    }

    @Test("A complete download records every part and seeds the local performances")
    func completeDownload() async throws {
        let server = FakeHTTPServer()
        Self.routeCompetition(server)
        server.route("rpc/ListActivityVocabulary", respond: .json(Fixture.activityVocabulary(activityId: 3)))
        let store = ActivityLocalStore.inMemory()

        let outcome = await CompetitionPreparation(service: Self.service(server), store: store)
            .prepare(eventId: 5, userId: 1, access: Self.access)

        #expect(outcome == .complete)
        let record = try #require(store.preparedCompetition(eventId: 5, userId: 1))
        #expect(record.isComplete)
        #expect(record.familyId == 7)
        #expect(record.seasonId == 1)
        #expect(record.activityId == 3)
        #expect(record.canContribute)
        #expect(record.preparedAt != nil)
        #expect(store.performances(eventId: 5, userId: 1).compactMap(\.serverId) == [40])
    }

    @Test("A download cut short is recorded as incomplete, keeping what arrived")
    func incompleteDownload() async throws {
        let server = FakeHTTPServer()
        Self.routeCompetition(server)
        server.route("rpc/ListActivityVocabulary", respond: .offline())
        let store = ActivityLocalStore.inMemory()

        let outcome = await CompetitionPreparation(service: Self.service(server), store: store)
            .prepare(eventId: 5, userId: 1, access: Self.access)

        #expect(outcome == .incomplete)
        let record = try #require(store.preparedCompetition(eventId: 5, userId: 1))
        #expect(record.hasEventDetail)
        #expect(record.hasSeasonOverview)
        #expect(!record.hasVocabulary)
        #expect(!record.isComplete)
        #expect(record.preparedAt == nil)
    }

    @Test("A competition that could not be read records nothing")
    func failedDownload() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetEventDetail", respond: .offline())
        let store = ActivityLocalStore.inMemory()

        let outcome = await CompetitionPreparation(service: Self.service(server), store: store)
            .prepare(eventId: 5, userId: 1, access: Self.access)

        guard case .failed = outcome else {
            Issue.record("outcome = \(outcome), want failed")
            return
        }
        #expect(store.preparedCompetition(eventId: 5, userId: 1) == nil)
    }
}
