import Foundation
import ImageIO
import OSLog

/// What the share extension leaves for the app: one folder per share in the App Group's `Inbox/`, holding the shared files and a `manifest.json` naming them and what was chosen for them.
///
/// The extension only writes and the app only drains, so the extension never opens the SwiftData store or holds a session. A share's manifest is written last: a folder without one is a share still being written, or one the extension was killed in the middle of, and the app leaves it alone until it is old enough to be abandoned.
nonisolated struct ShareInbox: Sendable {

    private static let log = Logger(subsystem: "com.familyrecord.ios", category: "share")

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// The inbox in the shared container, or nil when the App Group entitlement is missing.
    static func shared() -> ShareInbox? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetStore.appGroupIdentifier
        ) else {
            log.error("App Group is unavailable; the share inbox is unreachable")
            return nil
        }
        return ShareInbox(directory: container.appendingPathComponent("Inbox", isDirectory: true))
    }

    /// One share as the app finds it.
    struct Share: Sendable {
        let folder: URL
        var manifest: ShareManifest

        func url(of item: ShareManifest.Item) -> URL {
            folder.appendingPathComponent(item.file, isDirectory: false)
        }
    }

    // MARK: - Writing (the extension)

    /// A new, empty folder for one share's files.
    func makeShareFolder() throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes the manifest that makes a folder a share. Atomic, so the app never reads half of one.
    func writeManifest(_ manifest: ShareManifest, in folder: URL) throws {
        let data = try Self.encoder.encode(manifest)
        try data.write(to: Self.manifestURL(in: folder), options: [.atomic])
    }

    // MARK: - Draining (the app)

    /// Every finished share, oldest first. Unfinished folders older than `abandonAfter` are deleted on the way: the extension that was writing them is long gone.
    func pending(now: Date = Date(), abandonAfter: TimeInterval = 24 * 60 * 60) -> [Share] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var shares: [Share] = []
        for folder in folders {
            let manifestURL = Self.manifestURL(in: folder)
            guard let data = try? Data(contentsOf: manifestURL) else {
                let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
                if now.timeIntervalSince(created) > abandonAfter {
                    remove(folder)
                }
                continue
            }
            do {
                let manifest = try Self.decoder.decode(ShareManifest.self, from: data)
                guard manifest.version == ShareManifest.currentVersion else {
                    Self.log.error("Dropping a share written by another version")
                    remove(folder)
                    continue
                }
                shares.append(Share(folder: folder, manifest: manifest))
            } catch {
                Self.log.error("Dropping an unreadable share: \(String(describing: error), privacy: .public)")
                remove(folder)
            }
        }
        return shares.sorted { $0.manifest.createdAt < $1.manifest.createdAt }
    }

    /// Keeps only `remaining` of a share's items, deleting the others' files — or the whole share when nothing remains.
    func keep(_ remaining: [ShareManifest.Item], of share: Share) {
        guard !remaining.isEmpty else {
            remove(share.folder)
            return
        }
        let kept = Set(remaining.map(\.file))
        for item in share.manifest.items where !kept.contains(item.file) {
            try? FileManager.default.removeItem(at: share.url(of: item))
        }
        var manifest = share.manifest
        manifest.items = remaining
        do {
            try writeManifest(manifest, in: share.folder)
        } catch {
            Self.log.error("Couldn't rewrite a share's manifest: \(String(describing: error), privacy: .public)")
        }
    }

    func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Everything, finished or not. Signing out empties the inbox along with the widgets: a share belongs to the account that made it.
    func removeAll() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Self.log.error("Share inbox removal failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func manifestURL(in folder: URL) -> URL {
        folder.appendingPathComponent("manifest.json", isDirectory: false)
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

/// One share: its files and what the share sheet chose for all of them. People and tags are server ids, the only ids the widget snapshot carries.
nonisolated struct ShareManifest: Codable, Equatable, Sendable {

    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var createdAt: Date
    /// The account whose snapshot the sheet was showing. The app drops a share made under anyone else.
    var ownerUserId: Int
    var personIds: [Int]
    var tagIds: [Int]
    var caption: String
    var items: [Item]

    nonisolated struct Item: Codable, Equatable, Hashable, Sendable {
        enum Kind: String, Codable, Sendable {
            case photo
            case video
        }

        /// A file name inside the share's folder.
        var file: String
        var kind: Kind
        /// From the file's own metadata, read where the file was copied. Nil when it carries none; the app then dates it as an in-app pick would.
        var captureDate: Date?
    }
}

/// When a photo was taken, from the file's own EXIF. Shared because the share extension reads it from the file it copied, and the app from the bytes the picker gave it.
nonisolated enum CaptureDate {

    static func from(data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return from(source)
    }

    /// Reads only the metadata, never the pixels: the share extension has little memory to spare.
    static func from(fileURL: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        return from(source)
    }

    private static func from(_ source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = (exif[kCGImagePropertyExifDateTimeOriginal]
                              ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String
        else {
            return nil
        }
        return exifDate(from: original)
    }

    /// EXIF's own date spelling — colons in the date, not only the time. Parsed against a fixed POSIX locale, or a device set to a non-Gregorian calendar reads the digits as its own era.
    static func exifDate(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: string)
    }
}
