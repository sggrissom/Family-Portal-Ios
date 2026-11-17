import Foundation
import OSLog
import SwiftData

nonisolated enum ActivityStoreError: Error, LocalizedError, Equatable {
    /// The activity store could not be opened on disk, so nothing saved now would survive a relaunch.
    case unavailable
    /// The local write itself failed; nothing was saved.
    case saveFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Results can't be saved on this phone right now. Restart the app and try again."
        case .saveFailed:
            return "That couldn't be saved on this phone. Nothing was changed."
        case .notFound:
            return "That performance isn't on this phone anymore."
        }
    }
}

/// The account a performance or outbox entry belongs to, and the family it was recorded in.
nonisolated struct ActivityScope: Hashable, Sendable {
    let userId: Int
    let familyId: Int
}

/// Durable, local-first storage for competition results: `LocalPerformance` rows and the outbox that carries their changes to the server, written together in one transaction. A save here is what "Saved" means; reaching the server is the outbox's job, later.
///
/// Its own SwiftData store, apart from `DataStore`: a store that fails to open is set aside (`recoveredStoreURL`) and a fresh one opened, so neither the family's records nor the app launch depend on it, and the set-aside file can still be recovered rather than read as "no pending work".
@MainActor
final class ActivityLocalStore {

    static let shared = ActivityLocalStore.open()

    nonisolated static func makeSchema() -> Schema {
        Schema([LocalPerformance.self, ActivityOutboxMutation.self, PreparedCompetition.self])
    }

    let context: ModelContext
    /// `false` when even a fresh store could not be opened on disk, and this one lives in memory: writes then fail with `unavailable` rather than claim a save that a relaunch would lose.
    let isDurable: Bool
    /// Where an unreadable store was moved to, when one was.
    let recoveredStoreURL: URL?

    /// The save step, replaceable so tests can prove a failed save leaves nothing behind.
    var persist: (ModelContext) throws -> Void = { try $0.save() }

