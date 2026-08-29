import Foundation
import OSLog

nonisolated struct ActivitySnapshotKey: Hashable, Sendable {
    let rawValue: String

    init(_ proc: RPCMethod, _ ids: Int...) {
        rawValue = ([proc.rawValue] + ids.map(String.init)).joined(separator: "-")
    }

    /// Every key this app builds is a proc name and some integers, and this is what stands between a key and the file system, so anything else is refused.
    var fileName: String {
        let safe = rawValue.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" ? character : "_"
        }
        return String(safe) + ".json"
    }
}

nonisolated struct ActivitySnapshot<Value: Sendable>: Sendable {
    let value: Value
    let fetchedAt: Date
}

/// Reads are cached and writes stay online: replaying a stale write would report a success that never happened, while stale data is safe to read. An actor because the file work has no business on the main thread.
actor ActivitySnapshotCache {

    static let shared = ActivitySnapshotCache()

    private let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ActivitySnapshots", isDirectory: true)
    }

    // MARK: - Reads

    /// The last payload seen for this read, decoded, or `nil` if there has never been one — which is a different screen from "the family has none of these".
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
            // A payload this build can no longer read would fail on every open until the network happened to be up. Each read is its own file, so dropping one costs only that screen.
            AppLog.activities.error(
                "Discarding unreadable snapshot \(key.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    // MARK: - Writes

    /// Banks the raw response body exactly as the server sent it, so the response types stay `Decodable`-only and a field this build ignores survives for the build that reads it.
    func store(_ data: Data, key: ActivitySnapshotKey) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(key.fileName), options: .atomic)
        } catch {
            AppLog.activities.error(
                "Could not cache \(key.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Drops every cached read. `LocalDataReset.erase(.everything)` needs this because nothing in the pull reconciles the cache.
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

    /// When the payload was written — the file's own modification date, so the cached bytes stay exactly the response.
    private func modificationDate(of url: URL) -> Date {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }
}
