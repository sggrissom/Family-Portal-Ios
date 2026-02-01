import SwiftUI
import SwiftData

struct PhotoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @Query private var photos: [Photo]
    @State private var showDeleteConfirmation = false
    @State private var selection: UUID

    private let photoIds: [UUID]

    private var orderedPhotos: [Photo] {
        let photoById = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        return photoIds.compactMap { photoById[$0] }
    }

    private var selectedPhoto: Photo? {
        orderedPhotos.first { $0.id == selection }
    }

    init(photoIds: [UUID], initialPhotoId: UUID) {
        self.photoIds = photoIds
        _selection = State(initialValue: initialPhotoId)
        _photos = Query(filter: #Predicate<Photo> { photo in
            photoIds.contains(photo.id)
        })
    }

    var body: some View {
        if orderedPhotos.isEmpty {
            ContentUnavailableView("Photo Not Found", systemImage: "photo.slash")
        } else {
            TabView(selection: $selection) {
                ForEach(orderedPhotos) { photo in
                    PhotoDetailContent(photo: photo, showDeleteConfirmation: $showDeleteConfirmation)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete Photo", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let selectedPhoto else { return }
                    Task {
                        do {
                            try await syncService?.deletePhoto(selectedPhoto)
                        } catch {
                            print("Failed to sync delete photo: \(error)")
                        }
                        dismiss()
                    }
                }
            } message: {
                Text("This photo will be permanently deleted.")
            }
        }
    }
}

private struct PhotoDetailContent: View {
    @Bindable var photo: Photo
    @Binding var showDeleteConfirmation: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                    ZoomableView {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else if let remoteId = photo.remoteId, let remoteInt = Int(remoteId) {
                    ZoomableView {
                        RemotePhotoView(remoteId: remoteInt, size: .xlarge, contentMode: .fit)
                            .scaledToFit()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView("No Photo", systemImage: "photo")
                        .padding(.horizontal)
                }

                Text(photo.photoDate.formatted(date: .long, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    TextField("Title", text: $photo.title)
                        .textFieldStyle(.roundedBorder)

                    TextField("Description", text: $photo.descriptionText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                .padding(.horizontal)

                if !photo.taggedPeople.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tagged People")
                            .font(.headline)
                            .padding(.horizontal)

                        FlowLayout(spacing: 8) {
                            ForEach(photo.taggedPeople) { person in
                                HStack(spacing: 4) {
                                    PersonAvatarView(
                                        name: person.name,
                                        type: person.type,
                                        profilePhotoRemoteId: person.profilePhotoId,
                                        size: 20
                                    )
                                    Text(person.name)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.quaternary, in: Capsule())
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                NavigationLink(destination: TagPeopleView(photo: photo)) {
                    Label("Manage Tagged People", systemImage: "person.crop.circle.badge.plus")
                }
                .padding(.horizontal)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Photo", systemImage: "trash")
                }
                .padding(.top, 8)
            }
            .padding(.vertical)
        }
    }
}
