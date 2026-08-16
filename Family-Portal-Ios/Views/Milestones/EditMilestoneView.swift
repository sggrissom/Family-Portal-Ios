import SwiftUI
import SwiftData

/// `SyncService.updateMilestone` and the backend's `UpdateMilestone` proc were
/// both fully implemented and unreachable: a typo in a milestone could only be
/// fixed on the website (milestones/edit-milestone.tsx).
struct EditMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    let milestone: Milestone

    @State private var descriptionText: String
    @State private var category: MilestoneCategory
    @State private var date: Date
    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var didSeedSelection = false

    /// Every photo in the store, so an attachment made elsewhere can be matched
    /// back to a local record — see `milestonePhotoChoices`.
    @Query private var allPhotos: [Photo]

    init(milestone: Milestone) {
        self.milestone = milestone
        _descriptionText = State(initialValue: milestone.descriptionText)
        _category = State(initialValue: milestone.category)
        _date = State(initialValue: milestone.date)
    }

    private var isValid: Bool {
        !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var photoChoices: [Photo] {
        milestonePhotoChoices(for: milestone, person: milestone.person, allPhotos: allPhotos)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(MilestoneCategory.allCases, id: \.self) { option in
                            Text(option.rawValue.capitalized)
                        }
                    }
                }

                Section {
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                MilestonePhotosSection(
                    photos: photoChoices,
                    emptyDescription: "Tag \(milestone.person?.name ?? "this person") in a photo to attach it to a milestone.",
                    selection: $selectedPhotoIds
                )
            }
            // The `@Query` this needs isn't available in `init`, and re-seeding
            // on the way back from the picker would undo the user's edits.
            .task {
                guard !didSeedSelection else { return }
                didSeedSelection = true
                let attached = Set(milestone.photoRemoteIds)
                selectedPhotoIds = Set(
                    photoChoices
                        .filter { photo in
                            guard let remoteId = photo.remoteId.flatMap(Int.init) else { return false }
                            return attached.contains(remoteId)
                        }
                        .map { $0.id }
                )
            }
            .navigationTitle("Edit Milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        milestone.descriptionText = descriptionText.trimmingCharacters(in: .whitespaces)
        milestone.category = category
        milestone.date = date

        // `photoIds` is the complete set the milestone should end up with, so an
        // empty selection detaches everything. Sending it is safe only once the
        // seed has run — before that, an empty selection means "not loaded yet",
        // and `nil` leaves the server's attachments untouched — and only because
        // `photoChoices` includes whatever was already attached.
        let photos = didSeedSelection ? photoChoices.filter { selectedPhotoIds.contains($0.id) } : nil

        // The write is already local and the queue guarantees delivery, so the
        // sheet doesn't wait on the network to close.
        dismiss()

        Task { [milestone] in
            do {
                try await syncService?.updateMilestone(milestone, photos: photos)
            } catch {
                errorPresenter?.report(error, title: "Couldn't Save Milestone")
            }
        }
    }
}
