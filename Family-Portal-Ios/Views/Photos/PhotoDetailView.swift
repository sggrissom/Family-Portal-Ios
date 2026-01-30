import SwiftUI
import SwiftData

struct PhotoDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
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
                            } catch {
                                print("Failed to sync delete photo: \(error)")
                            }
                            dismiss()
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
    @Bindable var photo: Photo
    @Binding var showDeleteConfirmation: Bool
    @State private var isZoomed = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    if let imageData = photo.imageData, let uiImage = UIImage(data: imageData) {
                        let baseView = ZoomableView(isZoomed: $isZoomed) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                        }
                        .frame(maxWidth: .infinity, maxHeight: isZoomed ? proxy.size.height : nil)
                        .background(isZoomed ? Color.black : Color.clear)
                        .clipShape(isZoomed ? Rectangle() : RoundedRectangle(cornerRadius: 12))
                        .padding(isZoomed ? .zero : .horizontal)
                        Group {
                            if isZoomed {
                                baseView.ignoresSafeArea()
                            } else {
                                baseView
                            }
                        }
                    } else if let remoteId = photo.remoteId, let remoteInt = Int(remoteId) {
                        let baseView = ZoomableView(isZoomed: $isZoomed) {
                            RemotePhotoView(remoteId: remoteInt, size: .xlarge, contentMode: .fit)
                                .scaledToFit()
                        }
                        .frame(maxWidth: .infinity, maxHeight: isZoomed ? proxy.size.height : nil)
                        .background(isZoomed ? Color.black : Color.clear)
                        .clipShape(isZoomed ? Rectangle() : RoundedRectangle(cornerRadius: 12))
                        .padding(isZoomed ? .zero : .horizontal)
                        Group {
                            if isZoomed {
                                baseView.ignoresSafeArea()
                            } else {
                                baseView
                            }
                        }
                    } else {
                        ContentUnavailableView("No Photo", systemImage: "photo")
                            .padding(.horizontal)
                    }

                    if !isZoomed {
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
                }
                .padding(.vertical)
            }
            .scrollDisabled(isZoomed)
        }
    }
}
