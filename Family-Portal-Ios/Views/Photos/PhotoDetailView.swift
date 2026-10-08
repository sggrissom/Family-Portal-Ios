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
    private let openedFrom: UUID?

    init(photoId: UUID, openedFrom: UUID? = nil) {
        self.openedFrom = openedFrom
        _photos = Query(filter: #Predicate<Photo> { photo in
            photo.id == photoId
        })
    }

    var body: some View {
        if let photo {
            PhotoDetailContent(photo: photo, openedFrom: openedFrom, showDeleteConfirmation: $showDeleteConfirmation)
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
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(AuthService.self) private var authService: AuthService?
    @Bindable var photo: Photo
    let openedFrom: UUID?
    @Binding var showDeleteConfirmation: Bool

    /// Values last handed to the sync queue, so leaving an untouched field doesn't enqueue a redundant update.
    @State private var syncedTitle: String?
    @State private var syncedDescription: String?
    @State private var saveError: String?
    @FocusState private var editingMetadata: Bool
    /// `GetPhoto`'s place and pending tag suggestions, fetched when online. Never stored: the mirrored list doesn't carry them, and they are the server's to change.
    @State private var details: GetPhotoResponseDTO?

    /// A view-only member sees the photo, its people and its tags, and none of the controls that change them.
    private var canEdit: Bool { authService.access.canContribute(to: photo) }

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

                VStack(spacing: 4) {
                    Text(photo.photoDate.isUTCMidnight
                         ? photo.photoDate.displayDay().formatted(date: .long, time: .omitted)
                         : photo.photoDate.formatted(Date.FormatStyle(date: .long, time: .shortened, timeZone: .gmt)))
                    if let place = details?.place, !place.name.isEmpty {
                        Label(place.name, systemImage: "mappin.and.ellipse")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if canEdit {
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
                } else if !photo.title.isEmpty || !photo.descriptionText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !photo.title.isEmpty {
                            Text(photo.title)
                                .font(.headline)
                        }
                        if !photo.descriptionText.isEmpty {
                            Text(photo.descriptionText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                if !taggedPeople.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tagged People")
                            .font(.headline)
                            .padding(.horizontal)

                        FlowLayout(spacing: 8) {
                            ForEach(taggedPeople) { person in
                                HStack(spacing: 4) {
                                    PersonAvatarView(person: person, size: 20)
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

                if canEdit {
                    NavigationLink(destination: TagPeopleView(photo: photo)) {
                        Label("Manage Tagged People", systemImage: "person.crop.circle.badge.plus")
                    }
                    .padding(.horizontal)
                }

                // Below the people and their Manage link, not between them: "tagged people" and "tags" are separate things that share a word.
                TagChipsView(tagRemoteIds: photo.tagRemoteIds, title: "Tags")
                    .padding(.horizontal)

                if canEdit {
                    SuggestedTagChips(
                        suggestions: details?.suggestions ?? [],
                        onAccept: accept,
                        onReject: reject
                    )
                    .padding(.horizontal)

                    NavigationLink {
                        TagPickerView(tagRemoteIds: photo.tagRemoteIds) { tagRemoteIds in
                            guard let syncService else { return }
                            try await syncService.updatePhotoTags(photo, tagRemoteIds: tagRemoteIds)
                        }
                    } label: {
                        Label("Edit Tags", systemImage: "tag")
                    }
                    .padding(.horizontal)
                }

                // Only people tagged in the photo are offered: the server refuses a profile photo the person is not associated with. And only those the account can change — a view-only member may still see a photo shared from a family they can edit, as on the web.
                if !profileCandidates.isEmpty {
                    Menu {
                        ForEach(profileCandidates) { person in
                            Button {
                                setProfilePhoto(for: person)
                            } label: {
                                if isProfilePhoto(of: person) {
                                    Label(person.name, systemImage: "checkmark")
                                } else {
                                    Text(person.name)
                                }
                            }
                            .disabled(isProfilePhoto(of: person))
                        }
                    } label: {
                        Label("Use as Profile Photo", systemImage: "person.crop.square")
                    }
                    .padding(.horizontal)
                }

                PhotoSameAgeSection(photo: photo, openedFrom: openedFrom)
                    .padding(.horizontal)

                // Deleting takes an admin of the photo's family, as on the web.
                if authService.access.canDelete(photo) {
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
        .onAppear {
            if syncedTitle == nil { syncedTitle = photo.title }
            if syncedDescription == nil { syncedDescription = photo.descriptionText }
        }
        .onChange(of: editingMetadata) { _, isEditing in
            if !isEditing { commitEdits() }
        }
        .onDisappear { commitEdits() }
        .task(id: photo.remoteId) {
            await loadDetails()
        }
        // Anyone who can see the photo can take a copy of it, view-only members included, as on the web.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                OriginalPhotoMenu(photo: photo)
            }
        }
    }

    // MARK: - Analysis

    private func loadDetails() async {
        guard let id = photo.remoteId.flatMap(Int.init), network?.isConnected ?? true else {
            details = nil
            return
        }
        if let fresh = await AnalysisService.shared.photoDetails(photoId: id), !Task.isCancelled {
            details = fresh
        }
    }

    /// Online only and never queued: the server creates the tag if it has to, so the photo's tags are taken from its answer afterwards rather than guessed at here.
    private func accept(_ suggestion: SuggestedTagDTO) {
        let before = details?.image.tagIds ?? photo.tagRemoteIds
        Task {
            do {
                try await AnalysisService.shared.acceptTagSuggestions([suggestion.id])
                await loadDetails()
                if let after = details?.image.tagIds {
                    await syncService?.adoptServerTags(before: before, after: after, for: photo)
                }
            } catch {
                errorPresenter?.report(error, title: Copy.tagSuggestions.acceptFailed)
            }
        }
    }

    private func reject(_ suggestion: SuggestedTagDTO) {
        Task {
            do {
                try await AnalysisService.shared.rejectTagSuggestions([suggestion.id])
                await loadDetails()
            } catch {
                errorPresenter?.report(error, title: Copy.tagSuggestions.rejectFailed)
            }
        }
    }

    /// SwiftData leaves to-many relationships unordered, so both the chips and the profile-photo menu would otherwise reshuffle between redraws.
    private var taggedPeople: [Person] {
        photo.taggedPeople.sorted { $0.name < $1.name }
    }

    private var profileCandidates: [Person] {
        let access = authService.access
        return taggedPeople.filter { access.canContribute(to: $0) }
    }

    private func isProfilePhoto(of person: Person) -> Bool {
        guard let profilePhotoId = person.profilePhotoId else { return false }
        return photo.remoteId.flatMap(Int.init) == profilePhotoId
    }

    private func setProfilePhoto(for person: Person) {
        Task {
            do {
                try await syncService?.setProfilePhoto(photo, for: person)
            } catch {
                errorPresenter?.report(error, title: "Couldn't Set Profile Photo")
            }
        }
    }

    /// Queues the edited title/description. Without this the next pull overwrites both fields from the server.
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
