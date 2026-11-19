import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Editor sessions")
struct EditorSessionTests {

    @Test("A finished save closes its own editor once")
    func finishDismisses() {
        let session = EditorSession()
        var dismissals = 0

        #expect(session.finish { dismissals += 1 })
        #expect(!session.finish { dismissals += 1 })
        #expect(dismissals == 1)
        #expect(!session.isOpen)
    }

    /// The competition-weekend report: Save on routine A stalls, A is cancelled, B is opened, and A's save then lands. The sheet's dismiss closes whatever fills the slot, so it stands in here as clearing the one slot both editors share.
    @Test("A late save from a cancelled editor leaves the next one open")
    func lateCompletionLeavesNextEditorAlone() {
        var presented: String? = "A"
        let first = EditorSession()

        first.close()
        presented = nil

        let second = EditorSession()
        presented = "B"

        #expect(!first.finish { presented = nil })
        #expect(presented == "B")
        #expect(second.isOpen)

        #expect(second.finish { presented = nil })
        #expect(presented == nil)
    }
}

@Suite("Applying a performance write to its competition")
struct EventPerformancesTests {

    private static let event = Fixture.activityEvent(id: 5, startDate: "2026-03-14T00:00:00Z")
    private static let eventSummary = Fixture.eventSummary(id: 5, startDate: "2026-03-14T00:00:00Z")
    private static let riseUp = Fixture.activityEntry(id: 11, name: "Rise Up")
    private static let thunder = Fixture.activityEntry(id: 12, name: "Thunder")

    private static func detail(_ appearances: [[String: Any]]) throws -> GetEventDetailResponseDTO {
        try APIClient.decode(
            GetEventDetailResponseDTO.self,
            from: Fixture.data(Fixture.eventDetail(
                event: event,
                season: Fixture.seasonSummary(id: 1),
                photoIds: [3],
                appearances: appearances
            ))
        )
    }

    private static func recorded(
        id: Int,
        entry: [String: Any] = riseUp,
        occurredAt: String = Fixture.unsetDate,
        label: String = "High Gold"
    ) -> [String: Any] {
        Fixture.appearanceDetail(
            Fixture.appearance(id: id, eventId: 5, entryId: entry["id"] as! Int, occurredAt: occurredAt),
            results: [Fixture.activityResult(id: id * 10, appearanceId: id, label: label)],
            entry: entry,
            event: eventSummary
        )
    }

    private static func saved(
        id: Int,
        eventId: Int = 5,
        entryId: Int,
        occurredAt: String = Fixture.unsetDate,
        label: String,
        photoIds: [Int] = []
    ) throws -> AppearanceViewDTO {
        try APIClient.decode(
            AppearanceViewDTO.self,
            from: Fixture.data(Fixture.appearanceView(
                Fixture.appearance(id: id, eventId: eventId, entryId: entryId, occurredAt: occurredAt),
                results: [Fixture.activityResult(id: id * 10 + 1, appearanceId: id, label: label)],
                photoIds: photoIds
            ))
        )
    }

    private static let entries: [ActivityEntryDTO] = {
        let data = Fixture.data([riseUp, thunder])
        return (try? APIClient.decode([ActivityEntryDTO].self, from: data)) ?? []
    }()

    @Test("A new performance appears under its routine at once")
    func createAppends() throws {
        let response = try Self.detail([Self.recorded(id: 1)])
        let change = PerformanceChange.saved(try Self.saved(id: 2, entryId: 12, label: "Platinum"))

        let updated = EventPerformances.applying(change, to: response, entries: Self.entries)

        #expect(updated.appearances.map(\.id) == [1, 2])
        let created = try #require(updated.appearances.last)
        #expect(created.entry.name == "Thunder")
        #expect(created.event.id == 5)
        #expect(created.results.map(\.label) == ["Platinum"])
        #expect(updated.photoIds == [3])
        #expect(updated.event.id == 5)
    }

