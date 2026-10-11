import PhotosUI
import SwiftData
import SwiftUI

/// A milestone photo, read from the library but not yet a `Photo`: the form holds it until Save, so cancelling leaves nothing behind and the photo is tagged to the selected person on Save.
struct PickedMilestonePhoto: Identifiable {
    let id = UUID()
    let data: Data
    let captureDate: Date?
}

enum MilestonePhotoUploads {
    /// Turns the picks into photos tagged to the milestone's person and queues their uploads. The uploads go ahead of the milestone that attaches them, which the queue runs in order.
    static func queue(
        _ picked: [PickedMilestonePhoto],
        artist: Person,
        context: ModelContext,
        syncService: SyncService?
    ) async throws -> [Photo] {
        var photos: [Photo] = []
        for pick in picked {
            let photo = Photo(title: "", descriptionText: "", photoDate: (pick.captureDate ?? Date()).localWallClock(), imageData: pick.data)
            context.insert(photo)
            photo.taggedPeople = [artist]
            try context.save()
            try await syncService?.uploadPhoto(photo)
            photos.append(photo)
        }
        return photos
    }
}

/// Pick new photos without leaving the milestone. Nothing is uploaded until Save.
struct MilestonePhotoUploadSection: View {
    @Binding var picked: [PickedMilestonePhoto]
    @Binding var isReading: Bool
    var isArtwork = false

    @State private var items: [PhotosPickerItem] = []
    @State private var unreadable = false

    var body: some View {
        Section(isArtwork ? Copy.milestone.artworkPhotos : Copy.milestone.photos) {
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
                Label(isArtwork ? Copy.milestone.addArtworkPhoto : "Add New Photos", systemImage: "photo.badge.plus")
            }
            .disabled(isReading)

            if isReading {
                ProgressView("Loading photos…")
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
            isReading = true
            Task { await read(newItems) }
        }
    }

    private func read(_ newItems: [PhotosPickerItem]) async {
        defer { isReading = false }
        unreadable = false
        for item in newItems {
            guard let loaded = try? await PhotoImporter.load(item) else {
                unreadable = true
                continue
            }
            picked.append(PickedMilestonePhoto(data: loaded.data, captureDate: loaded.captureDate))
        }
    }
}
