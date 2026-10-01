import SwiftUI
import SwiftData

struct EditMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    let milestone: Milestone

    @State private var descriptionText: String
    @State private var category: MilestoneCategory
    @State private var context: String
    @State private var date: Date
    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var didSeedSelection = false
    @State private var artwork: [PickedArtwork] = []

    /// Every photo in the store, so an attachment made elsewhere can be matched back to a local record — see `milestonePhotoChoices`.
    @Query private var allPhotos: [Photo]

    init(milestone: Milestone) {
        self.milestone = milestone
        _descriptionText = State(initialValue: milestone.descriptionText)
        _category = State(initialValue: milestone.category)
        _context = State(initialValue: milestone.context)
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
                            Text(option.label)
                        }
                    }
                }

                Section(category.entryPrompt.label) {
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }

                if category == .quote {
                    Section(Copy.milestone.context) {
                        TextField(Copy.milestone.contextPlaceholder, text: $context)
                    }
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if category == .artwork {
                    ArtworkPhotosSection(picked: $artwork)
                }

                MilestonePhotosSection(
                    photos: photoChoices,
                    emptyDescription: "Tag \(milestone.person?.name ?? "this person") in a photo to attach it to a milestone.",
                    selection: $selectedPhotoIds
                )
            }
            // The `@Query` this needs isn't available in `init`, and re-seeding on the way back from the picker would undo the user's edits.
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
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        milestone.descriptionText = category == .quote ? Quotes.unquote(text) : text
        milestone.category = category
        milestone.context = category == .quote ? context.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        milestone.date = date

        // `photoIds` is the complete set the milestone should end up with, so an empty selection detaches everything — safe only once the seed has run, since before that an empty selection means "not loaded yet".
        let chosen = didSeedSelection ? photoChoices.filter { selectedPhotoIds.contains($0.id) } : nil
        let picked = category == .artwork ? artwork : []

        dismiss()

        Task { [milestone, modelContext] in
            do {
                var photos = chosen
                if let artist = milestone.person, !picked.isEmpty {
                    let added = try await ArtworkPhotos.queue(picked, artist: artist, context: modelContext, syncService: syncService)
                    // Without a seeded selection there is no complete set to add to, so the attached photos come from what the milestone already has.
                    let attached = Set(milestone.photoRemoteIds)
                    photos = (photos ?? photoChoices.filter { photo in
                        guard let remoteId = photo.remoteId.flatMap(Int.init) else { return false }
                        return attached.contains(remoteId)
                    }) + added
                }
                try await syncService?.updateMilestone(milestone, photos: photos)
            } catch {
                errorPresenter?.report(error, title: "Couldn't Save Milestone")
            }
        }
    }
}