    @Test("An edited performance is replaced in place with the server's copy")
    func editReplaces() throws {
        let response = try Self.detail([Self.recorded(id: 1), Self.recorded(id: 2, entry: Self.thunder)])
        let change = PerformanceChange.saved(try Self.saved(id: 1, entryId: 11, label: "Diamond", photoIds: [8]))

        let updated = EventPerformances.applying(change, to: response, entries: [])

        #expect(updated.appearances.map(\.id) == [1, 2])
        let edited = try #require(updated.appearances.first)
        #expect(edited.results.map(\.label) == ["Diamond"])
        #expect(edited.photoIds == [8])
        #expect(edited.entry.name == "Rise Up")
    }

    @Test("A deleted performance leaves the page at once")
    func deleteRemoves() throws {
        let response = try Self.detail([Self.recorded(id: 1), Self.recorded(id: 2, entry: Self.thunder)])

        let updated = EventPerformances.applying(.deleted(appearanceId: 1), to: response, entries: [])

        #expect(updated.appearances.map(\.id) == [2])
    }

    @Test("Performances keep the server's order: by date, the competition's start standing in, then by id")
    func keepsServerOrder() throws {
        let response = try Self.detail([
            Self.recorded(id: 4, occurredAt: "2026-03-15T00:00:00Z"),
            Self.recorded(id: 9)
        ])
        let change = PerformanceChange.saved(try Self.saved(id: 7, entryId: 12, label: "Gold"))

        let updated = EventPerformances.applying(change, to: response, entries: Self.entries)

        // 7 and 9 both fall back to the 14th; 4 is the 15th.
        #expect(updated.appearances.map(\.id) == [7, 9, 4])
    }

    @Test("A change this page cannot place is left for the refresh")
    func unplaceableChangeIgnored() throws {
        let response = try Self.detail([Self.recorded(id: 1)])

        let otherEvent = PerformanceChange.saved(try Self.saved(id: 2, eventId: 6, entryId: 11, label: "Gold"))
        #expect(EventPerformances.applying(otherEvent, to: response, entries: Self.entries).appearances.map(\.id) == [1])

        let unknownRoutine = PerformanceChange.saved(try Self.saved(id: 3, entryId: 99, label: "Gold"))
        #expect(EventPerformances.applying(unknownRoutine, to: response, entries: Self.entries).appearances.map(\.id) == [1])
    }
}

@MainActor
@Suite("Screen state after a local change")
struct ActivityScreenStateApplyTests {

    /// Answers the first read at once, holds the second until `release`, and answers the rest at once — each with its call number.
    private actor Reads {
        private(set) var calls = 0
        private var held: CheckedContinuation<Void, Never>?

        var isHolding: Bool { held != nil }

        func next() async -> Int {
            calls += 1
            let call = calls
            if call == 2 {
                await withCheckedContinuation { held = $0 }
            }
            return call
        }

        func release() {
            held?.resume()
            held = nil
        }
    }

    @Test("A local change shows at once")
    func applyShows() async {
        let state = ActivityScreenState<Int>()
        await state.load(ActivityRead(cached: { nil }, live: { 1 }))

        state.apply { $0 + 10 }

        #expect(state.value == 11)
    }

    @Test("Nothing is applied before the first payload")
    func applyBeforeLoad() {
        let state = ActivityScreenState<Int>()
        state.apply { _ in 5 }
        #expect(state.value == nil)
    }

    @Test("A read sent before a local change is read again rather than shown over it")
    func staleReadIsRetried() async {
        let reads = Reads()
        let state = ActivityScreenState<Int>()
        await state.load(ActivityRead(cached: { nil }, live: { await reads.next() }))
        #expect(state.value == 1)

        let reload = Task { await state.reload() }
        while !(await reads.isHolding) { await Task.yield() }

        state.apply { _ in 99 }
        // A second refresh asked for meanwhile joins the one in flight.
        await state.reload()
        #expect(state.value == 99)

        await reads.release()
        await reload.value

        #expect(state.value == 3)
        #expect(await reads.calls == 3)
    }
}
