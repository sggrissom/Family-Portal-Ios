import Foundation
import ImageIO
import OSLog
import PhotosUI
import SwiftData
import SwiftUI

/// Reads picked images into the store and hands them to the sync queue.
///
/// Lifted out of `PhotoGalleryView` so the same import can run from anywhere the
/// quick-add menu is offered. Dependencies arrive on the call rather than at
/// `init`, because a view's `@State` is built before its `@Environment` can be
/// read — `@State private var importer = PhotoImporter()` is the whole wiring,
/// and the caller passes what it already holds.
@MainActor
@Observable
final class PhotoImporter {

    /// What a run has settled so far. A value type, so the accounting can be reasoned about — and tested — without a picker or a store.
    /// Named for the import rather than called `Progress`, which is a Foundation class.
    struct ImportProgress {
        var total = 0
        var completed = 0
        var failed = 0

        /// Kept so a lone failure can still report its own error, which is where the iCloud hint lives.
        var firstFailure: Error?

        var settled: Int { completed + failed }
        var isFinished: Bool { settled >= total }
    }

    /// Nil when nothing is importing. Hosts show a progress bar while it isn't.
    private(set) var progress: ImportProgress?

    /// Adds `items` to whatever run is in flight, starting one if there isn't. A second pick made mid-import extends the same bar rather than opening a competing one.
    ///
    /// `taggingTo` is the person an import made from their own screen belongs to. Without it a photo added from Ada's screen would not appear among Ada's photos, which is the only place the person who added it was looking.
    func importPicked(
        _ items: [PhotosPickerItem],
        into context: ModelContext,
        syncService: SyncService?,
        errorPresenter: ErrorPresenter?,
        taggingTo person: Person? = nil
    ) {
        guard !items.isEmpty else { return }

        var next = progress ?? ImportProgress()
        next.total += items.count
        progress = next

        Task {
            // Sequential on purpose: twenty full-resolution images decoded at once is the kind of memory spike that gets an app killed mid-import.
            for item in items {
                do {
                    try await importOne(item, into: context, syncService: syncService, taggingTo: person)
                    progress?.completed += 1
                } catch {
                    AppLog.ui.error("Photo import failed: \(String(describing: error), privacy: .public)")
                    progress?.failed += 1
                    if progress?.firstFailure == nil {
                        progress?.firstFailure = error
                    }
                }

                if progress?.isFinished == true {
                    finish(reportingTo: errorPresenter)
                }
            }
        }
    }

    private func importOne(
        _ item: PhotosPickerItem,
        into context: ModelContext,
        syncService: SyncService?,
        taggingTo person: Person?
    ) async throws {
        guard let data = try await item.loadTransferable(type: Data.self),
              UIImage(data: data) != nil else {
            throw ImportFailure.unreadable
        }

        let photo = Photo(
            title: "",
            descriptionText: "",
            photoDate: Self.captureDate(from: data) ?? Date(),
            imageData: data
        )
        context.insert(photo)
        try context.save()
        // Only queues: a finished import means every photo is on screen and queued, not that it is on the server.
        try await syncService?.uploadPhoto(photo)

        // After the upload is queued, never before: the tag operation's dependency is the photo's own local id, and the queue holds it back until the upload has answered with a remote one.
        if let person {
            photo.taggedPeople.append(person)
            try await syncService?.addPeopleToPhoto(photo, people: [person])
        }
    }

    /// Reports **once** for the whole run. A dozen alerts stacked behind each other is what per-photo reporting looks like for an iCloud batch.
    private func finish(reportingTo errorPresenter: ErrorPresenter?) {
        guard let settled = progress else { return }
        progress = nil

        guard settled.failed > 0 else { return }

        if settled.failed == 1, let failure = settled.firstFailure {
            errorPresenter?.report(failure, title: "Couldn't Add Photo")
        } else {
            errorPresenter?.report(
                message: "\(settled.failed) of \(settled.total) photos couldn't be added. Photos stored in iCloud need to finish downloading in Photos first.",
                title: "Some Photos Weren't Added"
            )
        }
    }

    enum ImportFailure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "That photo couldn't be read. If it's stored in iCloud, open it in Photos first and try again."
        }
    }

    /// Reads the capture date out of the picked image's own EXIF, avoiding `PHAsset`, which needs photo-library authorization the picker itself does not.
    static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
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
        exifDateFormatter.date(from: string)
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()
}
