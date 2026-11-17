import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Result entry against the phone's store")
struct LocalResultEntryTests {

    private static func input(_ label: String, kind: String = "adjudication", score: Double? = nil) -> ResultInputDTO {
        ResultInputDTO(kind: kind, label: label, rank: nil, outOf: nil, category: "Teen", score: score, personId: 21, notes: "n")
    }

    private static let event: ActivityEventDTO = {
        (try? APIClient.decode(ActivityEventDTO.self, from: Fixture.data(
            Fixture.activityEvent(id: 5, startDate: "2026-03-14T00:00:00Z")
        )))!
    }()

    private static let riseUp: ActivityEntryDTO = {
        (try? APIClient.decode(ActivityEntryDTO.self, from: Fixture.data(Fixture.activityEntry(id: 11, name: "Rise Up"))))!
    }()

    // MARK: - Rows

    @Test("A saved sheet keeps each row's identity and server id, and drops blank rows")
    func rowsKeepIdentity() {
        let kept = UUID()
        let previous = [LocalResultRow(id: kept, serverId: 400, input: Self.input("Gold"))]
        let drafts = [
            ResultDraft(id: kept, kind: .adjudication, label: "Platinum"),
            ResultDraft(),
            ResultDraft(kind: .award, label: "Judges' Choice")
        ]

        let rows = ResultSheet.rows(drafts, previous: previous)

        #expect(rows.count == 2)
        #expect(rows[0].id == kept)
        #expect(rows[0].serverId == 400)
        #expect(rows[0].input.label == "Platinum")
        #expect(rows[1].serverId == nil)
        #expect(rows[1].id == drafts[2].id)
    }

    @Test("A stored row opens as the same editable row")
    func draftFromRowRoundTrips() {
        let row = LocalResultRow(id: UUID(), serverId: nil, input: Self.input("High Score", kind: "score", score: 98.5))
        let draft = ResultDraft(row: row)

        #expect(draft.id == row.id)
        #expect(draft.input() == row.input)
        #expect(ResultDraft(row: LocalResultRow(id: UUID(), serverId: nil, input: Self.input("x", kind: "score", score: 97))).scoreText == "97")
    }

    // MARK: - Sync state

    @Test("Anything needing someone outranks waiting")
    func syncStatePrecedence() {
        #expect(PerformanceSyncState.of(hasUnsyncedChanges: false, statuses: []) == .synced)
        #expect(PerformanceSyncState.of(hasUnsyncedChanges: true, statuses: []) == .pending)
        #expect(PerformanceSyncState.of(hasUnsyncedChanges: true, statuses: [.pending, .needsSignIn]) == .needsSignIn)
        #expect(PerformanceSyncState.of(hasUnsyncedChanges: true, statuses: [.needsSignIn, .failed]) == .failed)
        #expect(PerformanceSyncState.of(hasUnsyncedChanges: true, statuses: [.failed, .needsReview]) == .needsReview)
        #expect(PerformanceSyncState.synced.label == nil)
        #expect(PerformanceSyncState.pending.label != nil)
    }

    @Test("A performance not yet on the server gets a stable negative id")
    func displayIds() {
        let localId = UUID()
        #expect(LocalCompetition.displayId(serverId: 40, localId: localId) == 40)
        let id = LocalCompetition.displayId(serverId: nil, localId: localId)
        #expect(id < 0)
        #expect(LocalCompetition.displayId(serverId: nil, localId: localId) == id)
        #expect(LocalCompetition.displayId(serverId: nil, localId: UUID()) != id)
    }

    // MARK: - Drawing local performances

    @Test("A local snapshot draws as the server's view types")
    func detailFromSnapshot() {
        let snapshot = PerformanceSnapshot(
            occurredAt: nil,
            notes: "clean",
            matchup: MatchupInputDTO(round: "Final", opponent: "Elite", outcome: "win", scoreFor: 3, scoreAgainst: 1),
            results: [LocalResultRow(id: UUID(), serverId: nil, input: Self.input("Gold"))],
            photoIds: [8]
        )

        let detail = AppearanceDetailDTO(
            local: snapshot, id: -5, eventId: 5, familyId: 7, revision: 2,
            createdAt: Date(), entry: Self.riseUp, event: EventSummaryDTO(Self.event)
        )

        #expect(detail.id == -5)
        #expect(detail.appearance.occurredAt.isServerZero)
        #expect(detail.appearance.notes == "clean")
        #expect(Matchup(detail.appearance) == Matchup(round: "Final", opponent: "Elite", outcome: "win", scoreFor: 3, scoreAgainst: 1))
        #expect(detail.appearance.revision == 2)
        #expect(detail.results.map(\.label) == ["Gold"])
        #expect(detail.results.first?.personId == 21)
        #expect(detail.photoIds == [8])
        #expect(detail.entry.name == "Rise Up")
    }

    @Test("The page lists saved and pending performances, without local deletes or routines it cannot name")
    func rowsFromStore() throws {
        let store = ActivityLocalStore.inMemory()
        let scope = ActivityScope(userId: 1, familyId: 7)
        let snapshot = PerformanceSnapshot(occurredAt: nil, notes: "", matchup: nil, results: [], photoIds: [])
        let pending = try store.save(snapshot, localId: nil, scope: scope, eventId: 5, entryId: 11)
        let deleted = try store.save(snapshot, localId: nil, scope: scope, eventId: 5, entryId: 11)
        try store.delete(deleted.localId, userId: 1)
        try store.save(snapshot, localId: nil, scope: scope, eventId: 5, entryId: 99)
        try store.save(snapshot, localId: nil, scope: ActivityScope(userId: 2, familyId: 7), eventId: 5, entryId: 11)

        let rows = LocalCompetition.rows(
            store: store, eventId: 5, userId: 1, event: Self.event,
            entries: [Self.riseUp], serverAppearances: []
        )

        #expect(rows.map(\.localId) == [pending.localId])
        #expect(rows.first?.syncState == .pending)
        #expect(rows.first?.detail.entry.name == "Rise Up")
        #expect((rows.first?.detail.id ?? 0) < 0)
    }

    // MARK: - Read timing

    @Test("A screen records when its read was sent")
    func readStartRecorded() async {
        let state = ActivityScreenState<Int>()
        let before = Date()
        await state.load(ActivityRead(cached: { nil }, live: { 1 }))

        guard let started = state.readStartedAt, let fetched = state.fetchedAt else {
            Issue.record("the read's times were not recorded")
            return
        }
        #expect(started >= before)
        #expect(started <= fetched)
    }
}
