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

    static func save(_ fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: fileURL, options: nil)
        }
    }
}

/// **Share original** and **Save to Photos** for an uploaded photo: the web's "Download original". Both download the bytes as uploaded — never the resized image on screen — to a scratch file that is removed once the share sheet closes or the save finishes. Online only.
@MainActor
@Observable
final class OriginalPhotoActions {
    enum Action {
        case share, save

        var failureTitle: String {
            switch self {
            case .share: return Copy.originalPhoto.shareFailed
            case .save: return Copy.originalPhoto.saveFailed
            }
        }
    }

    enum Failure: LocalizedError {
        case offline

        var errorDescription: String? { Copy.originalPhoto.offline }
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

    func start(_ action: Action, photoId: Int, isConnected: Bool, onError: @escaping (Error, String) -> Void) {
        guard working == nil else { return }
        guard isConnected else {
            onError(Failure.offline, action.failureTitle)
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
                let original = try await apiClient.downloadOriginal(photoId: photoId) { fraction in
                    Task { @MainActor [weak self] in self?.progress = fraction }
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
                    try await PhotoLibrarySaver.save(original.fileURL)
                    saveCount += 1
                }
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                onError(error, action.failureTitle)
            }
        }
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
                        Text(Copy.originalPhoto.notUploaded)
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
        actions.start(action, photoId: remoteId, isConnected: network.isConnected) { error, title in
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
