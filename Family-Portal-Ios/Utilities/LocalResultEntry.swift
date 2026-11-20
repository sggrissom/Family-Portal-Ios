import Foundation

// Result entry against `ActivityLocalStore`: the pieces between the editor's drafts, the stored performance, and the competition page, kept apart from the views so they can be tested.

extension ResultDraft {
    /// A stored row, editable, keeping its identity.
    init(row: LocalResultRow) {
        self.init(
            id: row.id,
            kind: ActivityResultKind(rawValue: row.input.kind) ?? .adjudication,
            label: row.input.label,
            rankText: row.input.rank.map(String.init) ?? "",
            outOfText: row.input.outOf.map(String.init) ?? "",
            category: row.input.category,
            scoreText: row.input.score.map { $0 == $0.rounded() && abs($0) < 1e15 ? String(Int($0)) : String($0) } ?? "",
            personId: row.input.personId,
            notes: row.input.notes
        )
    }
}

extension ResultSheet {
    /// What a local save stores: the non-blank rows in screen order, each keeping its id and, when it came from the server, the server's id.
    static func rows(_ drafts: [ResultDraft], previous: [LocalResultRow]) -> [LocalResultRow] {
        var serverIds: [UUID: Int] = [:]
        for row in previous {
            if let serverId = row.serverId { serverIds[row.id] = serverId }
        }
        return drafts.filter { !$0.isBlank }.map { draft in
            LocalResultRow(id: draft.id, serverId: serverIds[draft.id], input: draft.input())
        }
    }
}

/// Where a performance saved on this phone stands with the server, as shown beside it.
nonisolated enum PerformanceSyncState: Equatable, Sendable {
    case synced
    case pending
    case needsSignIn
    case needsReview
    case failed

    /// The most pressing state among a performance's queued entries: anything needing someone outranks waiting.
    static func of(hasUnsyncedChanges: Bool, statuses: [ActivityMutationStatus]) -> PerformanceSyncState {
        if statuses.contains(.needsReview) { return .needsReview }
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.needsSignIn) { return .needsSignIn }
        if hasUnsyncedChanges || !statuses.isEmpty { return .pending }
        return .synced
    }

    var label: String? {
        switch self {
        case .synced: return nil
        case .pending: return "Saved on this phone · waiting to sync"
        case .needsSignIn: return "Saved on this phone · sign in to sync"
        case .needsReview: return "Changed on the website too · needs review"
        case .failed: return "Saved on this phone · couldn't sync"
        }
    }

    var systemImage: String {
        switch self {
        case .synced: return "checkmark.icloud"
        case .pending, .needsSignIn: return "icloud.and.arrow.up"
        case .needsReview, .failed: return "exclamationmark.icloud"
        }
    }
}

/// One performance on the competition page, from the local store.
struct LocalPerformanceRow {
    let detail: AppearanceDetailDTO
    let localId: UUID
    let snapshot: PerformanceSnapshot
    let serverRevision: Int
    let syncState: PerformanceSyncState
}

nonisolated enum LocalCompetition {

    /// A stand-in id for a performance the server has not acknowledged: negative, so it can never be a server id, and stable for as long as the app runs.
    static func displayId(serverId: Int?, localId: UUID) -> Int {
        if let serverId { return serverId }
        var hasher = Hasher()
        hasher.combine(localId)
        return -1 - Int(UInt32(truncatingIfNeeded: hasher.finalize()))
    }
}

extension LocalCompetition {
    /// The competition's performances as this account should see them, in the server's order. A routine the phone has no record of is taken from the server's copy of a performance of it; one it cannot name at all is left out rather than drawn wrong.
    @MainActor
    static func rows(
        store: ActivityLocalStore,
        eventId: Int,
        userId: Int,
        event: ActivityEventDTO,
        entries: [ActivityEntryDTO],
        serverAppearances: [AppearanceDetailDTO]
    ) -> [LocalPerformanceRow] {
        var entryById: [Int: ActivityEntryDTO] = [:]
        for detail in serverAppearances { entryById[detail.entry.id] = detail.entry }
        for entry in entries { entryById[entry.id] = entry }
        let summary = EventSummaryDTO(event)

        var shownServerIds = Set<Int>()
        let rows: [LocalPerformanceRow] = store.performances(eventId: eventId, userId: userId).compactMap { performance in
            guard let snapshot = performance.snapshot, let entry = entryById[performance.entryId] else { return nil }
            let statuses = store.mutations(for: performance.localId).map(\.status)
            // Independent queued edits can outlive the duplicate they were based on.
            let visibleServerId = performance.serverId.flatMap { shownServerIds.insert($0).inserted ? $0 : nil }
            return LocalPerformanceRow(
                detail: AppearanceDetailDTO(
                    local: snapshot,
                    id: displayId(serverId: visibleServerId, localId: performance.localId),
                    eventId: eventId,
                    familyId: performance.familyId,
                    revision: performance.serverRevision,
                    createdAt: performance.createdAt,
                    entry: entry,
                    event: summary
                ),
                localId: performance.localId,
                snapshot: snapshot,
                serverRevision: performance.serverRevision,
                syncState: PerformanceSyncState.of(hasUnsyncedChanges: performance.hasUnsyncedChanges, statuses: statuses)
            )
        }
        return rows.sorted { EventPerformances.order($0.detail, $1.detail) }
    }
}
