import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Sending the activity outbox")
struct ActivityOutboxSenderTests {

    private static let owner = ActivityScope(userId: 1, familyId: 7)
    private static let username = "owner@example.test"
    private static let save = "rpc/SyncSaveAppearance"
    private static let delete = "rpc/SyncDeleteAppearance"

    private static func scratchDefaults() -> UserDefaults {
        let name = "OutboxSenderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private static func setUp(supported: Bool = true, signedInAs: String = username) -> (FakeHTTPServer, ActivityLocalStore, ActivityOutboxSender) {
        let server = FakeHTTPServer()
        if supported {
            server.route("rpc/GetActivitySyncSupport", respond: .json(["mutationVersion": ActivityMutationContract.version]))
        } else {
            server.route("rpc/GetActivitySyncSupport", respond: .status(400, message: "Procedure Not Found"))
        }
        let store = ActivityLocalStore.inMemory()
        let claims = Fixture.data(["username": signedInAs]).base64EncodedString()
        let sender = ActivityOutboxSender(
            store: store,
            apiClient: APIClient(baseURL: server.baseURL, session: server.session(), initialAccessToken: "header.\(claims).signature"),
            capability: ActivitySyncCapability(defaults: scratchDefaults())
        )
        sender.jitter = { 1 }
        return (server, store, sender)
    }

    private static func snapshot(_ label: String) -> PerformanceSnapshot {
        PerformanceSnapshot(
            occurredAt: nil,
            notes: "",
            matchup: nil,
            results: [LocalResultRow(id: UUID(), serverId: nil, input: ResultInputDTO(
                kind: "adjudication", label: label, rank: nil, outOf: nil,
                category: "", score: nil, personId: nil, notes: ""
            ))],
            photoIds: [3]
        )
    }

    private static func label(_ performance: LocalPerformance?) -> String? {
        performance?.snapshot?.results.first?.input.label
    }

    private static func outcome(
        _ status: String,
        id: Int = 40,
        revision: Int,
        label: String? = nil,
        code: String = ""
    ) -> FakeHTTPServer.Response {
        var body: [String: Any] = ["status": status, "appearanceId": id, "revision": revision, "code": code, "message": ""]
        if let label {
            var appearance = Fixture.appearance(id: id, eventId: 5, entryId: 11)
            appearance["revision"] = revision
            body["appearance"] = Fixture.appearanceView(
                appearance,
                results: [Fixture.activityResult(id: id * 10 + revision, appearanceId: id, label: label)],
                photoIds: [3]
            )
        }
        return .json(body)
    }

    private static func saveBody(_ request: FakeHTTPServer.Request) throws -> SyncSaveAppearanceRequestDTO {
        try JSONDecoder().decode(SyncSaveAppearanceRequestDTO.self, from: request.body)
    }

    // MARK: - Capability

    @Test("An empty outbox can learn support on the first online competition visit")
    func capabilityProbeWithEmptyQueue() async {
        let (server, store, sender) = Self.setUp()
        #expect(!sender.capability.isSupported)
        #expect(store.mutations(userId: 1).isEmpty)

        #expect(await sender.checkSupport(username: Self.username) == nil)

        #expect(sender.capability.isSupported)
        #expect(server.requests(for: "rpc/GetActivitySyncSupport").count == 1)
        #expect(server.requests(for: Self.save).isEmpty)
    }

    @Test("A server without the queued-write procs gets nothing, and the queue is kept")
    func unsupportedServerKeepsQueue() async throws {
        let (server, store, sender) = Self.setUp(supported: false)
        try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)

        let stop = await sender.drain(userId: 1, username: Self.username)