    init(container: ModelContainer, isDurable: Bool, recoveredStoreURL: URL? = nil) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.isDurable = isDurable
        self.recoveredStoreURL = recoveredStoreURL
    }

    static func inMemory() -> ActivityLocalStore {
        let configuration = ModelConfiguration("ActivitiesInMemory", schema: makeSchema(), isStoredInMemoryOnly: true)
        // An in-memory container failing to open is not something to recover from.
        let container = try! ModelContainer(for: makeSchema(), configurations: [configuration])
        return ActivityLocalStore(container: container, isDurable: true)
    }

    /// Opens the store at `url`. One that cannot be opened is moved aside, never deleted, and a fresh one is opened in its place.
    static func open(at url: URL = defaultURL(), fileManager: FileManager = .default) -> ActivityLocalStore {
        let schema = makeSchema()
        func makeContainer() throws -> ModelContainer {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            return try ModelContainer(for: schema, configurations: [ModelConfiguration("Activities", schema: schema, url: url)])
        }

        do {
            return ActivityLocalStore(container: try makeContainer(), isDurable: true)
        } catch {
            AppLog.activities.error("The activity store would not open: \(String(describing: error), privacy: .public)")
        }

        let quarantined = quarantine(url, fileManager: fileManager)
        do {
            return ActivityLocalStore(container: try makeContainer(), isDurable: true, recoveredStoreURL: quarantined)
        } catch {
            AppLog.activities.error("A fresh activity store would not open either: \(String(describing: error), privacy: .public)")
            let configuration = ModelConfiguration("ActivitiesFallback", schema: schema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: schema, configurations: [configuration])
            return ActivityLocalStore(container: container, isDurable: false, recoveredStoreURL: quarantined)
        }
    }

    nonisolated static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Activities", isDirectory: true).appendingPathComponent("Activities.store")
    }

    /// Moves the store and its SQLite side files into a dated folder beside it. Returns the moved store's URL.
    private static func quarantine(_ url: URL, fileManager: FileManager) -> URL? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = url.deletingLastPathComponent().appendingPathComponent("Unreadable-\(stamp)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: url.path + suffix)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.moveItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
            }
            AppLog.activities.error("Set aside an unreadable activity store at \(folder.lastPathComponent, privacy: .public)")
            return folder.appendingPathComponent(url.lastPathComponent)
        } catch {
            AppLog.activities.error("Could not set aside the activity store: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Reading

    func performance(_ localId: UUID) -> LocalPerformance? {
        fetchFirst(FetchDescriptor<LocalPerformance>(predicate: #Predicate { $0.localId == localId }))
    }

    func performance(serverId: Int, userId: Int) -> LocalPerformance? {
        let target: Int? = serverId
        return fetchFirst(FetchDescriptor<LocalPerformance>(
            predicate: #Predicate { $0.serverId == target && $0.ownerUserId == userId }
        ))
    }

    /// The performances at one competition as this account should see them: local changes included, local deletes left out.
    func performances(eventId: Int, userId: Int) -> [LocalPerformance] {
        fetch(FetchDescriptor<LocalPerformance>(
            predicate: #Predicate { $0.eventId == eventId && $0.ownerUserId == userId && !$0.isDeleted },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    /// This account's outbox, oldest first.
    func mutations(userId: Int) -> [ActivityOutboxMutation] {
        fetch(FetchDescriptor<ActivityOutboxMutation>(
            predicate: #Predicate { $0.ownerUserId == userId },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    func mutations(for performanceLocalId: UUID) -> [ActivityOutboxMutation] {
        fetch(FetchDescriptor<ActivityOutboxMutation>(
            predicate: #Predicate { $0.performanceLocalId == performanceLocalId },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    /// Accounts with changes still on this phone that the server has not seen. A sign-in as someone else leaves them alone (they are never shown to the new account), so they can still be sent when their own account comes back.
    func accountsWithUnsyncedWork() -> Set<Int> {
        Set(fetch(FetchDescriptor<ActivityOutboxMutation>()).map(\.ownerUserId))
    }

    func preparedCompetition(eventId: Int, userId: Int) -> PreparedCompetition? {
        let key = PreparedCompetition.key(ownerUserId: userId, eventId: eventId)
        return fetchFirst(FetchDescriptor<PreparedCompetition>(predicate: #Predicate { $0.key == key }))
    }

    // MARK: - Local writes

    /// Saves a performance on this phone and queues it for the server, in one transaction: both are written or neither is.
    /// - Parameters:
    ///   - localId: The performance being edited; `nil` creates one.
    ///   - expectedRevision: For a performance the server already has, the revision the editor opened.
    @discardableResult
    func save(
        _ snapshot: PerformanceSnapshot,
        localId: UUID?,
        scope: ActivityScope,
        eventId: Int,
        entryId: Int,
        now: Date = Date()
    ) throws -> LocalPerformance {
        try requireDurable()

        let performance: LocalPerformance
        if let localId {
            guard let existing = self.performance(localId), existing.ownerUserId == scope.userId, !existing.isDeleted else {
                throw ActivityStoreError.notFound
            }
            performance = existing
        } else {
            performance = LocalPerformance(
                ownerUserId: scope.userId,
                familyId: scope.familyId,
                serverId: nil,
                eventId: eventId,
                entryId: entryId,
                snapshot: snapshot,
                serverRevision: 0,
                createdAt: now
            )
            context.insert(performance)
        }

        try transaction {
            try performance.setSnapshot(snapshot)
            performance.localGeneration += 1
            try enqueueSave(of: performance, snapshot: snapshot, now: now)
        }
        return performance
    }

    /// Deletes a performance on this phone and queues the delete. One the server never heard of — created here, never sent — simply goes, with its queued create.
    func delete(_ localId: UUID, userId: Int, now: Date = Date()) throws {
        try requireDurable()
        guard let performance = performance(localId), performance.ownerUserId == userId, !performance.isDeleted else {
            throw ActivityStoreError.notFound
        }
        let queued = mutations(for: localId)

        try transaction {
            if performance.serverId == nil && !queued.contains(where: \.mayHaveBeenSent) {
                for mutation in queued { context.delete(mutation) }
                context.delete(performance)
                return
            }

            // Saves not yet sent are superseded by the delete; anything that may have reached the server stays, so the delete is sent after it.
            for mutation in queued where mutation.kind == .save && !mutation.mayHaveBeenSent {
                context.delete(mutation)
            }
            let remaining = queued.filter { $0.kind != .save || $0.mayHaveBeenSent }
            performance.isDeleted = true
            performance.localGeneration += 1
            context.insert(ActivityOutboxMutation(
                ownerUserId: performance.ownerUserId,
                familyId: performance.familyId,
                performanceLocalId: localId,
                kind: .delete,
                snapshotData: nil,
                generation: performance.localGeneration,
                expectedRevision: remaining.isEmpty ? performance.serverRevision : nil,
                dependsOnMutationId: remaining.last?.id,
                createdAt: now
            ))
        }
    }

    /// Coalesces into a save nobody has sent yet; otherwise queues another, after the last one.
    private func enqueueSave(of performance: LocalPerformance, snapshot: PerformanceSnapshot, now: Date) throws {
        let data = try PerformanceSnapshot.encoder.encode(snapshot)
        let queued = mutations(for: performance.localId)

        if let unsent = queued.last, unsent.kind == .save, !unsent.mayHaveBeenSent {
            unsent.snapshotData = data
            unsent.generation = performance.localGeneration
            return
        }

        context.insert(ActivityOutboxMutation(
            ownerUserId: performance.ownerUserId,
            familyId: performance.familyId,
            performanceLocalId: performance.localId,
            kind: .save,
            snapshotData: data,
            generation: performance.localGeneration,
            // A create has no revision; an edit after a queued change learns its revision when that change is acknowledged.
            expectedRevision: queued.isEmpty && performance.serverId != nil ? performance.serverRevision : nil,
            dependsOnMutationId: queued.last?.id,
            createdAt: now
        ))
    }

    // MARK: - Server copies

    /// Merges a competition's performances as the server returned them. A pull is a snapshot that may be older than what the phone already holds, so:
    /// - a performance with local changes, or deleted here, is left alone;
    /// - a copy is replaced only by one at least as new (`revision`), and only by a read that began after the phone last heard about it;
    /// - a performance missing from the read is dropped only when it has no local changes and was last heard of before the read began.
    func mergeServerPerformances(
        _ details: [AppearanceDetailDTO],
        eventId: Int,
        userId: Int,
        readStartedAt: Date
    ) throws {
        try requireDurable()
        let local = fetch(FetchDescriptor<LocalPerformance>(
            predicate: #Predicate { $0.eventId == eventId && $0.ownerUserId == userId }
        ))
        var byServerId: [Int: LocalPerformance] = [:]
        for performance in local {
            if let serverId = performance.serverId { byServerId[serverId] = performance }
        }

        try transaction {
            var seen = Set<Int>()
            for detail in details where detail.appearance.eventId == eventId {
                seen.insert(detail.id)
                if let existing = byServerId[detail.id] {
                    guard !existing.hasUnsyncedChanges, !existing.isDeleted else { continue }
                    if let heard = existing.serverUpdatedAt, heard > readStartedAt { continue }
                    guard detail.appearance.revision >= existing.serverRevision else { continue }
                    try existing.setSnapshot(Self.snapshot(of: detail, keepingRowIdsFrom: existing.snapshot))
                    existing.entryId = detail.entry.id
                    existing.serverRevision = detail.appearance.revision
                    existing.serverUpdatedAt = readStartedAt
                } else {
                    let performance = LocalPerformance(
                        ownerUserId: userId,
                        familyId: detail.appearance.familyId,
                        serverId: detail.id,
                        eventId: eventId,
                        entryId: detail.entry.id,
                        snapshot: Self.snapshot(of: detail, keepingRowIdsFrom: nil),
                        serverRevision: detail.appearance.revision,
                        createdAt: detail.appearance.createdAt
                    )
                    performance.serverUpdatedAt = readStartedAt
                    context.insert(performance)
                }
            }

            for performance in local {
                guard let serverId = performance.serverId, !seen.contains(serverId) else { continue }
                guard !performance.hasUnsyncedChanges, !performance.isDeleted else { continue }
                if let heard = performance.serverUpdatedAt, heard > readStartedAt { continue }
                context.delete(performance)
            }
        }
    }

    /// The server's copy as a snapshot. Rows keep the local ids they had when the server's ids match, so a row on screen stays the same row.
    static func snapshot(of detail: AppearanceDetailDTO, keepingRowIdsFrom previous: PerformanceSnapshot?) -> PerformanceSnapshot {
        snapshot(detail.appearance, results: detail.results, photoIds: detail.photoIds, keepingRowIdsFrom: previous)
    }

    static func snapshot(of view: AppearanceViewDTO, keepingRowIdsFrom previous: PerformanceSnapshot?) -> PerformanceSnapshot {
        snapshot(view.appearance, results: view.results, photoIds: view.photoIds, keepingRowIdsFrom: previous)
    }

    private static func snapshot(
        _ appearance: AppearanceDTO,
        results: [ActivityResultDTO],
        photoIds: [Int],
        keepingRowIdsFrom previous: PerformanceSnapshot?
    ) -> PerformanceSnapshot {
        var previousIds: [Int: UUID] = [:]
        for row in previous?.results ?? [] {
            if let serverId = row.serverId { previousIds[serverId] = row.id }
        }
        let matchup = Matchup(appearance)
        return PerformanceSnapshot(
            occurredAt: appearance.occurredAt.serverDate,
            notes: appearance.notes,
            matchup: matchup.isRecorded ? matchup.input : nil,
            results: results.map { result in
                LocalResultRow(id: previousIds[result.id] ?? UUID(), serverId: result.id, input: ResultInputDTO(result))
            },
            photoIds: photoIds
        )
    }

    // MARK: - Outbox bookkeeping

    /// Records changes the outbox sender makes — freezing a request, an acknowledgement, a refusal — durably, or not at all.
    func commit(_ changes: () throws -> Void) throws {
        try requireDurable()
        try transaction(changes)
    }

    func mutation(_ id: UUID) -> ActivityOutboxMutation? {
        fetchFirst(FetchDescriptor<ActivityOutboxMutation>(predicate: #Predicate { $0.id == id }))
    }

    /// Applies the server's acknowledgement of `mutation` and removes it from the outbox. The server's id and revision are taken; the server's copy replaces the local one only when nothing newer was saved here meanwhile, so a late acknowledgement never undoes a later edit or clears its pending state.
    func acknowledge(
        _ mutation: ActivityOutboxMutation,
        serverId: Int,
        revision: Int,
        serverCopy: AppearanceViewDTO?,
        at now: Date
    ) throws {
        try commit {
            guard let performance = performance(mutation.performanceLocalId) else {
                context.delete(mutation)
                return
            }
            if mutation.kind == .delete {
                context.delete(mutation)
                context.delete(performance)
                return
            }
            if serverId > 0 { performance.serverId = serverId }
            performance.serverRevision = revision
            performance.acknowledgedGeneration = max(performance.acknowledgedGeneration, mutation.generation)
            performance.serverUpdatedAt = now
            if !performance.hasUnsyncedChanges, !performance.isDeleted, let serverCopy, serverCopy.appearance.revision >= revision {
                try performance.setSnapshot(Self.snapshot(of: serverCopy, keepingRowIdsFrom: performance.snapshot))
                performance.serverRevision = serverCopy.appearance.revision
                performance.entryId = serverCopy.appearance.entryId
            }
            context.delete(mutation)
        }
    }

    /// Entries paused for a sign-in go back in line once someone is signed in again.
    func resumeAfterSignIn(userId: Int) throws {
        let paused = mutations(userId: userId).filter { $0.status == .needsSignIn }
        guard !paused.isEmpty else { return }
        try commit {
            for mutation in paused { mutation.status = .pending }
        }
    }

    // MARK: - Preparation

    func recordPreparation(
        eventId: Int,
        userId: Int,
        update: (PreparedCompetition) -> Void
    ) throws {
        try requireDurable()
        let record: PreparedCompetition
        if let existing = preparedCompetition(eventId: eventId, userId: userId) {
            record = existing
        } else {
            record = PreparedCompetition(ownerUserId: userId, eventId: eventId)
            context.insert(record)
        }
        try transaction { update(record) }
    }

    // MARK: - Accounts

    /// For a sign-in as a different account: drops everything already on the server, for every account, and keeps only work the server has not seen, still under its own account.
    func discardSyncedData() throws {
        let pendingAccounts = accountsWithUnsyncedWork()
        let pendingPerformances = Set(fetch(FetchDescriptor<ActivityOutboxMutation>()).map(\.performanceLocalId))
        try transaction {
            for performance in fetch(FetchDescriptor<LocalPerformance>())
            where !pendingPerformances.contains(performance.localId) && !performance.hasUnsyncedChanges {
                context.delete(performance)
            }
            for record in fetch(FetchDescriptor<PreparedCompetition>()) where !pendingAccounts.contains(record.ownerUserId) {
                context.delete(record)
            }
        }
    }

    /// Everything one account left on this phone, sent or not — for an account that is gone, or an explicit choice to discard.
    func discardAll(userId: Int) throws {
        try transaction {
            for mutation in mutations(userId: userId) { context.delete(mutation) }
            for performance in fetch(FetchDescriptor<LocalPerformance>(predicate: #Predicate { $0.ownerUserId == userId })) {
                context.delete(performance)
            }
            for record in fetch(FetchDescriptor<PreparedCompetition>(predicate: #Predicate { $0.ownerUserId == userId })) {
                context.delete(record)
            }
        }
    }

    // MARK: - Internals

    private func requireDurable() throws {
        guard isDurable else { throw ActivityStoreError.unavailable }
    }

    /// Applies `changes` and saves them, or leaves the store exactly as it was.
    private func transaction(_ changes: () throws -> Void) throws {
        do {
            try changes()
            try persist(context)
        } catch {
            context.rollback()
            AppLog.activities.error("A local activity write failed: \(String(describing: error), privacy: .public)")
            if let storeError = error as? ActivityStoreError { throw storeError }
            throw ActivityStoreError.saveFailed(String(describing: error))
        }
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func fetchFirst<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> T? {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }
}
