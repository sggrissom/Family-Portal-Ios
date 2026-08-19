import Foundation
import OSLog

/// Names one cached read: the proc plus the arguments that distinguish it.
///
/// `GetSeasonOverview-41`, `GetPersonSeason-7-0`. The ids are what make two
/// calls to the same proc different reads, so a key that dropped them would
/// have one season's payload answering for another's.
nonisolated struct ActivitySnapshotKey: Hashable, Sendable {
    let rawValue: String

    init(_ proc: RPCMethod, _ ids: Int...) {
        rawValue = ([proc.rawValue] + ids.map(String.init)).joined(separator: "-")
    }

    /// Every key this app builds is a proc name and some integers, so this only
    /// ever has to hold that shape — but it is what stands between a key and the
    /// file system, so it refuses anything else rather than trusting the
    /// callers to stay well behaved.
    var fileName: String {
        let safe = rawValue.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" ? character : "_"
        }
        return String(safe) + ".json"
    }
}

/// One decoded read plus when it was fetched.
nonisolated struct ActivitySnapshot<Value: Sendable>: Sendable {
    let value: Value
    let fetchedAt: Date
}

/// Keeps the raw body of each activities read on disk, so a screen that has been
/// opened once still renders with no signal.
///
/// Activities are deliberately *not* in SwiftData or `SyncQueue` — the joins are
/// already done by the aggregate procs, and every write is a whole-set replace
/// with server-side cross-record validation that a device cannot predict, so a
/// queued activity write would report a success that never happened. But the
/// venue has no signal, and arriving at a competition to a blank app is the
/// failure the offline story exists to prevent. Reading stale data is safe in a
/// way that replaying stale writes is not, so the two halves get different
/// answers: reads are cached, writes stay online.
///
/// An actor because the file work has no business on the main thread and every
/// screen refreshes on appear.
actor ActivitySnapshotCache {

    static let shared = ActivitySnapshotCache()

    private let directory: URL
    private let fileManager = FileManager.default

    /// `directory` is injectable so tests never touch the app's real cache — the
    /// same reason `SyncQueue` takes a `UserDefaults`.
    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ActivitySnapshots", isDirectory: true)
    }

    // MARK: - Reads

    /// The last payload seen for this read, decoded, or `nil` if there has never
    /// been one.
    ///
    /// A `nil` here is "nothing cached", which is a different screen from "the
    /// family has none of these" — conflating the two is how the chat history
    /// bug read as *this family has no messages*. The caller keeps them apart.
    func load<Value: Decodable & Sendable>(
        _ type: Value.Type,
        key: ActivitySnapshotKey
    ) -> ActivitySnapshot<Value>? {
        let url = directory.appendingPathComponent(key.fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }

        do {
            let value = try APIClient.decode(Value.self, from: data)
            return ActivitySnapshot(value: value, fetchedAt: modificationDate(of: url))
        } catch {
            // A payload this build can no longer read is worse than none: it
            // would fail on every open until the network happened to be up.
            // Each read is its own file, so dropping one costs only that screen.
            AppLog.activities.error(
                "Discarding unreadable snapshot \(key.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    // MARK: - Writes

    /// Banks the raw response body, exactly as the server sent it. Storing the
    /// bytes rather than a re-encoding of the DTOs is what lets the response
    /// types stay `Decodable`-only, and means a field this build ignores is
    /// still there for the build that reads it.
    func store(_ data: Data, key: ActivitySnapshotKey) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(key.fileName), options: .atomic)
        } catch {
            // A cache that cannot be written is a slower app, not a broken one.
            AppLog.activities.error(
                "Could not cache \(key.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Drops every cached read.
    ///
    /// `LocalDataReset.erase(.everything)` calls this, and it is the same
    /// problem `LocalAccountOwner` exists for: nothing in the pull reconciles
    /// this cache, so a device that changes hands would otherwise show the
    /// previous account's season.
    func removeAll() {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            AppLog.activities.error(
                "Could not clear the activity snapshot cache: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Internals

    /// When the payload was written. The file's own modification date rather
    /// than a timestamp inside an envelope: an envelope would mean the cached
    /// bytes are no longer the response, and the whole point is that they are.
    private func modificationDate(of url: URL) -> Date {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }
}
