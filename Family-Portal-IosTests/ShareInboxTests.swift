import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Family_Portal_Ios

@Suite("Share inbox")
@MainActor
struct ShareInboxTests {

    private static func makeInbox() -> ShareInbox {
        ShareInbox(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxTests-\(UUID().uuidString)", isDirectory: true))
    }

    /// A share as the extension writes one: each file in a numbered subfolder, then the manifest.
    private static func writeShare(
        in inbox: ShareInbox,
        ownerUserId: Int = 1,
        personIds: [Int] = [],
        caption: String = "",
        files: [(name: String, data: Data, kind: ShareManifest.Item.Kind)],
        createdAt: Date = Date()
    ) throws -> URL {
        let folder = try inbox.makeShareFolder()
        var items: [ShareManifest.Item] = []
        for (index, file) in files.enumerated() {
            let itemFolder = folder.appendingPathComponent(String(index), isDirectory: true)
            try FileManager.default.createDirectory(at: itemFolder, withIntermediateDirectories: true)
            try file.data.write(to: itemFolder.appendingPathComponent(file.name))
            items.append(ShareManifest.Item(file: "\(index)/\(file.name)", kind: file.kind, captureDate: nil))
        }
        try inbox.writeManifest(
            ShareManifest(createdAt: createdAt, ownerUserId: ownerUserId, personIds: personIds, tagIds: [], caption: caption, items: items),
            in: folder
        )
        return folder
    }

    // MARK: - The inbox

    @Test("A finished share is pending, with its manifest as written")
    func finishedShareIsPending() throws {
        let inbox = Self.makeInbox()
        defer { inbox.removeAll() }
        _ = try Self.writeShare(in: inbox, personIds: [7], caption: "Beach", files: [("a.jpg", Data([1]), .photo)])

        let shares = inbox.pending()
        #expect(shares.count == 1)
        #expect(shares.first?.manifest.personIds == [7])
        #expect(shares.first?.manifest.caption == "Beach")
        let item = try #require(shares.first?.manifest.items.first)
        #expect(FileManager.default.fileExists(atPath: try #require(shares.first).url(of: item).path))
    }

    /// The manifest is written last, so a folder without one is a share the extension is still copying.
    @Test("A folder still being written is left alone until it's abandoned")
    func unfinishedShareWaits() throws {
        let inbox = Self.makeInbox()
        defer { inbox.removeAll() }
        let folder = try inbox.makeShareFolder()

        #expect(inbox.pending().isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.path))

        #expect(inbox.pending(now: Date().addingTimeInterval(2 * 24 * 60 * 60)).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("Shares drain oldest first")
    func oldestFirst() throws {
        let inbox = Self.makeInbox()
        defer { inbox.removeAll() }
        _ = try Self.writeShare(in: inbox, caption: "second", files: [("a.jpg", Data([1]), .photo)], createdAt: Date())
        _ = try Self.writeShare(in: inbox, caption: "first", files: [("a.jpg", Data([1]), .photo)], createdAt: Date().addingTimeInterval(-60))

        #expect(inbox.pending().map(\.manifest.caption) == ["first", "second"])
    }

    @Test("Keeping some items deletes the others' files and rewrites the manifest")
    func keepingSomeItems() throws {
        let inbox = Self.makeInbox()
        defer { inbox.removeAll() }
        _ = try Self.writeShare(in: inbox, files: [("a.jpg", Data([1]), .photo), ("b.mov", Data([2]), .video)])
        let share = try #require(inbox.pending().first)
        let video = try #require(share.manifest.items.last)
        let photo = try #require(share.manifest.items.first)

        inbox.keep([video], of: share)

        let after = try #require(inbox.pending().first)
        #expect(after.manifest.items == [video])
        #expect(!FileManager.default.fileExists(atPath: share.url(of: photo).path))
        #expect(FileManager.default.fileExists(atPath: share.url(of: video).path))
    }

    @Test("Keeping nothing removes the share")
    func keepingNothing() throws {
        let inbox = Self.makeInbox()
        defer { inbox.removeAll() }
        let folder = try Self.writeShare(in: inbox, files: [("a.jpg", Data([1]), .photo)])
        let share = try #require(inbox.pending().first)

        inbox.keep([], of: share)

        #expect(inbox.pending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("Signing out empties the inbox")
    func removeAllEmpties() throws {
        let inbox = Self.makeInbox()
        _ = try Self.writeShare(in: inbox, files: [("a.jpg", Data([1]), .photo)])
        _ = try inbox.makeShareFolder()

        inbox.removeAll()

        #expect(!FileManager.default.fileExists(atPath: inbox.directory.path))
        #expect(inbox.pending().isEmpty)
    }

    // MARK: - Draining

    private static let contributor = FamilyAccess(
        families: [FamilyRefDTO(id: 9, role: FamilyAccess.contribute, isPrimary: true)],
        primaryFamilyId: 9
    )

    @Test("A drained share becomes photos with its people and caption, and leaves the inbox")
    func drainImportsPhotos() async throws {
        let inbox = Self.makeInbox()
        defer { inbox.removeAll() }
        let context = try TestStore.makeContext()
        let emma = Person(remoteId: "7", name: "Emma", gender: .female)
        let theo = Person(remoteId: "8", name: "Theo", gender: .male)
        context.insert(emma)
        context.insert(theo)
        try context.save()

        let jpeg = try PhotoImporterTests.jpeg(exifDateTimeOriginal: "2026:03:15 14:30:00")
        _ = try Self.writeShare(in: inbox, personIds: [7], caption: "Beach", files: [("a.jpg", jpeg, .photo), ("b.jpg", jpeg, .photo)])

        let flow = AddFlow()
        await ShareInboxDrain(makeInbox: { inbox }).drain(
            userId: 1, access: Self.contributor, addFlow: flow, isConnected: false,
            context: context, syncService: nil, errorPresenter: nil
        )

        let photos = try context.fetch(FetchDescriptor<Photo>())
        #expect(photos.count == 2)
        #expect(photos.allSatisfy { $0.title == "Beach" })
        #expect(photos.allSatisfy { $0.taggedPeople.map(\.name) == ["Emma"] })
        #expect(inbox.pending().isEmpty)
        #expect(flow.importer.progress == nil)
    }

    @Test("A share made under another account is dropped, not imported")
    func drainDropsAnotherAccountsShare() async throws {
        let inbox = Self.makeInbox()
        defer { inbox.removeAll() }
        let context = try TestStore.makeContext()
        let jpeg = try PhotoImporterTests.jpeg(exifDateTimeOriginal: nil)
        _ = try Self.writeShare(in: inbox, ownerUserId: 2, files: [("a.jpg", jpeg, .photo)])

        await ShareInboxDrain(makeInbox: { inbox }).drain(
            userId: 1, access: Self.contributor, addFlow: AddFlow(), isConnected: false,
            context: context, syncService: nil, errorPresenter: nil
        )

        #expect(try context.fetch(FetchDescriptor<Photo>()).isEmpty)
        #expect(inbox.pending().isEmpty)
    }

    /// A video can only upload online, and only once the server has said video is on; until then it waits in the inbox rather than being lost.
    @Test("A video waits in the inbox while video support is unknown")
    func drainKeepsVideoOffline() async throws {
        let inbox = Self.makeInbox()
        defer { inbox.removeAll() }
        let context = try TestStore.makeContext()
        let jpeg = try PhotoImporterTests.jpeg(exifDateTimeOriginal: nil)
        _ = try Self.writeShare(in: inbox, files: [("a.jpg", jpeg, .photo), ("b.mov", Data([0]), .video)])

        await ShareInboxDrain(makeInbox: { inbox }).drain(
            userId: 1, access: Self.contributor, addFlow: AddFlow(), isConnected: false,
            context: context, syncService: nil, errorPresenter: nil
        )

        #expect(try context.fetch(FetchDescriptor<Photo>()).count == 1)
        let left = try #require(inbox.pending().first)
        #expect(left.manifest.items.map(\.kind) == [.video])
    }

    @Test("A file that isn't an image fails and is dropped")
    func drainDropsUnreadable() async throws {
        let inbox = Self.makeInbox()
        defer { inbox.removeAll() }
        let context = try TestStore.makeContext()
        _ = try Self.writeShare(in: inbox, files: [("a.jpg", Data([0, 1, 2]), .photo)])

        await ShareInboxDrain(makeInbox: { inbox }).drain(
            userId: 1, access: Self.contributor, addFlow: AddFlow(), isConnected: false,
            context: context, syncService: nil, errorPresenter: nil
        )

        #expect(try context.fetch(FetchDescriptor<Photo>()).isEmpty)
        #expect(inbox.pending().isEmpty)
    }

    @Test("People in a family the account can only view are left off")
    func choicesKeepOnlyContributablePeople() throws {
        let context = try TestStore.makeContext()
        let own = Person(remoteId: "7", name: "Emma", gender: .female)
        own.familyRemoteId = 9
        let viewed = Person(remoteId: "8", name: "Cousin", gender: .male)
        viewed.familyRemoteId = 10
        context.insert(own)
        context.insert(viewed)
        try context.save()

        let manifest = ShareManifest(createdAt: Date(), ownerUserId: 1, personIds: [7, 8, 99], tagIds: [], caption: "", items: [])
        let choices = ShareInboxDrain.choices(for: manifest, access: Self.contributor, context: context)

        #expect(choices.personIds == [own.id])
    }

    @Test("A JPEG is uploaded as it is")
    func jpegKept() throws {
        let jpeg = try PhotoImporterTests.jpeg(exifDateTimeOriginal: nil)
        #expect(PhotoImporter.uploadable(jpeg) == jpeg)
    }

    /// The server takes JPEG, PNG and GIF; a camera's HEIC original (TIFF here, which every simulator can write) has to become a JPEG first, keeping when it was taken.
    @Test("Another image type becomes a JPEG that keeps its capture date")
    func otherTypesBecomeJPEG() throws {
        let jpeg = try PhotoImporterTests.jpeg(exifDateTimeOriginal: "2026:03:15 14:30:00")
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let tiff = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(tiff, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        #expect(CGImageDestinationFinalize(destination))

        let converted = try #require(PhotoImporter.uploadable(tiff as Data))
        let convertedSource = try #require(CGImageSourceCreateWithData(converted as CFData, nil))
        #expect(CGImageSourceGetType(convertedSource) as String? == UTType.jpeg.identifier)
        #expect(CaptureDate.from(data: converted) == CaptureDate.from(data: jpeg))
    }

    @Test("Shared summary counts photos and videos")
    func summaryWords() {
        #expect(ShareCopy.summary(photos: 3, videos: 0) == "3 photos")
        #expect(ShareCopy.summary(photos: 0, videos: 1) == "1 video")
        #expect(ShareCopy.summary(photos: 1, videos: 2) == "1 photo and 2 videos")
    }
}
