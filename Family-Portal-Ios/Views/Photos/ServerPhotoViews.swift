import SwiftUI
import SwiftData

/// A grid cell for a photo by server id: the local photo when this device holds it, else the server's thumbnail — never left out because the mirror hasn't caught up.
struct ServerPhotoCell: View {
    let remoteId: Int
    /// The local photo with that id, if any.
    let local: Photo?

    var body: some View {
        if let local {
            NavigationLink(value: PhotoRoute(id: local.id)) {
                PhotoThumbnailView(imageData: local.imageData, title: local.title, remoteId: local.remoteId)
            }
        } else {
            NavigationLink(value: AppRoute.remotePhoto(id: remoteId)) {
                PhotoThumbnailView(imageData: nil, title: "", remoteId: String(remoteId))
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "icloud")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .shadow(radius: 2)
                    }
            }
            .accessibilityLabel(Copy.photoBrowse.notSyncedPhoto)
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

/// A photo opened by server id. Once the mirror holds it, this is the ordinary photo page; until then, the photo itself and a line saying why there is nothing else.
struct RemotePhotoDetailView: View {
    let remoteId: Int

    @Query private var matches: [Photo]

    init(remoteId: Int) {
        self.remoteId = remoteId
        let key = String(remoteId)
        _matches = Query(filter: #Predicate<Photo> { photo in photo.remoteId == key })
    }

    var body: some View {
        if let local = matches.first {
            PhotoDetailView(photoId: local.id)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    ZoomableView {
                        RemotePhotoView(remoteId: remoteId, size: .xlarge, contentMode: .fit)
                            .scaledToFit()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
