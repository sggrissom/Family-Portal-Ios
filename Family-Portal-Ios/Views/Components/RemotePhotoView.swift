import SwiftUI

/// What a `RemotePhotoView` is doing while it has nothing of its own to draw. Reported to the caller so a view that supplies its own stand-in — an avatar, say — can tell "still coming" from "never coming".
enum RemotePhotoPhase {
    case loading
    case processing
    case ready
    case unavailable
}

/// A photo the server holds, by id. The fetching, caching and 401 retry live in `PhotoImageCache`.
struct RemotePhotoView: View {
    let remoteId: Int
    let size: PhotoSizeVariant
    let contentMode: ContentMode
    /// Off for callers that draw their own stand-in behind this view; the built-in spinner and symbol would otherwise sit on top of it.
    let showsPlaceholder: Bool
    let onPhaseChange: ((RemotePhotoPhase) -> Void)?

    /// How long to wait between asks while the server is still generating the photo's variants, and how many times to ask. It stops rather than polling forever.
    private static let processingRetryDelays: [Duration] = [
        .seconds(2), .seconds(3), .seconds(5), .seconds(8), .seconds(13), .seconds(21),
    ]

    @State private var image: UIImage?
    @State private var phase: RemotePhotoPhase

    init(
        remoteId: Int,
        size: PhotoSizeVariant,
        contentMode: ContentMode = .fill,
        showsPlaceholder: Bool = true,
        onPhaseChange: ((RemotePhotoPhase) -> Void)? = nil
    ) {
        self.remoteId = remoteId
        self.size = size
        self.contentMode = contentMode
        self.showsPlaceholder = showsPlaceholder
        self.onPhaseChange = onPhaseChange

        // Seeded rather than left to `.task`, which only runs after a frame has already been drawn: a photo that is decoded and waiting in memory should reach the very first layout pass. Without this, scrolling back to a thumbnail already seen flashes its placeholder again.
        let cached = PhotoImageCache.shared.cachedImage(remoteId: remoteId, size: size)
        _image = State(initialValue: cached)
        _phase = State(initialValue: cached == nil ? .loading : .ready)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel("Photo")
            } else if showsPlaceholder {
                switch phase {
                case .loading:
                    ProgressView()
                case .processing:
                    placeholder(systemName: "clock", label: "Photo still processing")
                case .ready, .unavailable:
                    placeholder(systemName: "photo", label: "Photo unavailable")
                }
            } else {
                Color.clear
            }
        }
        // A photo that arrives late fades over whatever stood in for it; a hard cut reads as the view changing its mind. Keyed on presence rather than on the image, whose `==` compares pixels.
        .animation(.easeIn(duration: 0.2), value: image != nil)
        .task(id: "\(remoteId)-\(size.rawValue)") {
            await load()
        }
    }

    private func placeholder(systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
    }

    private func setPhase(_ new: RemotePhotoPhase) {
        phase = new
        onPhaseChange?(new)
    }

    private func load() async {
        // A thumbnail already in memory renders in the first layout pass instead of flashing a spinner on every scroll back.
        if let cached = PhotoImageCache.shared.cachedImage(remoteId: remoteId, size: size) {
            image = cached
            setPhase(.ready)
            return
        }

        image = nil
        setPhase(.loading)

        for attempt in 0...Self.processingRetryDelays.count {
            switch await PhotoImageCache.shared.image(remoteId: remoteId, size: size) {
            case .image(let loaded):
                image = loaded
                setPhase(.ready)
                return
            case .unavailable:
                setPhase(.unavailable)
                return
            case .processing:
                setPhase(.processing)
                guard attempt < Self.processingRetryDelays.count else { return }
                do {
                    try await Task.sleep(for: Self.processingRetryDelays[attempt])
                } catch {
                    return
                }
            }
        }
    }
}
