import SwiftUI

/// A photo the server holds, by id.
///
/// The fetching, caching and 401 retry all live in `PhotoImageCache`; what is
/// left here is the two things the view has to decide: whether it can render
/// immediately, and what to do while a freshly uploaded photo is still being
/// processed.
struct RemotePhotoView: View {
    let remoteId: Int
    let size: PhotoSizeVariant
    let contentMode: ContentMode

    /// How long to wait between asks while the server is still generating the
    /// photo's variants, and how many times to ask.
    ///
    /// Processing is fast when it works, so the first look-again is quick and
    /// the gap widens from there. It stops rather than polling forever: a job
    /// that has not finished in about a minute has failed in a way this view
    /// cannot fix, and a screenful of thumbnails each polling on a timer is a
    /// worse problem than a photo the user can fix by pulling to refresh.
    private static let processingRetryDelays: [Duration] = [
        .seconds(2), .seconds(3), .seconds(5), .seconds(8), .seconds(13), .seconds(21),
    ]

    @State private var image: UIImage?
    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        /// The server has the photo but has not finished making this variant.
        case processing
        case ready
        case unavailable
    }

    init(remoteId: Int, size: PhotoSizeVariant, contentMode: ContentMode = .fill) {
        self.remoteId = remoteId
        self.size = size
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel("Photo")
            } else {
                switch phase {
                case .loading:
                    ProgressView()
                case .processing:
                    placeholder(systemName: "clock", label: "Photo still processing")
                case .ready, .unavailable:
                    placeholder(systemName: "photo", label: "Photo unavailable")
                }
            }
        }
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

    private func load() async {
        // A thumbnail already in memory renders in the first layout pass
        // instead of flashing a spinner on every scroll back.
        if let cached = PhotoImageCache.shared.cachedImage(remoteId: remoteId, size: size) {
            image = cached
            phase = .ready
            return
        }

        image = nil
        phase = .loading

        for attempt in 0...Self.processingRetryDelays.count {
            switch await PhotoImageCache.shared.image(remoteId: remoteId, size: size) {
            case .image(let loaded):
                image = loaded
                phase = .ready
                return
            case .unavailable:
                phase = .unavailable
                return
            case .processing:
                phase = .processing
                guard attempt < Self.processingRetryDelays.count else { return }
                do {
                    try await Task.sleep(for: Self.processingRetryDelays[attempt])
                } catch {
                    // The view went away, or `task(id:)` restarted us.
                    return
                }
            }
        }
    }
}
