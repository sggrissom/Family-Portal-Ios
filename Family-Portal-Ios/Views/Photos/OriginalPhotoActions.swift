import SwiftUI
import Photos
import OSLog

/// Saves a file to the photo library. Asks for add-only access, and only when the user has chosen to save — never at launch or on import.
/// `nonisolated` so the change block is not inferred to the main actor: PhotoKit runs it on a queue of its own.
nonisolated enum PhotoLibrarySaver {
    enum Failure: LocalizedError {
        case denied

        var errorDescription: String? {
            "Family Record isn't allowed to add to your photo library. You can allow it in Settings › Privacy & Security › Photos."
        }
    }

    static func save(_ fileURL: URL, isVideo: Bool = false) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: isVideo ? .video : .photo, fileURL: fileURL, options: nil)
        }
    }
}

/// **Share original** and **Save to Photos** for an uploaded photo or video: the web's "Download original". Both download the bytes as uploaded — never the resized image or the playback copy — to a scratch file that is removed once the share sheet closes or the save finishes. Online only.
/// A photo's original is `api/photo/{id}/original`; a video's is the `downloadUrl` that `GetVideoPlayback` mints, fetched without the app's credentials.
@MainActor
@Observable
final class OriginalPhotoActions {
    enum Action {
        case share, save

        func failureTitle(isVideo: Bool) -> String {
            switch self {
            case .share: return isVideo ? Copy.video.shareFailed : Copy.originalPhoto.shareFailed
            case .save: return isVideo ? Copy.video.saveFailed : Copy.originalPhoto.saveFailed
            }
        }
    }

    enum Failure: LocalizedError {
        case offline(isVideo: Bool)
        /// A video whose original the server no longer keeps — one it rejected.
        case noOriginal

        var errorDescription: String? {
            switch self {
            case .offline(let isVideo): return isVideo ? Copy.video.offline : Copy.originalPhoto.offline
            case .noOriginal: return Copy.video.noOriginal
            }
        }
    }

    /// What is downloading, if anything. One at a time.
    private(set) var working: Action?
    /// 0…1, or 0 while the size is unknown.
    private(set) var progress: Double = 0
    /// The file the share sheet is showing.
    private(set) var sharing: DownloadedOriginal?
    /// Bumped by every save that lands, for the confirmation.
    private(set) var saveCount = 0

    private var task: Task<Void, Never>?
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func start(_ action: Action, photoId: Int, isVideo: Bool = false, isConnected: Bool, onError: @escaping (Error, String) -> Void) {
        guard working == nil else { return }
        guard isConnected else {
            onError(Failure.offline(isVideo: isVideo), action.failureTitle(isVideo: isVideo))
            return
        }
        working = action
        progress = 0
        task = Task {
            defer {
                working = nil
                task = nil
            }
            do {
                let report: @Sendable (Double) -> Void = { fraction in
                    Task { @MainActor in self.progress = fraction }
                }
                let original: DownloadedOriginal
                if isVideo {
                    original = try await downloadVideoOriginal(photoId: photoId, progress: report)
                } else {
                    original = try await apiClient.downloadOriginal(photoId: photoId, progress: report)
                }
                // Cancelled just as the bytes landed: nothing to show them to.
                guard !Task.isCancelled else {
                    original.remove()
                    return
                }
                switch action {
                case .share:
                    sharing = original
                case .save:
                    defer { original.remove() }
                    try await PhotoLibrarySaver.save(original.fileURL, isVideo: isVideo)
                    saveCount += 1
                }
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                onError(error, action.failureTitle(isVideo: isVideo))
            }
        }
    }

    /// Asks for a fresh link every time rather than holding one: links expire, and a stored one is exactly what the contract says never to keep.
    private func downloadVideoOriginal(photoId: Int, progress: @escaping @Sendable (Double) -> Void) async throws -> DownloadedOriginal {
        let playback: GetVideoPlaybackResponseDTO = try await apiClient.callRPC(.getVideoPlayback, payload: GetVideoPlaybackRequestDTO(id: photoId))
        guard !playback.downloadUrl.isEmpty else { throw Failure.noOriginal }
        try Task.checkCancellation()
        return try await apiClient.downloadMedia(
            link: playback.downloadUrl,
            suggested: playback.originalFilename,
            photoId: photoId,
            progress: progress
        )
    }

    func cancel() {
        task?.cancel()
    }

    /// The share sheet closed, whether or not anything was shared.
    func finishSharing() {
        sharing?.remove()
        sharing = nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case APIError.network(let underlying) = error, (underlying as? URLError)?.code == .cancelled { return true }
        return false
    }
}

/// The photo page's toolbar button: a menu with both actions, a progress readout that cancels while one runs, and an explanation in place of the actions for a photo that has not uploaded yet.
struct OriginalPhotoMenu: View {
    let photo: Photo

    @Environment(NetworkMonitor.self) private var network
    @Environment(ErrorPresenter.self) private var errorPresenter
    @State private var actions = OriginalPhotoActions()
    @State private var showsSaved = false

    private var remoteId: Int? { photo.serverId }

    var body: some View {
        Group {
            if actions.working != nil {
                Button {
                    actions.cancel()
                } label: {
                    HStack(spacing: 6) {
                        ProgressView()
                        if actions.progress > 0 {
                            Text(actions.progress, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                    }
                }
                .accessibilityLabel(Copy.originalPhoto.cancel)
            } else {
                Menu {
                    if let remoteId {
                        Button {
                            run(.share, remoteId)
                        } label: {
                            Label(Copy.originalPhoto.share, systemImage: "square.and.arrow.up")
                        }
                        Button {
                            run(.save, remoteId)
                        } label: {
                            Label(Copy.originalPhoto.save, systemImage: "square.and.arrow.down")
                        }
                    } else {
                        // Still on this device only: there is no original on the server to fetch yet.
                        Text(photo.isVideo ? Copy.video.notUploaded : Copy.originalPhoto.notUploaded)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Copy.originalPhoto.menu)
            }
        }
        .sheet(item: Binding(get: { actions.sharing }, set: { if $0 == nil { actions.finishSharing() } })) { original in
            ActivityView(items: [original.fileURL]) {
                actions.finishSharing()
            }
            .ignoresSafeArea()
        }
        .onChange(of: actions.saveCount) { _, _ in
            showsSaved = true
        }
        .sensoryFeedback(.success, trigger: actions.saveCount)
        .alert(Copy.originalPhoto.saved, isPresented: $showsSaved) {
            Button("OK", role: .cancel) {}
        }
    }

    private func run(_ action: OriginalPhotoActions.Action, _ remoteId: Int) {
        actions.start(action, photoId: remoteId, isVideo: photo.isVideo, isConnected: network.isConnected) { error, title in
            errorPresenter.report(error, title: title)
        }
    }
}

/// The system share sheet, for a file that only exists once it has downloaded — which `ShareLink` cannot wait for.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
