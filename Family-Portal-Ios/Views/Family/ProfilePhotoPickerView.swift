import SwiftUI
import SwiftData

/// Picks a person's avatar from the photos they are tagged in — `SetProfilePhoto` rejects a photo the person is not associated with, so that set is the whole eligible set.
struct ProfilePhotoPickerView: View {
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
    @Environment(\.dismiss) private var dismiss

    let person: Person

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    /// SwiftData does not order relationships; newest-first matches the preview grid that leads here.
    private var photos: [Photo] {
        person.photos.sorted { $0.photoDate > $1.photoDate }
    }

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No Photos",
                    systemImage: "person.crop.square",
                    description: Text("Tag \(person.name) in a photo to use it as their profile photo.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(photos) { photo in
                            Button {
                                select(photo)
                            } label: {
                                PhotoThumbnailView(
                                    imageData: photo.imageData,
                                    title: photo.title,
                                    remoteId: photo.remoteId
                                )
                                .overlay(alignment: .topTrailing) {
                                    if isCurrent(photo) {
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
                        }
                    }
                    .padding(8)
                }
            }
        }
        .navigationTitle("Profile Photo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isCurrent(_ photo: Photo) -> Bool {
        guard let profilePhotoId = person.profilePhotoId else { return false }
        return photo.remoteId.flatMap(Int.init) == profilePhotoId
    }

    private func accessibilityLabel(for photo: Photo) -> String {
        let name = photo.title.isEmpty
            ? photo.photoDate.formatted(date: .abbreviated, time: .omitted)
            : photo.title
        return isCurrent(photo) ? "\(name), current profile photo" : name
    }

    private func select(_ photo: Photo) {
        guard !isCurrent(photo) else {
            dismiss()
            return
        }

        Task {
            do {
                try await syncService?.setProfilePhoto(photo, for: person)
                dismiss()
            } catch {
                dismiss()
                errorPresenter?.report(error, title: "Couldn't Set Profile Photo")
            }
        }
    }
}
