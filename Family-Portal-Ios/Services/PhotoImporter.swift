import AVFoundation
import CoreTransferable
import Foundation
import ImageIO
import OSLog
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Reads picked images into the store and hands them to the sync queue. A picked video is uploaded there and then instead (`VideoUploadService`) and lands in the store once the server has it.
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

    /// Where an entry's bytes come from: the photo picker, or a file the share extension left in the App Group's inbox.
    enum Source {
        case picked(PhotosPickerItem)
        /// The file stays where it is until the drain that handed it over has heard how the import went.
        case file(URL, captureDate: Date?)
    }

    /// One picked item as the photo batch form shows it: the photo it became, whether a capture date was available, or that it could not be read.
    struct ImportEntry: Identifiable {
        let id: UUID
        let source: Source
        var photoId: UUID?
        /// False when neither the library nor the file supplied a capture date and "now" stood in for it — which the form says, rather than silently dating the photo today.
        var hasCaptureDate = true
        var failed = false
        /// A video, uploaded at once rather than queued, so its row shows how far it has got.
        var isVideo = false
        /// 0…1 while a video's bytes are going up.
        var uploadFraction: Double?
        /// Why it couldn't be added, when there is something more useful to say than "Failed" — a video too long, too large, or refused.
        var failureMessage: String?
        var isReading: Bool { photoId == nil && !failed }
    }

    /// What the batch form chose for a whole batch, applied to each photo once it has been read. A photo still being read when the form closes gets the same choices when it lands.
    struct BatchChoices {
        var personIds: Set<UUID> = []
        var caption = ""
        var tagRemoteIds: [Int] = []
        /// Per-photo dates the user changed, keyed by entry.
        var dates: [UUID: Date] = [:]
        /// Per-photo approximate dates, keyed by entry. A photo is in this or `dates`, not both.
        var recordTimes: [UUID: RecordTime] = [:]

        var isEmpty: Bool {
            personIds.isEmpty && caption.trimmingCharacters(in: .whitespaces).isEmpty && tagRemoteIds.isEmpty && dates.isEmpty && recordTimes.isEmpty
        }
    }

    private(set) var entries: [UUID: ImportEntry] = [:]
    /// Whether the account's family takes video, and its limits. Set by `AddFlow` when the add sheet opens; nil offline.
    var videoSupport: GetVideoSupportResponseDTO?
    private var pendingChoices: [UUID: BatchChoices] = [:]
    private var applyContext: (context: ModelContext, syncService: SyncService?)?
    /// Each failed entry's error, kept only until `importShared` has asked for it.
    private var lastErrors: [UUID: Error] = [:]

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

        let batch = items.map { ImportEntry(id: UUID(), source: .picked($0), isVideo: Self.isVideo($0)) }
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

    /// One file the share extension handed over.
    struct SharedFile {
        let url: URL
        let isVideo: Bool
        let captureDate: Date?
    }

    /// Imports files from the share inbox with the share sheet's choices already made, and returns once each has been read — or uploaded, for a video — or has failed. The caller keeps the files until then, and learns which failures are worth trying again.
    /// Joins whatever run is in flight, so one progress bar covers an in-app pick and a share alike.
    func importShared(
        _ files: [SharedFile],
        choices: BatchChoices,
        into context: ModelContext,
        syncService: SyncService?,
        errorPresenter: ErrorPresenter?
    ) async -> [SharedFileOutcome] {
        guard !files.isEmpty else { return [] }

        var next = progress ?? ImportProgress()
        next.total += files.count
        progress = next

        let batch = files.map {
            ImportEntry(id: UUID(), source: .file($0.url, captureDate: $0.captureDate), isVideo: $0.isVideo)
        }
        for entry in batch {
            entries[entry.id] = entry
            if !choices.isEmpty {
                pendingChoices[entry.id] = choices
            }
        }
        if !choices.isEmpty {
            applyContext = (context: context, syncService: syncService)
        }

        var outcomes: [SharedFileOutcome] = []
        for entry in batch {
            await read(entry.id, into: context, syncService: syncService)
            outcomes.append(Self.outcome(of: entry.id, in: entries, lastError: lastErrors.removeValue(forKey: entry.id)))
            // Settled, and the form never shows these: nothing reads the entry again.
            entries[entry.id] = nil
            pendingChoices[entry.id] = nil
            if progress?.isFinished == true {
                finish(reportingTo: errorPresenter)
            }
        }
        return outcomes
    }

    /// How one shared file's import ended, as the inbox needs to know it: whether its file can go.
    enum SharedFileOutcome: Equatable {
        case imported
        /// Couldn't be read or was refused; trying again would fail the same way.
        case failed
        /// Needed a connection, or video support that wasn't known yet. The file stays for the next drain.
        case retryLater
    }

    private static func outcome(of entryId: UUID, in entries: [UUID: ImportEntry], lastError: Error?) -> SharedFileOutcome {
        guard entries[entryId]?.failed == true else { return .imported }
        switch lastError as? VideoImportFailure {
        case .needsConnection, .unsupported: return .retryLater
        default: return .failed
        }
    }

    /// Reads one entry again after a failure. Counted on its own, outside the run's progress.
    func retry(_ entryId: UUID, into context: ModelContext, syncService: SyncService?) {
        guard entries[entryId]?.failed == true else { return }
        entries[entryId]?.failed = false
        entries[entryId]?.failureMessage = nil
        entries[entryId]?.uploadFraction = nil
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
            let imported: (photo: Photo, hasCaptureDate: Bool)
            switch (entry.source, entry.isVideo) {
            case (.picked(let item), true):
                guard let picked = try await item.loadTransferable(type: PickedVideo.self) else {
                    throw VideoImportFailure.unreadable
                }
                defer { picked.remove() }
                imported = try await importVideo(entryId, fileURL: picked.url, captureDate: Self.libraryDate(for: item), into: context)
            case (.file(let url, let captureDate), true):
                imported = try await importVideo(entryId, fileURL: url, captureDate: captureDate, into: context)
            case (.picked(let item), false):
                imported = try await importOne(Self.load(item), into: context, syncService: syncService)
            case (.file(let url, let captureDate), false):
                imported = try await importOne(Self.load(url, captureDate: captureDate), into: context, syncService: syncService)
            }
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
            if case .file = entry.source {
                lastErrors[entryId] = error
            }
            if entry.isVideo {
                entries[entryId]?.failureMessage = error.localizedDescription
            }
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
            try await Self.queueDetails(choices, changedDate: choices.dates[entryId], recordTime: choices.recordTimes[entryId], for: photo, context: context, syncService: syncService)
        } catch {
            AppLog.ui.error("Couldn't queue photo details: \(String(describing: error), privacy: .public)")
        }
    }

    /// Queues what the batch form chose for one photo: people, then tags, then the caption and date. Each is queued *behind* the photo's own upload — each declares the photo as its dependency — so the queue holds them until the upload has answered with a remote id, the way person tags always have been.
    static func queueDetails(
        _ choices: BatchChoices,
        changedDate: Date?,
        recordTime: RecordTime? = nil,
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
        if !caption.isEmpty || changedDate != nil || recordTime != nil {
            if !caption.isEmpty { photo.title = caption }
            if let changedDate { photo.photoDate = changedDate.localRecordDay() }
            if let recordTime {
                photo.recordTime = recordTime
                photo.photoDate = recordTime.isExactDay ? (DaySummaries.date(of: recordTime.from) ?? photo.photoDate) : RecordWhenEntry.sortDate(recordTime)
            }
            try context.save()
            // "keep" unless the date was changed: the upload already sent the resolved date. An approximate date goes as `recordTime`, which overrides "keep".
            try await syncService?.updatePhoto(photo, keepingDate: changedDate == nil, recordTime: recordTime)
        }
    }

    private func importOne(
        _ loaded: (data: Data, captureDate: Date?),
        into context: ModelContext,
        syncService: SyncService?
    ) async throws -> (photo: Photo, hasCaptureDate: Bool) {
        let (data, captureDate) = loaded
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

    /// Checks, uploads and stores one video. Online only: the batch form's people, caption and tags then queue against a photo that already has its server id, exactly as they would for an uploaded photo.
    /// `fileURL` is the caller's to delete: a picked video's scratch copy, or a shared file the inbox keeps until it hears the outcome.
    private func importVideo(_ entryId: UUID, fileURL: URL, captureDate: Date?, into context: ModelContext) async throws -> (photo: Photo, hasCaptureDate: Bool) {
        guard let support = videoSupport else { throw VideoImportFailure.unsupported }

        let filename = fileURL.lastPathComponent
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if let problem = VideoFiles.problem(filename: filename, size: size, support: support) {
            throw VideoImportFailure.refused(problem)
        }
        let seconds = try? await AVURLAsset(url: fileURL).load(.duration).seconds
        if let problem = VideoFiles.durationProblem(filename: filename, seconds: seconds, maxSeconds: support.maxDurationSeconds) {
            throw VideoImportFailure.refused(problem)
        }
        guard let contentType = VideoFiles.contentType(forFilename: filename) else {
            throw VideoImportFailure.unreadable
        }

        // The server dates the video from its own metadata; this day is only for a file that carries none.
        let fallbackDate = (captureDate ?? Date()).localWallClock().recordDayKey

        // A short trip out of the app shouldn't cost the upload.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Video upload")
        defer { UIApplication.shared.endBackgroundTask(background) }

        let image: ImageDTO
        do {
            image = try await VideoUploadService().upload(
                fileURL: fileURL,
                filename: filename,
                contentType: contentType,
                size: size,
                fallbackDate: fallbackDate
            ) { fraction in
                Task { @MainActor in self.entries[entryId]?.uploadFraction = fraction }
            }
        } catch APIError.network {
            throw VideoImportFailure.needsConnection
        }

        // A pull that landed while this was uploading may already hold the row.
        let remoteId = String(image.id)
        let photo = (try? context.fetch(FetchDescriptor<Photo>(predicate: #Predicate<Photo> { $0.remoteId == remoteId })).first)
            ?? Photo(title: "", descriptionText: "", photoDate: image.photoDate)
        applyPhotoDTO(image, to: photo)
        if photo.modelContext == nil {
            context.insert(photo)
        }
        try context.save()
        return (photo, captureDate != nil || image.photoDate.recordDayKey != fallbackDate)
    }

    private static func isVideo(_ item: PhotosPickerItem) -> Bool {
        item.supportedContentTypes.contains { $0.conforms(to: .movie) }
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

    enum VideoImportFailure: LocalizedError {
        case unreadable
        case unsupported
        case needsConnection
        /// The checks' own sentence: too long, too large, not MP4 or MOV, or video turned off.
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: return Copy.video.unreadable
            case .unsupported: return Copy.video.unsupported
            case .needsConnection: return Copy.video.needsConnection
            case .refused(let reason): return reason
            }
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

    /// A shared file's bytes. The date is the one the extension read from the file as it copied it.
    /// The extension keeps the original, which from a camera is usually HEIC; the server takes only JPEG, PNG and GIF, so anything else becomes a JPEG here, metadata and all.
    static func load(_ url: URL, captureDate: Date?) throws -> (data: Data, captureDate: Date?) {
        guard let original = try? Data(contentsOf: url), UIImage(data: original) != nil,
              let data = uploadable(original)
        else {
            throw ImportFailure.unreadable
        }
        return (data, captureDate ?? CaptureDate.from(data: original))
    }

    /// `data` as the server accepts it: unchanged when it is already JPEG, PNG or GIF, otherwise re-encoded as JPEG with its EXIF, orientation and GPS carried over.
    static func uploadable(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier)
        else { return nil }
        if [UTType.jpeg, .png, .gif].contains(where: { type.conforms(to: $0) }) {
            return data
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
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
        CaptureDate.from(data: data)
    }

    static func exifDate(from string: String) -> Date? {
        CaptureDate.exifDate(from: string)
    }
}

/// A picked video as a file of its own in a scratch folder: the system's copy lasts only as long as the import callback, and an upload needs it for minutes.
nonisolated struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("video-uploads", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedVideo(url: copy)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
