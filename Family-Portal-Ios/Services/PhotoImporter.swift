import Foundation
import ImageIO
import OSLog
import Photos
import PhotosUI
import SwiftData
import SwiftUI

/// Reads picked images into the store and hands them to the sync queue.
///
/// One instance, held by `AddFlow`, so every **+** imports the same way and one
/// progress bar covers every batch. Dependencies arrive on the call rather than at
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

    /// One picked item as the photo batch form shows it: the photo it became, whether a capture date was available, or that it could not be read.
    struct ImportEntry: Identifiable {
        let id: UUID
        let item: PhotosPickerItem
        var photoId: UUID?
        /// False when neither the library nor the file supplied a capture date and "now" stood in for it — which the form says, rather than silently dating the photo today.
        var hasCaptureDate = true
        var failed = false
        var isReading: Bool { photoId == nil && !failed }
    }

    /// What the batch form chose for a whole batch, applied to each photo once it has been read. A photo still being read when the form closes gets the same choices when it lands.
    struct BatchChoices {
        var personIds: Set<UUID> = []
        var caption = ""
        var tagRemoteIds: [Int] = []
        /// Per-photo dates the user changed, keyed by entry.
        var dates: [UUID: Date] = [:]

        var isEmpty: Bool {
            personIds.isEmpty && caption.trimmingCharacters(in: .whitespaces).isEmpty && tagRemoteIds.isEmpty && dates.isEmpty
        }
    }

    private(set) var entries: [UUID: ImportEntry] = [:]
    private var pendingChoices: [UUID: BatchChoices] = [:]
    private var applyContext: (context: ModelContext, syncService: SyncService?)?

    /// Adds `items` to whatever run is in flight, starting one if there isn't, and returns the entries the batch form lists. A second pick made mid-import extends the same bar rather than opening a competing one.
    /// Nobody is tagged here: who is in a batch is the form's question, asked after the photos are already on their way up.
    @discardableResult
    func importPicked(
        _ items: [PhotosPickerItem],
        into context: ModelContext,
        syncService: SyncService?,
        errorPresenter: ErrorPresenter?
    ) -> [UUID] {
        guard !items.isEmpty else { return [] }

        var next = progress ?? ImportProgress()
        next.total += items.count
        progress = next

        let batch = items.map { ImportEntry(id: UUID(), item: $0) }
        for entry in batch {
            entries[entry.id] = entry
        }

        Task {
            // The picker itself needs no permission. Library access is optional,
            // but lets us read dates Photos stores separately from the image file.
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            // Sequential on purpose: twenty full-resolution images decoded at once is the kind of memory spike that gets an app killed mid-import.
            for entry in batch {
                await read(entry.id, into: context, syncService: syncService)
                if progress?.isFinished == true {
                    finish(reportingTo: errorPresenter)
                }
            }
        }
        return batch.map(\.id)
    }

    /// Reads one entry again after a failure. Counted on its own, outside the run's progress.
    func retry(_ entryId: UUID, into context: ModelContext, syncService: SyncService?) {
        guard entries[entryId]?.failed == true else { return }
        entries[entryId]?.failed = false
        Task {
            await read(entryId, into: context, syncService: syncService, countsTowardProgress: false)
        }
    }

    /// Applies the form's choices to every entry that has become a photo, and holds them for the ones that have not.
    func apply(_ choices: BatchChoices, to entryIds: [UUID], context: ModelContext, syncService: SyncService?) {
        guard !choices.isEmpty else { return }
        applyContext = (context: context, syncService: syncService)
        for entryId in entryIds {
            if entries[entryId]?.photoId != nil {
                Task { await applyChoices(choices, to: entryId, context: context, syncService: syncService) }
            } else if entries[entryId]?.failed == false {
                pendingChoices[entryId] = choices
            }
        }
    }

    private func read(
        _ entryId: UUID,
        into context: ModelContext,
        syncService: SyncService?,
        countsTowardProgress: Bool = true
    ) async {
        guard let entry = entries[entryId] else { return }
        do {
            let imported = try await importOne(entry.item, into: context, syncService: syncService)
            entries[entryId]?.photoId = imported.photo.id
            entries[entryId]?.hasCaptureDate = imported.hasCaptureDate
            if countsTowardProgress { progress?.completed += 1 }

            if let choices = pendingChoices.removeValue(forKey: entryId) {
                let target = applyContext ?? (context: context, syncService: syncService)
                await applyChoices(choices, to: entryId, context: target.context, syncService: target.syncService)
            }
        } catch {
            AppLog.ui.error("Photo import failed: \(String(describing: error), privacy: .public)")
            entries[entryId]?.failed = true
            if countsTowardProgress {
                progress?.failed += 1
                if progress?.firstFailure == nil {
                    progress?.firstFailure = error
                }
            }
        }
    }

    private func applyChoices(_ choices: BatchChoices, to entryId: UUID, context: ModelContext, syncService: SyncService?) async {
        guard let photoId = entries[entryId]?.photoId,
              let photo = try? context.fetch(FetchDescriptor<Photo>(predicate: #Predicate<Photo> { $0.id == photoId })).first
        else { return }

        do {
            try await Self.queueDetails(choices, changedDate: choices.dates[entryId], for: photo, context: context, syncService: syncService)
        } catch {
            AppLog.ui.error("Couldn't queue photo details: \(String(describing: error), privacy: .public)")
        }
    }

    /// Queues what the batch form chose for one photo: people, then tags, then the caption and date. Each is queued *behind* the photo's own upload — each declares the photo as its dependency — so the queue holds them until the upload has answered with a remote id, the way person tags always have been.
    static func queueDetails(
        _ choices: BatchChoices,
        changedDate: Date?,
        for photo: Photo,
        context: ModelContext,
        syncService: SyncService?
    ) async throws {
        if !choices.personIds.isEmpty {
            let people = try context.fetch(FetchDescriptor<Person>())
                .filter { choices.personIds.contains($0.id) && !photo.taggedPeople.contains($0) }
            if !people.isEmpty {
                photo.taggedPeople.append(contentsOf: people)
                try await syncService?.addPeopleToPhoto(photo, people: people)
            }
        }
        if !choices.tagRemoteIds.isEmpty {
            try await syncService?.updatePhotoTags(photo, tagRemoteIds: choices.tagRemoteIds)
        }
        let caption = choices.caption.trimmingCharacters(in: .whitespaces)
        if !caption.isEmpty || changedDate != nil {
            if !caption.isEmpty { photo.title = caption }
            if let changedDate { photo.photoDate = changedDate.localRecordDay() }
            try context.save()
            // "keep" unless the date was changed: the upload already sent the resolved date.
            try await syncService?.updatePhoto(photo, keepingDate: changedDate == nil)
        }
    }

    private func importOne(
        _ item: PhotosPickerItem,
        into context: ModelContext,
        syncService: SyncService?
    ) async throws -> (photo: Photo, hasCaptureDate: Bool) {
        let (data, captureDate) = try await Self.load(item)
        let photo = Photo(
            title: "",
            descriptionText: "",
            photoDate: (captureDate ?? Date()).localWallClock(),
            imageData: data
        )
        context.insert(photo)
        try context.save()
        // Only queues: a finished import means every photo is on screen and queued, not that it is on the server.
        try await syncService?.uploadPhoto(photo)
        return (photo, captureDate != nil)
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

    /// A picked item's bytes and when it was taken: the library's date, which carries corrections made in Photos, else the file's own EXIF. Throws `unreadable` for anything that isn't an image.
    static func load(_ item: PhotosPickerItem) async throws -> (data: Data, captureDate: Date?) {
        guard let data = try await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
            throw ImportFailure.unreadable
        }
        return (data, libraryDate(for: item) ?? captureDate(from: data))
    }

    /// A limited library grant only covers assets the user explicitly allowed;
    /// selecting something in PhotosPicker does not extend that grant. Denied access is harmless.
    private static func libraryDate(for item: PhotosPickerItem) -> Date? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited,
              let identifier = item.itemIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            .firstObject?.creationDate
    }

    /// The capture date in the image's own EXIF.
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
