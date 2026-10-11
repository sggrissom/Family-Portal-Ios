import Foundation
import OSLog

/// The widgets' directory in the App Group container: `snapshot.json` and the `images/` it names. The app writes it, the extension only reads it.
///
/// The directory is the whole of what a widget knows about an account, which is why signing out is one `removeAll()`.
nonisolated struct WidgetStore: Sendable {

    static let appGroupIdentifier = "group.com.familyrecord.ios"

    private static let log = Logger(subsystem: "com.familyrecord.ios", category: "widgets")

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// The store in the shared container, or nil when the App Group entitlement is missing — the app then simply publishes nothing.
    static func shared() -> WidgetStore? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            log.error("App Group \(appGroupIdentifier, privacy: .public) is unavailable; widgets get nothing")
            return nil
        }
        return WidgetStore(directory: container.appendingPathComponent("Widgets", isDirectory: true))
    }

    var snapshotURL: URL { directory.appendingPathComponent("snapshot.json", isDirectory: false) }
    var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }

    func imageURL(_ name: String) -> URL {
        imagesDirectory.appendingPathComponent(name, isDirectory: false)
    }

    // MARK: - Reading

    /// nil for no snapshot, one that cannot be decoded, or one written by a build that speaks another version.
    func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        do {
            let snapshot = try Self.decoder.decode(WidgetSnapshot.self, from: data)
            guard snapshot.version == WidgetSnapshot.currentVersion else { return nil }
            return snapshot
        } catch {
            Self.log.error("Widget snapshot unreadable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func hasImage(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: imageURL(name).path)
    }

    // MARK: - Writing

    /// Atomic, so the widget never reads half a snapshot. Readable after the first unlock: a timeline reloads while the phone is locked, and the Lock Screen and CarPlay are exactly where it is read.
    func write(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: [.atomic])
        protect(snapshotURL)
    }

    func writeImage(_ data: Data, named name: String) throws {
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        let url = imageURL(name)
        try data.write(to: url, options: [.atomic])
        protect(url)
    }

    /// Deletes every image the latest snapshot no longer names.
    func pruneImages(keeping names: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path) else { return }
        for file in files where !names.contains(file) {
            try? FileManager.default.removeItem(at: imageURL(file))
        }
    }

    /// Everything, snapshot and images alike. A widget with no snapshot shows the signed-out state.
    func removeAll() {
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            Self.log.error("Widget store removal failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func protect(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// How far the Shuffle button has moved the Memory widget along its pool. In the App Group's defaults, because the button runs in the extension and the widget reads it on its next reload.
nonisolated enum WidgetShuffle {

    private static let key = "memoryShuffleOffset"

    static func offset(in defaults: UserDefaults? = UserDefaults(suiteName: WidgetStore.appGroupIdentifier)) -> Int {
        defaults?.integer(forKey: key) ?? 0
    }

    static func advance(in defaults: UserDefaults? = UserDefaults(suiteName: WidgetStore.appGroupIdentifier)) {
        guard let defaults else { return }
        // Wraps long before overflow; only its value modulo the pool matters.
        defaults.set((defaults.integer(forKey: key) + 1) % 1_000_000, forKey: key)
    }
}