        #expect(stop == .unsupported)
        #expect(server.requests(for: Self.save).isEmpty)
        #expect(store.mutations(userId: 1).count == 1)
        #expect(!sender.capability.isSupported)
    }

    // MARK: - Acknowledgements

    @Test("A create is sent once and acknowledged with the server's id and revision")
    func createIsAcknowledged() async throws {
        let (server, store, sender) = Self.setUp()
        server.route(Self.save, respond: Self.outcome("applied", revision: 1, label: "Gold"))
        let performance = try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)
        let mutationId = try #require(store.mutations(userId: 1).first?.id)

        let stop = await sender.drain(userId: 1, username: Self.username)

        #expect(stop == nil)
        #expect(sender.capability.isSupported)
        let sent = try Self.saveBody(try #require(server.requests(for: Self.save).first))
        #expect(sent.mutationId == mutationId.uuidString)
        #expect(sent.expectedRevision == nil)
        #expect(sent.appearance.id == 0)
        #expect(sent.appearance.matchup == nil)
        #expect(sent.appearance.photoIds == [3])
        #expect(performance.serverId == 40)
        #expect(performance.serverRevision == 1)
        #expect(!performance.hasUnsyncedChanges)
        #expect(store.mutations(userId: 1).isEmpty)
    }

    @Test("After a lost response the same request is sent again, unchanged")
    func lostResponseResendsTheSameRequest() async throws {
        let (server, store, sender) = Self.setUp()
        server.routeSequence(Self.save, [.offline(), Self.outcome("replayed", revision: 1, label: "Gold")])
        let performance = try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)

        #expect(await sender.drain(userId: 1, username: Self.username) == .offline)
        let pending = try #require(store.mutations(userId: 1).first)
        #expect(pending.mayHaveBeenSent)
        #expect(pending.failureCount == 0)
        #expect(pending.status == .pending)

        #expect(await sender.drain(userId: 1, username: Self.username) == nil)
        let requests = server.requests(for: Self.save)
        #expect(requests.count == 2)
        #expect(try Self.saveBody(requests[0]) == Self.saveBody(requests[1]))
        #expect(performance.serverId == 40)
        #expect(store.mutations(userId: 1).isEmpty)
    }

    @Test("An edit saved during a create waits for it, then names the revision the create got")
    func editAfterCreateUsesItsRevision() async throws {
        let (server, store, sender) = Self.setUp()
        server.routeSequence(Self.save, [
            Self.outcome("applied", revision: 1, label: "Gold"),
            Self.outcome("applied", revision: 2, label: "Platinum")
        ])
        let performance = try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)
        let inFlight = try #require(store.mutations(userId: 1).first)
        inFlight.attemptCount = 1
        try store.save(Self.snapshot("Platinum"), localId: performance.localId, scope: Self.owner, eventId: 5, entryId: 11)

        #expect(await sender.drain(userId: 1, username: Self.username) == nil)

        let requests = server.requests(for: Self.save)
        #expect(requests.count == 2)
        let edit = try Self.saveBody(requests[1])
        #expect(edit.appearance.id == 40)
        #expect(edit.expectedRevision == 1)
        #expect(edit.appearance.results.first?.label == "Platinum")
        #expect(performance.serverRevision == 2)
        #expect(Self.label(performance) == "Platinum")
        #expect(!performance.hasUnsyncedChanges)
    }

    @Test("A late acknowledgement does not undo a newer local edit")
    func lateAcknowledgementKeepsNewerEdit() async throws {
        let (server, store, sender) = Self.setUp()
        server.routeSequence(Self.save, [Self.outcome("applied", revision: 1, label: "Gold"), .offline()])
        let performance = try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)
        let inFlight = try #require(store.mutations(userId: 1).first)
        inFlight.attemptCount = 1
        try store.save(Self.snapshot("Platinum"), localId: performance.localId, scope: Self.owner, eventId: 5, entryId: 11)

        #expect(await sender.drain(userId: 1, username: Self.username) == .offline)

        #expect(performance.serverId == 40)
        #expect(Self.label(performance) == "Platinum")
        #expect(performance.hasUnsyncedChanges)
        #expect(store.mutations(userId: 1).count == 1)
    }

    // MARK: - Refusals

    @Test("A conflict keeps both versions for review and holds back what follows")
    func conflictNeedsReview() async throws {
        let (server, store, sender) = Self.setUp()
        try store.mergeServerPerformances([try APIClient.decode(AppearanceDetailDTO.self, from: Fixture.data(Fixture.appearanceDetail(
            Fixture.appearance(id: 40, eventId: 5, entryId: 11),
            entry: Fixture.activityEntry(id: 11),
            event: Fixture.eventSummary(id: 5)
        )))], eventId: 5, userId: 1, readStartedAt: Date())
        let performance = try #require(store.performance(serverId: 40, userId: 1))
        server.route(Self.save, respond: Self.outcome("conflict", revision: 7, label: "From the website"))
        try store.save(Self.snapshot("Mine"), localId: performance.localId, scope: Self.owner, eventId: 5, entryId: 11)
        let inFlight = try #require(store.mutations(userId: 1).first)
        inFlight.attemptCount = 1
        try store.save(Self.snapshot("Mine again"), localId: performance.localId, scope: Self.owner, eventId: 5, entryId: 11)

        #expect(await sender.drain(userId: 1, username: Self.username) == nil)

        let queued = store.mutations(userId: 1)
        #expect(queued.count == 2)
        #expect(queued[0].status == .needsReview)
        #expect(queued[0].lastOutcome == "conflict")
        let kept = try APIClient.decode(AppearanceMutationResponseDTO.self, from: try #require(queued[0].serverResponseData))
        #expect(kept.appearance?.results.first?.label == "From the website")
        #expect(queued[1].status == .pending)
        #expect(server.requests(for: Self.save).count == 1)
        #expect(Self.label(performance) == "Mine again")
    }

    // MARK: - Review

    /// A server copy at revision 1, edited here, with the edit answered by a conflict at revision 7.
    private static func conflicted() async throws -> (FakeHTTPServer, ActivityLocalStore, ActivityOutboxSender, LocalPerformance) {
        let (server, store, sender) = Self.setUp()
        try store.mergeServerPerformances([try APIClient.decode(AppearanceDetailDTO.self, from: Fixture.data(Fixture.appearanceDetail(
            Fixture.appearance(id: 40, eventId: 5, entryId: 11),
            entry: Fixture.activityEntry(id: 11),
            event: Fixture.eventSummary(id: 5)
        )))], eventId: 5, userId: 1, readStartedAt: Date())
        let performance = try #require(store.performance(serverId: 40, userId: 1))
        server.route(Self.save, respond: Self.outcome("conflict", revision: 7, label: "From the website"))
        try store.save(Self.snapshot("Mine"), localId: performance.localId, scope: Self.owner, eventId: 5, entryId: 11)
        _ = await sender.drain(userId: 1, username: Self.username)
        #expect(store.mutations(userId: 1).first?.status == .needsReview)
        return (server, store, sender, performance)
    }

    @Test("Keep mine resends the change, as a new request, against the website's revision")
    func keepMine() async throws {
        let (server, store, sender, performance) = try await Self.conflicted()
        server.route(Self.save, respond: Self.outcome("applied", revision: 8, label: "Mine"))

        try store.resend(performance.localId, userId: 1)
        #expect(store.unsyncedSummary(userId: 1).waiting == 1)
        #expect(store.unsyncedSummary(userId: 1).needsAttention == 0)
        #expect(await sender.drain(userId: 1, username: Self.username) == nil)

        let requests = server.requests(for: Self.save)
        #expect(requests.count == 2)
        let first = try Self.saveBody(requests[0])
        let second = try Self.saveBody(requests[1])
        #expect(second.expectedRevision == 7)
        #expect(second.mutationId != first.mutationId)
        #expect(store.mutations(userId: 1).isEmpty)
        #expect(performance.serverRevision == 8)
        #expect(Self.label(performance) == "Mine")
    }

    @Test("Use the website's drops the change and shows the website's copy")
    func useTheWebsites() async throws {
        let (server, store, _, performance) = try await Self.conflicted()

        try store.discardChanges(performance.localId, userId: 1)

        #expect(store.mutations(userId: 1).isEmpty)
        #expect(!performance.hasUnsyncedChanges)
        #expect(performance.serverRevision == 7)
        #expect(Self.label(performance) == "From the website")
        #expect(server.requests(for: Self.save).count == 1)
    }

    @Test("Keeping a change to a performance deleted on the website records it again")
    func keepMineAfterDelete() async throws {
        let (server, store, sender, performance) = try await Self.conflicted()
        try store.commit {
            store.mutations(userId: 1)[0].serverResponseData = try JSONSerialization.data(withJSONObject: [
                "status": "deleted", "appearanceId": 40, "revision": 9
            ])
        }
        server.route(Self.save, respond: Self.outcome("applied", id: 41, revision: 1, label: "Mine"))

        try store.resend(performance.localId, userId: 1)
        #expect(await sender.drain(userId: 1, username: Self.username) == nil)

        let again = try Self.saveBody(try #require(server.requests(for: Self.save).last))
        #expect(again.appearance.id == 0)
        #expect(again.expectedRevision == nil)
        #expect(performance.serverId == 41)
    }

    @Test("Discarding a performance never sent removes it")
    func discardNeverSent() throws {
        let store = ActivityLocalStore.inMemory()
        let created = try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)

        try store.discardChanges(created.localId, userId: 1)

        #expect(store.performance(created.localId) == nil)
        #expect(store.mutations(userId: 1).isEmpty)
        #expect(store.unsyncedSummary(userId: 1).waiting == 0)
        #expect(store.unsyncedSummary(userId: 1).needsAttention == 0)
    }

    @Test("Try again resends a refused save")
    func tryAgain() async throws {
        let (server, store, sender) = Self.setUp()
        server.route(Self.save, respond: Self.outcome("invalid", id: 0, revision: 0, code: "personNotOnEntry"))
        let created = try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)
        _ = await sender.drain(userId: 1, username: Self.username)
        #expect(store.unsyncedSummary(userId: 1).waiting == 1)
        #expect(store.unsyncedSummary(userId: 1).needsAttention == 1)

        server.route(Self.save, respond: Self.outcome("applied", revision: 1, label: "Gold"))
        try store.resend(created.localId, userId: 1)
        #expect(await sender.drain(userId: 1, username: Self.username) == nil)

        #expect(server.requests(for: Self.save).count == 2)
        #expect(store.mutations(userId: 1).isEmpty)
        #expect(created.serverId == 40)
    }

    @Test("Sign-out warns about results still on this phone")
    func signOutMessage() {
        #expect(ActivityLocalStore.signOutMessage(waiting: 0) == "Are you sure you want to sign out?")
        #expect(ActivityLocalStore.signOutMessage(waiting: 1).hasPrefix("1 result hasn't"))
        #expect(ActivityLocalStore.signOutMessage(waiting: 3).hasPrefix("3 results haven't"))
        #expect(ActivityUnsyncedNote.text(waiting: 2, needsAttention: 1).contains("couldn't sync"))
    }

    @Test("A refused save is kept with its reason and not retried")
    func invalidIsKept() async throws {
        let (server, store, sender) = Self.setUp()
        server.route(Self.save, respond: Self.outcome("invalid", id: 0, revision: 0, code: "personNotOnEntry"))
        try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)

        #expect(await sender.drain(userId: 1, username: Self.username) == nil)
        #expect(await sender.drain(userId: 1, username: Self.username) == nil)

        let failed = try #require(store.mutations(userId: 1).first)
        #expect(failed.status == .failed)
        #expect(failed.lastOutcome == "invalid:personNotOnEntry")
        #expect(server.requests(for: Self.save).count == 1)
    }

    @Test("A server error backs off and keeps the entry")
    func serverErrorBacksOff() async throws {
        let (server, store, sender) = Self.setUp()
        let start = Date(timeIntervalSince1970: 1_000)
        sender.now = { start }
        server.route(Self.save, respond: .status(503, message: "busy"))
        try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)

        #expect(await sender.drain(userId: 1, username: Self.username) == nil)
        let waiting = try #require(store.mutations(userId: 1).first)
        #expect(waiting.status == .pending)
        #expect(waiting.failureCount == 1)
        #expect(waiting.nextAttemptAt == start.addingTimeInterval(ActivityOutboxSender.baseBackoff))

        // Not before its time.
        #expect(await sender.drain(userId: 1, username: Self.username) == nil)
        #expect(server.requests(for: Self.save).count == 1)

        sender.now = { start.addingTimeInterval(60) }
        #expect(await sender.drain(userId: 1, username: Self.username) == nil)
        #expect(server.requests(for: Self.save).count == 2)
        #expect(waiting.failureCount == 2)
    }

    @Test("Backoff doubles up to an hour")
    func backoffSchedule() {
        #expect(ActivityOutboxSender.backoff(failures: 1) == 5)
        #expect(ActivityOutboxSender.backoff(failures: 2) == 10)
        #expect(ActivityOutboxSender.backoff(failures: 4) == 40)
        #expect(ActivityOutboxSender.backoff(failures: 40) == ActivityOutboxSender.maximumBackoff)
    }

    @Test("A signed-out session pauses the queue until someone signs in")
    func authFailurePauses() async throws {
        let (server, store, sender) = Self.setUp()
        server.routeSequence(Self.save, [.status(400, message: "AuthFailure"), Self.outcome("replayed", revision: 1, label: "Gold")])
        try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)

        #expect(await sender.drain(userId: 1, username: Self.username) == .signedOut)
        #expect(store.mutations(userId: 1).first?.status == .needsSignIn)

        #expect(await sender.drain(userId: 1, username: Self.username) == nil)
        #expect(store.mutations(userId: 1).isEmpty)
    }

    // MARK: - Deletes

    @Test("A delete during an in-flight create waits for its id, leaving nothing behind")
    func deleteAfterInFlightCreate() async throws {
        let (server, store, sender) = Self.setUp()
        server.route(Self.save, respond: Self.outcome("applied", revision: 1, label: "Gold"))
        server.route(Self.delete, respond: Self.outcome("applied", revision: 2))
        let performance = try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)
        let localId = performance.localId
        let inFlight = try #require(store.mutations(userId: 1).first)
        inFlight.attemptCount = 1
        try store.delete(localId, userId: 1)

        #expect(await sender.drain(userId: 1, username: Self.username) == nil)

        let deleteRequest = try JSONDecoder().decode(
            SyncDeleteAppearanceRequestDTO.self,
            from: try #require(server.requests(for: Self.delete).first).body
        )
        #expect(deleteRequest.id == 40)
        #expect(deleteRequest.expectedRevision == 1)
        #expect(store.performance(localId) == nil)
        #expect(store.mutations(userId: 1).isEmpty)
    }

    @Test("A delete of something already deleted on the server is done")
    func deleteOfDeletedIsDone() async throws {
        let (server, store, sender) = Self.setUp()
        try store.mergeServerPerformances([try APIClient.decode(AppearanceDetailDTO.self, from: Fixture.data(Fixture.appearanceDetail(
            Fixture.appearance(id: 40, eventId: 5, entryId: 11),
            entry: Fixture.activityEntry(id: 11),
            event: Fixture.eventSummary(id: 5)
        )))], eventId: 5, userId: 1, readStartedAt: Date())
        let localId = try #require(store.performance(serverId: 40, userId: 1)).localId
        server.route(Self.delete, respond: Self.outcome("deleted", revision: 3))
        try store.delete(localId, userId: 1)

        #expect(await sender.drain(userId: 1, username: Self.username) == nil)

        #expect(store.performance(localId) == nil)
        #expect(store.mutations(userId: 1).isEmpty)
    }

    // MARK: - One pass at a time

    @Test("Overlapping triggers send each entry once")
    func overlappingDrainsSendOnce() async throws {
        let (server, store, sender) = Self.setUp()
        server.route(Self.save, respond: Self.outcome("applied", revision: 1, label: "Gold"))
        try store.save(Self.snapshot("Gold"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)

        async let first = sender.drain(userId: 1, username: Self.username)
        async let second = sender.drain(userId: 1, username: Self.username)
        _ = await (first, second)

        #expect(server.requests(for: Self.save).count == 1)
        #expect(store.mutations(userId: 1).isEmpty)
    }

    @Test("A drain for a previous account stops even after the server capability was confirmed")
    func changedCredentialsStopAnExistingDrain() async throws {
        let (server, store, sender) = Self.setUp(signedInAs: "other@example.test")
        #expect(await sender.checkSupport(username: "other@example.test") == nil)
        try store.save(Self.snapshot("Mine"), localId: nil, scope: Self.owner, eventId: 5, entryId: 11)

        #expect(await sender.drain(userId: 1, username: Self.username) == .signedOut)

        #expect(server.requests(for: Self.save).isEmpty)
        #expect(store.mutations(userId: 1).first?.status == .needsSignIn)
    }

    @Test("Another account's queue is never sent under this one")
    func otherAccountsWaitForTheirOwner() async throws {
        let (server, store, sender) = Self.setUp()
        server.route(Self.save, respond: Self.outcome("applied", revision: 1, label: "Gold"))
        try store.save(Self.snapshot("Theirs"), localId: nil, scope: ActivityScope(userId: 2, familyId: 7), eventId: 5, entryId: 11)

        #expect(await sender.drain(userId: 1, username: Self.username) == nil)

        #expect(server.requests(for: Self.save).isEmpty)
        #expect(store.mutations(userId: 2).count == 1)
    }
}
