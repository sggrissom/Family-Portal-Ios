import SwiftUI
import SwiftData

/// The mirror's record for a server id, or nil when it doesn't hold one yet, handed to `content`. For views that start from a server id — attached media, search results — and need what only the mirror knows, such as whether it is a video.
struct MirroredPhoto<Content: View>: View {
    @Query private var matches: [Photo]
    private let content: (Photo?) -> Content

    init(remoteId: Int, @ViewBuilder content: @escaping (Photo?) -> Content) {
        let key = String(remoteId)
        _matches = Query(filter: #Predicate<Photo> { photo in photo.remoteId == key })
        self.content = content
    }

    var body: some View {
        content(matches.first)
    }
}

extension View {
    /// Badges a thumbnail drawn from a server id as a video once the mirror knows it is one.
    func videoBadge(remoteId: Int) -> some View {
        overlay(alignment: .topLeading) {
            MirroredPhoto(remoteId: remoteId) { photo in
                if let duration = photo?.videoBadgeDuration {
                    VideoBadge(durationMs: duration)
                }
            }
        }
    }
}

/// A photo or video known by server id, full size: the player for a video, `still` otherwise. Whether it is a video comes from the mirror, or from `GetPhoto` when the mirror doesn't hold it yet and there is a connection — without that, an attached video the mirror hasn't caught up with could only ever show its poster.
struct RemoteMediaView<Still: View>: View {
    let remoteId: Int
    /// The mirror's record, when it holds one.
    let local: Photo?
    private let still: Still

    @Environment(NetworkMonitor.self) private var network
    /// `mediaKind` from `GetPhoto`, for a server id the mirror doesn't hold.
    @State private var fetchedKind: Int?

    init(remoteId: Int, local: Photo?, @ViewBuilder still: () -> Still) {
        self.remoteId = remoteId
        self.local = local
        self.still = still()
    }

    private var isVideo: Bool {
        if let local { return local.isVideo }
        return fetchedKind == MediaKind.video.rawValue
    }

    var body: some View {
        Group {
            if isVideo {
                VideoPlayerSection(photo: local, remoteId: remoteId)
            } else {
                still
            }
        }
        .task(id: network.isConnected) {
            guard local == nil, fetchedKind == nil, network.isConnected else { return }
            fetchedKind = await AnalysisService.shared.photoDetails(photoId: remoteId)?.image.mediaKind
        }
    }
}
