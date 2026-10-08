import SwiftUI
import SwiftData

struct EditMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    let milestone: Milestone

    @State private var descriptionText: String
    @State private var category: MilestoneCategory
    @State private var context: String
    @State private var date: Date
    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var didSeedSelection = false
    @State private var artwork: [PickedArtwork] = []
    /// `SuggestMilestonePhotos`' answer, as server ids, best first. Offered, never attached until tapped.
    @State private var suggestedPhotoRemoteIds: [Int] = []

    /// Every photo in the store, so an attachment made elsewhere can be matched back to a local record — see `milestonePhotoChoices`.
    @Query private var allPhotos: [Photo]

    init(milestone: Milestone) {
        self.milestone = milestone
        _descriptionText = State(initialValue: milestone.descriptionText)
        _category = State(initialValue: milestone.category)
        _context = State(initialValue: milestone.context)
        _date = State(initialValue: milestone.date.displayDay())
    }

    private var isValid: Bool {
        !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var photoChoices: [Photo] {
        milestonePhotoChoices(for: milestone, person: milestone.person, allPhotos: allPhotos)
    }

    /// The choices the milestone has attached right now.
    private var attachedChoices: [Photo] {
        let attached = Set(milestone.photoRemoteIds)
        return photoChoices.filter { photo in photo.remoteId.flatMap(Int.init).map { attached.contains($0) } ?? false }
    }

    /// What the milestone had attached when the editor opened. Not suggested again: they are in the picker already.
    private var originallyAttached: Set<Int> { Set(milestone.photoRemoteIds) }

    private var suggestedPhotos: [Photo] {
        MilestonePhotoSuggestions.offered(suggestedPhotoRemoteIds, choices: photoChoices, alreadyAttached: originallyAttached)
    }

    /// What the suggestions depend on. A change restarts the lookup after a pause, so typing settles first and an answer for older words is never shown.
    private var lookupKey: String {
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return [milestone.person?.remoteId ?? "-", text, dateToAPIString(date.localRecordDay()), String(network?.isConnected ?? true)].joined(separator: "|")
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
                    TextField(category.entryPrompt.placeholder, text: $descriptionText, axis: .vertical)
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

                if !suggestedPhotos.isEmpty {
                    Section(Copy.milestone.photosAroundThen) {
                        SuggestedPhotosRow(photos: suggestedPhotos, selection: $selectedPhotoIds)
                    }
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
                selectedPhotoIds = Set(attachedChoices.map(\.id))
            }
            .task(id: lookupKey) {
                await lookUpSuggestions()
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

    /// Photos of the person from around the milestone's date. Waits for the inputs to settle; a newer key cancels this one. Offline, or on any failure, the row empties and the selection is left exactly as it was.
    private func lookUpSuggestions() async {
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }

        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard network?.isConnected ?? true,
              let personId = milestone.person?.remoteId.flatMap(Int.init),
              text.count >= 3 else {
            suggestedPhotoRemoteIds = []
            return
        }
        let ids = await AnalysisService.shared.suggestMilestonePhotos(
            personId: personId,
            description: text,
            date: date.localRecordDay(),
            excludeIds: Array(originallyAttached)
        )
        if !Task.isCancelled {
            suggestedPhotoRemoteIds = ids
        }
    }

    private func save() {
        milestone.category = category
        milestone.setEntry(descriptionText, context: context)
        milestone.date = date.localRecordDay()

        // `photoIds` is the complete set the milestone should end up with, so an empty selection detaches everything — safe only once the seed has run, since before that an empty selection means "not loaded yet".
        let chosen = didSeedSelection ? photoChoices.filter { selectedPhotoIds.contains($0.id) } : nil
        let attached = attachedChoices
        let picked = category == .artwork ? artwork : []

        dismiss()

        Task { [milestone, modelContext] in
            do {
                var photos = chosen
                if let artist = milestone.person, !picked.isEmpty {
                    // New pieces join the selection — or, without a seeded one, what the milestone already has.
                    photos = (chosen ?? attached)
                        + (try await ArtworkPhotos.queue(picked, artist: artist, context: modelContext, syncService: syncService))
                }
                try await syncService?.updateMilestone(milestone, photos: photos)
            } catch {
                errorPresenter?.report(error, title: "Couldn't Save Milestone")
            }
        }
    }
}
