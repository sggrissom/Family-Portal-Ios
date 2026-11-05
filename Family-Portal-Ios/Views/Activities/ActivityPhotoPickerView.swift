import PhotosUI
import SwiftUI
import SwiftData
import OSLog

/// Which photos are of this performance, or of this competition.
/// A performance's photos (saved with it by `SaveAppearance`) and `SetEventPhotos` are whole-set writes over **remote** photo ids, so an attached id with no local record still gets a tile — a photo this grid cannot show is one the next save silently detaches.
/// Selection is by remote id, unlike `MilestonePhotoPickerView`: this path is online-only, so a photo with no remote id cannot be attached yet — which is why one picked from the library here is uploaded at once rather than queued.
struct ActivityPhotoPickerView: View {
    let attachedPhotoIds: [Int]
    let subject: String
    let save: @MainActor ([Int]) async throws -> Void
    let onSaved: @MainActor () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service
    @Query private var photos: [Photo]

    @State private var selection: [Int] = []
    @State private var didSeed = false
    @State private var saveError: String?
    @State private var isSaving = false
    /// Photos uploaded from here, which this device has no record of until the next pull.
    @State private var uploadedIds: [Int] = []
    @State private var newItems: [PhotosPickerItem] = []
    @State private var isUploading = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    private struct Choice: Identifiable {
        let remoteId: Int
        let photo: Photo?
        var id: Int { remoteId }
    }

    /// Attached-but-unknown ids come first — they are the ones a careless save would drop.
    private var choices: [Choice] {
        let local = photos
            .compactMap { photo -> Choice? in
                guard let remoteId = photo.serverId else { return nil }
                return Choice(remoteId: remoteId, photo: photo)
            }
            .sorted { ($0.photo?.photoDate ?? .distantPast) > ($1.photo?.photoDate ?? .distantPast) }

        let known = Set(local.map(\.remoteId))
        var seen = Set<Int>()
        let unresolved = (uploadedIds.reversed() + attachedPhotoIds)
            .filter { !known.contains($0) && seen.insert($0).inserted }
            .map { Choice(remoteId: $0, photo: nil) }

        return unresolved + local
    }

    private var isOverLimit: Bool {
        selection.count > ActivityFieldLimit.photosPerSubject
    }

    var body: some View {
        NavigationStack {
            Group {
                if choices.isEmpty {
                    ContentUnavailableView(
                        "No Photos Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Upload one below. A photo added elsewhere can be attached to a \(subject) once it finishes uploading.")
                    )
                } else {
                    ScrollView {
                        if let saveError {
                            Label(saveError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                        }

                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(choices) { choice in
                                Button {
                                    toggle(choice.remoteId)
                                } label: {
                                    tile(choice)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(
                                    selection.contains(choice.remoteId) ? .isSelected : []
                                )
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { commitSelection() }
                        .disabled(isSaving || isUploading || isOverLimit)
                }
                // A photo taken at the event, added without leaving: uploaded now and selected.
                ToolbarItem(placement: .bottomBar) {
                    if isUploading {
                        ProgressView("Uploading…")
                    } else {
                        PhotosPicker(selection: $newItems, matching: .images, photoLibrary: .shared()) {
                            Label("Upload New Photos", systemImage: "photo.badge.plus")
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .onChange(of: newItems) { _, items in
                guard !items.isEmpty else { return }
                newItems = []
                Task { await upload(items) }
            }
            .onAppear {
                guard !didSeed else { return }
                didSeed = true
                selection = attachedPhotoIds
            }
        }
    }

    @ViewBuilder
    private func tile(_ choice: Choice) -> some View {
        let position = selection.firstIndex(of: choice.remoteId)

        Group {
            if let photo = choice.photo {
                PhotoThumbnailView(
                    imageData: photo.imageData,
                    title: photo.title,
                    remoteId: photo.remoteId,
                    videoDurationMs: photo.videoBadgeDuration
                )
            } else {
                RemotePhotoView(remoteId: choice.remoteId, size: .thumb)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .overlay {
            if position != nil {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.blue, lineWidth: 3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let position {
                // The number, not a checkmark: the server writes these joins in the order they arrive and reads them back that way.
                Text("\(position + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(.blue))
                    .padding(4)
            }
        }
    }

    private func toggle(_ remoteId: Int) {
        if let index = selection.firstIndex(of: remoteId) {
            selection.remove(at: index)
        } else {
            selection.append(remoteId)
        }
    }

    private func upload(_ items: [PhotosPickerItem]) async {
        isUploading = true
        saveError = nil
        defer { isUploading = false }
        for item in items {
            do {
                let loaded = try await PhotoImporter.load(item)
                let remoteId = try await service.uploadPhoto(loaded.data, captureDate: loaded.captureDate)
                uploadedIds.append(remoteId)
                selection.append(remoteId)
            } catch {
                AppLog.activities.error("Uploading a photo failed: \(String(describing: error), privacy: .public)")
                saveError = error.localizedDescription
            }
        }
    }

    private func commitSelection() {
        saveError = nil
        isSaving = true
        let photoIds = selection

        Task {
            do {
                try await save(photoIds)
                await onSaved()
                dismiss()
            } catch {
                AppLog.activities.error(
                    "Attaching photos failed: \(String(describing: error), privacy: .public)"
                )
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
