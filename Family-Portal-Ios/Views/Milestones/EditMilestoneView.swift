import SwiftUI
import SwiftData

struct EditMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(NetworkMonitor.self) private var network

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
    @FocusState private var isTextFocused: Bool

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

    private var lookupKey: String {
        MilestoneSuggestionLookup.key(
            personRemoteId: milestone.person?.remoteId,
            text: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            day: date.localRecordDay(),
            isConnected: network.isConnected
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(Copy.milestone.category, selection: $category) {
                        ForEach(MilestoneCategory.allCases, id: \.self) { option in
                            Text(option.label)
                        }
                    }
                }

                MilestoneTextSections(category: category, descriptionText: $descriptionText, context: $context, isFocused: $isTextFocused)

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                MilestonePhotoSections(category: category, artwork: $artwork, suggestedPhotos: suggestedPhotos, selectedPhotoIds: $selectedPhotoIds)

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
                    Button(Copy.milestone.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.milestone.save) {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    /// Photos of the person from around the milestone's date. Waits for the inputs to settle; a newer key cancels this one. Offline, or on any failure, the row empties and the selection is left exactly as it was.
    private func lookUpSuggestions() async {
        guard await MilestoneSuggestionLookup.settle() else { return }

        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard network.isConnected,
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
                try await syncService.updateMilestone(milestone, photos: photos)
            } catch {
                errorPresenter.report(error, title: "Couldn't Save Milestone")
            }
        }
    }
}
