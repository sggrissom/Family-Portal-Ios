import Foundation
import SwiftData

@Model
final class Photo {
    var id: UUID
    var remoteId: String?

    @Attribute(.externalStorage)
    var imageData: Data?

    var title: String
    var descriptionText: String
    var photoDate: Date

    /// Ids of the `FamilyTag`s on this photo. Ids rather than a relationship because the server owns the pairing and both sides arrive from separate calls.
    var tagRemoteIds: [Int] = []
    /// The server id of the household the photo was shared to, which decides who may edit or delete it (`FamilyAccess`). `nil` until the first pull after upgrading, and for a photo imported offline — both read as the account's own.
    var familyRemoteId: Int? = nil

    /// A video is shown by its poster frame wherever a photo would be, with a play badge, and played on its own page. Everything below defaults so rows stored before video read as ready photos.
    /// `MediaKind`'s raw value. A plain `Int` rather than the enum so adding it migrates lightweight and a predicate can read it.
    var mediaKindRaw: Int = 0
    var durationMs: Int = 0
    /// The server's: 0 ready, 1 processing, 2 failed. A photo picked on this device reads 0 until it uploads.
    var status: Int = 0
    /// Why the server refused a video, worded for showing as is.
    var processingError: String = ""
    /// See `Milestone.hasExactDate` and `Milestone.recordTimeData`.
    var hasExactDate: Bool = true
    var recordTimeData: Data? = nil
    /// The `PHAsset.localIdentifier` this photo was imported from, when it was picked from the library **on this device**. Never synced: an identifier means nothing on another device, and the server has no field for it.
    /// It is how the library finder knows a library photo is already in the app. `nil` for photos imported before it existed, shared in, scanned, or pulled from the server — those are matched by capture time instead.
    var libraryAssetId: String? = nil

    @Relationship(inverse: \Person.photos)
    var taggedPeople: [Person]

    init(title: String, descriptionText: String, photoDate: Date, imageData: Data? = nil) {
        self.id = UUID()
        self.remoteId = nil
        self.imageData = imageData
        self.title = title
        self.descriptionText = descriptionText
        self.photoDate = photoDate
        self.taggedPeople = []
    }

    /// A kind this build doesn't know reads as a photo: its variants are still images.
    var mediaKind: MediaKind {
        get { MediaKind(rawValue: mediaKindRaw) ?? .photo }
        set { mediaKindRaw = newValue.rawValue }
    }

    var isVideo: Bool { mediaKind == .video }

    /// See `Milestone.dateText`.
    func dateText(_ style: Date.FormatStyle.DateStyle) -> String {
        hasExactDate ? photoDate.displayDay().formatted(date: style, time: .omitted) : (recordTime?.label ?? "")
    }

    var recordTime: RecordTime? {
        get { recordTimeData.flatMap { try? JSONDecoder().decode(RecordTime.self, from: $0) } }
        set {
            recordTimeData = newValue.flatMap { try? JSONEncoder().encode($0) }
            hasExactDate = newValue?.isExactDay ?? true
        }
    }
}
