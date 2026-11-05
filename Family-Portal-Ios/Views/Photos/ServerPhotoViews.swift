import SwiftUI
import SwiftData

/// A grid cell for a photo by server id: the local photo when this device holds it, else the server's thumbnail — never left out because the mirror hasn't caught up.
struct ServerPhotoCell: View {
    let remoteId: Int
    /// The local photo with that id, if any.
    let local: Photo?
    /// Where in a video a search matched it, if it did: the cell shows that frame and the line, and opens the video there.
    var match: MediaMatchDTO? = nil

    var body: some View {
        if let local {
            NavigationLink(value: PhotoRoute(id: local.id, startMs: startMs)) {
                matched {
                    PhotoThumbnailView(imageData: local.imageData, title: local.title, remoteId: local.remoteId, videoDurationMs: local.videoBadgeDuration)
                }
            }
            .accessibilityLabel(match?.snippet.isEmpty == false ? Copy.search.saidInVideo(match?.snippet ?? "") : local.title)
        } else {
            NavigationLink(value: AppRoute.remotePhoto(id: remoteId, startMs: startMs)) {
                matched {
                    PhotoThumbnailView(imageData: nil, title: "", remoteId: String(remoteId))
                }
                .overlay(alignment: .bottomLeading) {
                    if match?.snippet.isEmpty ?? true {
                        Image(systemName: "icloud")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .shadow(radius: 2)
                    }
                }
            }
            .accessibilityLabel(Copy.photoBrowse.notSyncedPhoto)
        }
    }

    private var startMs: Int { match?.offsetMs ?? 0 }

    /// The thumbnail, or for a match inside a video the matching frame with the line said there, as the web's search tile does.
    @ViewBuilder
    private func matched(@ViewBuilder thumbnail: () -> some View) -> some View {
        if let match, match.offsetMs > 0 {
            VideoFrameView(remoteId: remoteId, frameMs: match.offsetMs, badgeDurationMs: local?.durationMs ?? 0) {
                thumbnail()
            }
            .overlay(alignment: .bottom) { snippet }
        } else {
            thumbnail()
                .overlay(alignment: .bottom) { snippet }
        }
    }

    @ViewBuilder
    private var snippet: some View {
        if let text = match?.snippet, !text.isEmpty {
            Text("“\(text)”")
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.65))
        }
    }
}

/// One sampled frame of a video by server id, filling its frame; `fallback` while it loads or when the server has none.
struct VideoFrameView<Fallback: View>: View {
    let remoteId: Int
    let frameMs: Int
    /// The play badge over the frame, which the fallback thumbnail draws for itself.
    var badgeDurationMs: Int = 0
    @ViewBuilder let fallback: () -> Fallback

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        VideoBadge(durationMs: badgeDurationMs)
                    }
            } else {
                fallback()
            }
        }
        .task(id: "\(remoteId)-\(frameMs)") {
            let cache = PhotoImageCache.shared
            if let cached = cache.cachedFrame(remoteId: remoteId, frameMs: frameMs) {
                image = cached
            } else if case .image(let loaded) = await cache.frame(remoteId: remoteId, frameMs: frameMs) {
                image = loaded
            }
        }
    }
}

/// Every photo in a group of similar shots, cover first — the web's stack viewer, as a grid.
struct SimilarPhotosView: View {
    let remoteIds: [Int]

    @Query private var photos: [Photo]

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    var body: some View {
        let byRemoteId = Dictionary(photos.compactMap { photo in photo.serverId.map { ($0, photo) } }, uniquingKeysWith: { first, _ in first })
        ScrollView {
            Text(Copy.photoBrowse.similarCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(remoteIds, id: \.self) { id in
                    ServerPhotoCell(remoteId: id, local: byRemoteId[id])
                }
            }
            .padding(4)
        }
        .navigationTitle(Copy.photoBrowse.similarTitle(remoteIds.count))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A photo or video opened by server id. Once the mirror holds it, this is the ordinary photo page; until then, the photo itself (or the player, for a video) and a line saying why there is nothing else.
struct RemotePhotoDetailView: View {
    let remoteId: Int
    var startMs: Int = 0

    @Query private var matches: [Photo]

    init(remoteId: Int, startMs: Int = 0) {
        self.remoteId = remoteId
        self.startMs = startMs
        let key = String(remoteId)
        _matches = Query(filter: #Predicate<Photo> { photo in photo.remoteId == key })
    }

    var body: some View {
        if let local = matches.first {
            PhotoDetailView(photoId: local.id, startMs: startMs)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    RemoteMediaView(remoteId: remoteId, local: nil, startMs: startMs) {
                        ZoomableView {
                            RemotePhotoView(remoteId: remoteId, size: .xlarge, contentMode: .fit)
                                .scaledToFit()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Label(Copy.photoBrowse.notSyncedNote, systemImage: "icloud")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
