import SwiftUI
import SwiftData
import OSLog

/// Which photos are of this performance.
///
/// `SetAppearancePhotos` is a whole-set write over **remote** photo ids, so this
/// grid has to be able to show everything currently attached — a photo it cannot
/// show is a photo the next save silently detaches. That is why an attached id
/// with no local record still gets a tile, rendered straight from the server the
/// way `TagChipsView` renders a tag id it cannot resolve.
///
/// Selection is by remote id rather than by local id, which is the opposite of
/// `MilestonePhotoPickerView` and for a reason: milestones are queued, so a
/// photo still uploading is resolved at execution time and its choice is kept.
/// This path is online-only — there is nothing to resolve later — so a photo
/// with no remote id simply cannot be attached yet.
struct AppearancePhotoPickerView: View {
    let appearanceId: Int
    let attachedPhotoIds: [Int]
    let labels: ActivityLabels
    let onSaved: @MainActor () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ActivityService.self) private var service
    @Query private var photos: [Photo]

    @State private var selection: [Int] = []
    @State private var didSeed = false
    @State private var saveError: String?
    @State private var isSaving = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    /// One tile: a photo this device holds, or an id it does not.
    private struct Choice: Identifiable {
        let remoteId: Int
        let photo: Photo?
        var id: Int { remoteId }
    }

    /// Attached-but-unknown ids come first so they are impossible to miss —
    /// they are the ones a careless save would drop.
    private var choices: [Choice] {
        let local = photos
            .compactMap { photo -> Choice? in
                guard let remoteId = photo.remoteId.flatMap(Int.init) else { return nil }
                return Choice(remoteId: remoteId, photo: photo)
            }
            .sorted { ($0.photo?.photoDate ?? .distantPast) > ($1.photo?.photoDate ?? .distantPast) }

        let known = Set(local.map(\.remoteId))
        let unresolved = attachedPhotoIds
            .filter { !known.contains($0) }
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
                        description: Text("A photo has to finish uploading before it can be attached to a \(labels.appearance.lowercased()).")
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
                    Button("Save") { save() }
                        .disabled(isSaving || isOverLimit)
                }
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
                    remoteId: photo.remoteId
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
                // The number, not a checkmark: the server writes these joins in
                // the order they arrive and reads them back that way, so the
                // order of selection is the order they appear on the
                // performance.
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

    private func save() {
        saveError = nil
        isSaving = true
        let photoIds = selection

        Task {
            do {
                _ = try await service.setAppearancePhotos(appearanceId: appearanceId, photoIds: photoIds)
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
