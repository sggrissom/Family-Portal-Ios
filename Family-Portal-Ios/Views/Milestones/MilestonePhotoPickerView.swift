import SwiftUI

/// Chooses which photos a milestone is illustrated with. Selection is by *local* id, so a photo still uploading does not silently lose its place.
struct MilestonePhotoPickerView: View {
    let photos: [Photo]
    let emptyDescription: String
    @Binding var selection: Set<UUID>

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "photo.on.rectangle",
                    description: Text(emptyDescription)
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(photos) { photo in
                            Button {
                                toggle(photo)
                            } label: {
                                PhotoThumbnailView(
                                    imageData: photo.imageData,
                                    title: photo.title,
                                    remoteId: photo.remoteId
                                )
                                .overlay {
                                    if selection.contains(photo.id) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(.blue, lineWidth: 3)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if selection.contains(photo.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .blue)
                                            .padding(6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accessibilityLabel(for: photo))
                            .accessibilityAddTraits(selection.contains(photo.id) ? .isSelected : [])
                        }
                    }
                    .padding(8)
                }
            }
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ photo: Photo) {
        if selection.contains(photo.id) {
            selection.remove(photo.id)
        } else {
            selection.insert(photo.id)
        }
    }

    private func accessibilityLabel(for photo: Photo) -> String {
        photo.title.isEmpty
            ? photo.photoDate.formatted(date: .abbreviated, time: .omitted)
            : photo.title
    }
}

struct MilestonePhotosSection: View {
    let photos: [Photo]
    let emptyDescription: String
    @Binding var selection: Set<UUID>

    private var selectedPhotos: [Photo] {
        photos.filter { selection.contains($0.id) }
    }

    var body: some View {
        Section("Photos") {
            NavigationLink {
                MilestonePhotoPickerView(
                    photos: photos,
                    emptyDescription: emptyDescription,
                    selection: $selection
                )
            } label: {
                HStack {
                    Label("Attach Photos", systemImage: "photo.on.rectangle")
                    Spacer()
                    if !selection.isEmpty {
                        Text("\(selection.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !selectedPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedPhotos) { photo in
                            PhotoThumbnailView(
                                imageData: photo.imageData,
                                title: photo.title,
                                remoteId: photo.remoteId
                            )
                            .frame(width: 64, height: 64)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

/// The photos a milestone may be illustrated with: the ones its person is tagged in, plus anything already attached — `photoIds` is the complete attachment set, so a photo the sheet cannot show is one the next save detaches.
func milestonePhotoChoices(
    for milestone: Milestone?,
    person: Person?,
    allPhotos: [Photo]
) -> [Photo] {
    var eligible = person?.photos ?? []

    if let attached = milestone.map({ Set($0.photoRemoteIds) }), !attached.isEmpty {
        let known = Set(eligible.map { $0.id })
        eligible += allPhotos.filter { photo in
            guard !known.contains(photo.id),
                  let remoteId = photo.remoteId.flatMap(Int.init) else { return false }
            return attached.contains(remoteId)
        }
    }

    return eligible.sorted { $0.photoDate > $1.photoDate }
}
