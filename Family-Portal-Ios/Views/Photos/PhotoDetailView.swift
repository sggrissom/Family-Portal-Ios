import SwiftUI
import SwiftData

struct PhotoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
    @Query private var photos: [Photo]
    @State private var showDeleteConfirmation = false

    private var photo: Photo? { photos.first }

    init(photoId: UUID) {
        _photos = Query(filter: #Predicate<Photo> { photo in
            photo.id == photoId
        })
    }

    var body: some View {
        if let photo {
            PhotoDetailContent(photo: photo, showDeleteConfirmation: $showDeleteConfirmation)
                .navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("Delete Photo", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        Task {
                            do {
                                try await syncService?.deletePhoto(photo)
                                dismiss()
                            } catch {
                                dismiss()
                                errorPresenter?.report(error, title: "Couldn't Delete Photo")
                            }
                        }
                    }
                } message: {
                    Text("This photo will be permanently deleted.")
                }
        } else {
            ContentUnavailableView("Photo Not Found", systemImage: "photo.slash")
        }
    }
}

private struct PhotoDetailContent: View {
    @Environment(SyncService.self) private var syncService: SyncService?
    @Bindable var photo: Photo
    @Binding var showDeleteConfirmation: Bool

    /// Values last handed to the sync queue, so leaving a field that wasn't
    /// touched doesn't enqueue a redundant update.
    @State private var syncedTitle: String?
    @State private var syncedDescription: String?
    @State private var saveError: String?
    @FocusState private var editingMetadata: Bool

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
                        .focused($editingMetadata)
                        .submitLabel(.done)
                        .onSubmit { commitEdits() }

                    TextField("Description", text: $photo.descriptionText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                        .focused($editingMetadata)

                    if let saveError {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
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
        .onAppear {
            if syncedTitle == nil { syncedTitle = photo.title }
            if syncedDescription == nil { syncedDescription = photo.descriptionText }
        }
        .onChange(of: editingMetadata) { _, isEditing in
            if !isEditing { commitEdits() }
        }
        .onDisappear { commitEdits() }
    }

    /// Queues the edited title/description. Without this the next `pullFamilyData`
    /// overwrites both fields from the server and the typing disappears.
    private func commitEdits() {
        let title = photo.title
        let description = photo.descriptionText
        guard title != syncedTitle || description != syncedDescription else { return }

        syncedTitle = title
        syncedDescription = description
        saveError = nil

        Task {
            do {
                try await syncService?.updatePhoto(photo)
            } catch {
                saveError = "Couldn't save changes: \(error.localizedDescription)"
                syncedTitle = nil
                syncedDescription = nil
            }
        }
    }
}
