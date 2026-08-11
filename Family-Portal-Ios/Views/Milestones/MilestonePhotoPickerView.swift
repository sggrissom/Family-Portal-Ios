import SwiftUI
import SwiftData

/// Chooses which already-uploaded family photos a milestone links to.
///
/// `AddMilestoneRequest.PhotoIds` and `UpdateMilestoneRequest.PhotoIds` have
/// existed on the backend all along, and `applyMilestoneDTO` has been reading
/// the ids back into `Milestone.photoRemoteIds` — nothing ever sent them.
struct MilestonePhotoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?

    // Only synced photos can be linked: the association is by remote id, so a
    // photo still sitting in the upload queue has no id to send.
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]

    let milestone: Milestone

    @State private var selected: Set<Int> = []
    @State private var isSaving = false

    private var linkablePhotos: [Photo] {
        photos.compactMap { photo in
            guard let remoteId = photo.remoteId, Int(remoteId) != nil else { return nil }
            return photo
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        NavigationStack {
            Group {
                if linkablePhotos.isEmpty {
                    ContentUnavailableView(
                        "No Photos Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Upload photos from the Photos tab, then attach them here.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(linkablePhotos, id: \.id) { photo in
                                if let remoteId = photo.remoteId, let id = Int(remoteId) {
                                    photoCell(photo: photo, remoteId: id)
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .navigationTitle("Attach Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                selected = Set(milestone.photoRemoteIds)
            }
        }
    }

    @ViewBuilder
    private func photoCell(photo: Photo, remoteId: Int) -> some View {
        let isSelected = selected.contains(remoteId)

        Button {
            if isSelected {
                selected.remove(remoteId)
            } else {
                selected.insert(remoteId)
            }
        } label: {
            PhotoThumbnailView(
                imageData: photo.imageData,
                title: "",
                remoteId: photo.remoteId
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .white)
                    .shadow(radius: 2)
                    .padding(4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(photo.title.isEmpty ? "Photo" : photo.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func save() {
        isSaving = true
        milestone.photoRemoteIds = selected.sorted()

        dismiss()

        Task {
            do {
                try await syncService?.updateMilestone(milestone)
            } catch {
                print("Failed to sync milestone photos: \(error)")
            }
        }
    }
}
