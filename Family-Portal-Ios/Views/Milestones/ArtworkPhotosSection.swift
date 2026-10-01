import PhotosUI
import SwiftData
import SwiftUI

/// A photo of a piece of artwork, read from the library but not yet a `Photo`: the form holds it until Save, so cancelling leaves nothing behind and the photo is tagged to whoever the artist is by then.
struct PickedArtwork: Identifiable {
    let id = UUID()
    let data: Data
    let captureDate: Date?
}

enum ArtworkPhotos {
    /// Turns the picks into photos tagged to the artist and queues their uploads. The uploads go ahead of the milestone that attaches them, which the queue runs in order.
    static func queue(
        _ picked: [PickedArtwork],
        artist: Person,
        context: ModelContext,
        syncService: SyncService?
    ) async throws -> [Photo] {
        var photos: [Photo] = []
        for pick in picked {
            let photo = Photo(title: "", descriptionText: "", photoDate: pick.captureDate ?? Date(), imageData: pick.data)
            context.insert(photo)
            photo.taggedPeople = [artist]
            try context.save()
            try await syncService?.uploadPhoto(photo)
            photos.append(photo)
        }
        return photos
    }
}

/// The web's "Add a photo of it". A drawing rarely has the artist's face in it, so the person's photos — all the picker offers — won't include it.
struct ArtworkPhotosSection: View {
    @Binding var picked: [PickedArtwork]

    @State private var items: [PhotosPickerItem] = []
    @State private var unreadable = false

    var body: some View {
        Section(Copy.milestone.artworkPhotos) {
            if !picked.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(picked) { pick in
                            PhotoThumbnailView(imageData: pick.data, title: "")
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        picked.removeAll { $0.id == pick.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Copy.milestone.detachPhoto)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            PhotosPicker(selection: $items, matching: .images, photoLibrary: .shared()) {
                Label(Copy.milestone.addArtworkPhoto, systemImage: "camera")
            }

            if unreadable {
                Text(PhotoImporter.ImportFailure.unreadable.errorDescription ?? "")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: items) { _, newItems in
            guard !newItems.isEmpty else { return }
            items = []
            Task { await read(newItems) }
        }
    }

    private func read(_ newItems: [PhotosPickerItem]) async {
        unreadable = false
        for item in newItems {
            guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
                unreadable = true
                continue
            }
            picked.append(PickedArtwork(data: data, captureDate: PhotoImporter.captureDate(from: data)))
        }
    }
}
