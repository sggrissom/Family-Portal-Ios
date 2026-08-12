import SwiftUI
import SwiftData

/// Picks which already-uploaded photos a milestone links to.
///
/// Only photos with a remote id can be offered: the link is made server-side by
/// photo id (`AddMilestoneRequest.PhotoIds`), so a photo still waiting in the
/// upload queue has nothing to link to yet.
struct MilestonePhotoPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]
    @Binding var selectedPhotoIds: [Int]

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    private var linkablePhotos: [(photo: Photo, remoteId: Int)] {
        photos.compactMap { photo in
            guard let remoteId = photo.remoteId, let id = Int(remoteId) else { return nil }
            return (photo, id)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if linkablePhotos.isEmpty {
                    ContentUnavailableView(
                        "No Photos Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Photos can be attached once they've finished uploading.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(linkablePhotos, id: \.remoteId) { entry in
                                photoCell(entry.photo, remoteId: entry.remoteId)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Attach Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func photoCell(_ photo: Photo, remoteId: Int) -> some View {
        let isSelected = selectedPhotoIds.contains(remoteId)

        return Button {
            toggle(remoteId)
        } label: {
            PhotoThumbnailView(imageData: photo.imageData, title: photo.title, remoteId: photo.remoteId)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Color.accentColor : Color.black.opacity(0.35))
                        .padding(6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.title.isEmpty ? "Photo" : photo.title)
        .accessibilityValue(isSelected ? "Attached" : "Not attached")
    }

    private func toggle(_ remoteId: Int) {
        if let index = selectedPhotoIds.firstIndex(of: remoteId) {
            selectedPhotoIds.remove(at: index)
        } else {
            selectedPhotoIds.append(remoteId)
        }
    }
}
