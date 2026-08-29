import Foundation
import OSLog

nonisolated struct SyncQueueStore: Sendable {

    /// The `UserDefaults` key the queue used to be written to; a build that upgrades still has to find whatever was pending there. See `load()`.
    private static let legacyStorageKey = "com.familyrecord.syncQueue"

    private let fileURL: URL
    /// `UserDefaults` is thread-safe but not marked `Sendable`, and this store is read off whatever actor the queue runs on.
    nonisolated(unsafe) private let legacyDefaults: UserDefaults

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

    /// On the first launch of a build that has this file, any legacy `UserDefaults` queue is adopted — those are local changes the server has never heard about. The migration runs once.
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
            // The whole queue is one array, so a decode failure costs every pending change. If it ever does fail, an empty queue is the only honest answer.
            AppLog.queue.error(
                "Failed to load the \(source, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return []
        }
    }

    // MARK: - Writing

    /// Replaces the stored queue, atomically: a write torn by a crash would leave an array `load()` cannot decode, costing the whole backlog.
    func save(_ operations: [PendingOperation]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(operations)
            try data.write(to: fileURL, options: [.atomic])

            // A sync can run from the background after a reboot, and `.complete` would make the file unreadable until someone unlocks the phone.
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
