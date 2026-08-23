import Foundation
import OSLog

/// Where the pending-operation queue is kept between launches.
///
/// It used to be one JSON blob in `UserDefaults`, rewritten in full on every
/// mutation — every enqueue, every retry count, every dequeue. `UserDefaults` is
/// a preferences store: it is loaded into memory in its entirety, it is not meant
/// to hold a growing record, and a device that has been offline for a weekend can
/// accumulate a real backlog of operations there. Nothing about that was urgent
/// once photo bytes stopped travelling in the queue — the payloads left are small
/// JSON — but it was always the wrong drawer.
///
/// So the queue lives in Application Support as its own file, written atomically,
/// which is also what `ActivitySnapshotCache` does with the payloads it banks.
///
/// This is deliberately not SwiftData, the other option §33 named. The queue is
/// read and written as a whole array — `mergeOperationIfPossible` scans it,
/// `readyOperations` sorts it — so per-record storage buys nothing, and a queue
/// inside the same store it is trying to push would gain a schema migration on
/// `DataStore.container` for the trouble.
nonisolated struct SyncQueueStore: Sendable {

    /// The `UserDefaults` key the queue used to be written to. A build that
    /// upgrades still has to find whatever was pending there — see `load()`.
    private static let legacyStorageKey = "com.familyrecord.syncQueue"

    private let fileURL: URL
    private let legacyDefaults: UserDefaults

    /// Both are injectable so tests never touch the app's real queue, the same
    /// arrangement `ActivitySnapshotCache` has with its directory.
    init(fileURL: URL? = nil, legacyDefaults: UserDefaults = .standard) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.legacyDefaults = legacyDefaults
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SyncQueue.json", isDirectory: false)
    }

    // MARK: - Reading

    /// Everything still pending, in the order it was written.
    ///
    /// On the first launch of a build that has this file, there is no file and
    /// there may well be a queue in `UserDefaults`. Adopting it is not optional
    /// politeness: those operations are local changes the user has already made
    /// and the server has never heard about, so dropping them loses data that
    /// exists nowhere else. The migration runs once — the legacy key is cleared
    /// as soon as the file is written — and a fresh install simply finds neither.
    func load() -> [PendingOperation] {
        if let data = try? Data(contentsOf: fileURL) {
            return decode(data, source: "queue file")
        }

        guard let legacy = legacyDefaults.data(forKey: Self.legacyStorageKey) else {
            return []
        }

        let operations = decode(legacy, source: "legacy UserDefaults queue")
        AppLog.queue.info("Migrating \(operations.count) queued operations out of UserDefaults")
        save(operations)
        legacyDefaults.removeObject(forKey: Self.legacyStorageKey)
        return operations
    }

    private func decode(_ data: Data, source: String) -> [PendingOperation] {
        do {
            return try JSONDecoder().decode([PendingOperation].self, from: data)
        } catch {
            // The whole queue is one array, so a decode failure costs every
            // pending change on the device. `PendingOperation` is written to
            // survive a field it has never seen — `blockedCount` was added to it
            // after ship — but if it ever does fail, an empty queue is the only
            // honest answer.
            AppLog.queue.error(
                "Failed to load the \(source, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return []
        }
    }

    // MARK: - Writing

    /// Replaces the stored queue.
    ///
    /// Atomically, because this is called on every mutation including the ones
    /// that happen while a sync run is in flight: a write torn by a crash or a
    /// task cancellation would leave a half-written array that `load()` cannot
    /// decode, and that costs the whole backlog rather than one operation.
    func save(_ operations: [PendingOperation]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(operations)
            try data.write(to: fileURL, options: [.atomic])

            // Matches what `UserDefaults` gave these payloads before the move, and
            // is the strongest protection a queue may have: a sync can run from
            // the background after a reboot, and `.complete` would make the file
            // unreadable until someone unlocks the phone.
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
        } catch {
            AppLog.queue.error(
                "Failed to save the queue: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
