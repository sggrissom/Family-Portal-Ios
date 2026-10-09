import SwiftUI
import SwiftData

/// The milestone form: who, then what happened (focused), then category, then when. Photos and tags sit behind one disclosure, since most milestones have neither.
/// Save opens the milestone's own page in place of the form; its Done returns to wherever the form was opened from.
struct AddMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Environment(AuthService.self) private var authService
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(NetworkMonitor.self) private var network

    /// The whole roster rather than one person: a `@Query` predicate is fixed at `init` and cannot follow a `@State` selection.
    @Query(sort: \Person.name) private var people: [Person]
    /// For the fallback in `QuickAddDefaults.person`, which bands the roster to find the youngest generation.
    @Query private var relations: [PersonRelation]

    private let defaults = QuickAddDefaults()

    @State private var selectedPersonId: UUID?
    @State private var descriptionText = ""
    @State private var category: MilestoneCategory = .development
    @State private var context = ""
    @State private var artwork: [PickedArtwork] = []
    @State private var when = WhenEntry()
    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var tagRemoteIds: [Int] = []
    @State private var showsMore = false
    @State private var error: String?
    @State private var isSaving = false
    @State private var saved: Milestone?
    /// Set by the user's own category selection; after that a suggestion never moves it.
    @State private var categoryTouched = false
    /// The selected category came from `SuggestMilestoneCategory`, and is marked as such.
    @State private var categorySuggested = false
    /// `SuggestMilestonePhotos`' answer, as server ids, best first. Unattached until tapped.
    @State private var suggestedPhotoRemoteIds: [Int] = []
    @FocusState private var isTextFocused: Bool

    private var person: Person? {
        people.first { $0.id == selectedPersonId }
    }

    private var photoChoices: [Photo] {
        milestonePhotoChoices(for: nil, person: person, allPhotos: [])
    }

    /// The suggested photos this device holds and could attach, in the server's order.
    private var suggestedPhotos: [Photo] {
        RemotePhotoResolution.resolve(suggestedPhotoRemoteIds, in: photoChoices)
    }

    private var lookupKey: String {
        MilestoneSuggestionLookup.key(
            personRemoteId: person?.remoteId,
            text: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            day: when.problem == nil ? when.resolvedDate(birthday: person?.birthday) : nil,
            isConnected: network.isConnected
        )
    }

    init(personId: UUID? = nil) {
        _selectedPersonId = State(initialValue: personId)
    }

    var body: some View {
        if let saved {
            MilestoneDetailSheetView(milestone: saved)
        } else {
            form
        }
    }

    private var form: some View {
        NavigationStack {
            Form {
                Section(Copy.milestone.who) {
                    PersonChips(selection: $selectedPersonId, contributableOnly: true)
                }

                MilestoneTextSections(category: category, descriptionText: $descriptionText, context: $context, isFocused: $isTextFocused)

                Section {
                    Picker(Copy.milestone.category, selection: Binding(
                        get: { category },
                        set: { option in
                            category = option
                            categoryTouched = true
                            categorySuggested = false
                        }
                    )) {
                        ForEach(MilestoneCategory.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .labelStyle(.titleAndIcon)
                } header: {
                    Text(categorySuggested ? "\(Copy.milestone.category) · \(Copy.milestone.suggested)" : Copy.milestone.category)
                }

                Section {
                    WhenControl(entry: $when, birthday: person?.birthday)
                        .id(person?.id)
                }

                MilestonePhotoSections(category: category, artwork: $artwork, suggestedPhotos: suggestedPhotos, selectedPhotoIds: $selectedPhotoIds)

                Section {
                    DisclosureGroup(Copy.milestone.more, isExpanded: $showsMore) {
                        NavigationLink {
                            MilestonePhotoPickerView(
                                photos: photoChoices,
                                emptyDescription: person.map { "Tag \($0.name) in a photo to attach it to a milestone." }
                                    ?? "Choose who this milestone is for to see their photos.",
                                selection: $selectedPhotoIds
                            )
                        } label: {
                            LabeledContent(Copy.milestone.photos, value: selectedPhotoIds.isEmpty ? "" : "\(selectedPhotoIds.count)")
                        }
                        NavigationLink {
                            // The picker applies each toggle through this closure; before the milestone exists, applying means remembering.
                            TagPickerView(tagRemoteIds: tagRemoteIds) { tagRemoteIds = $0 }
                        } label: {
                            LabeledContent(Copy.milestone.tags, value: tagRemoteIds.isEmpty ? "" : "\(tagRemoteIds.count)")
                        }
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(Copy.milestone.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.milestone.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? Copy.milestone.saving : Copy.milestone.save) { save() }
                        .disabled(isSaving)
                }
            }
            // The eligible photos are the person's, so a selection made against somebody else is no longer about anything.
            .onChange(of: selectedPersonId) { _, _ in
                selectedPhotoIds.removeAll()
                error = nil
            }
            .task(id: lookupKey) {
                await lookUpSuggestions()
            }
            .onAppear {
                if selectedPersonId == nil {
                    selectedPersonId = QuickAddDefaults.person(
                        in: people.filter { authService.access.canContribute(to: $0) },
                        remembered: defaults.rememberedPersonId,
                        relations: relations.map(\.edge)
                    )?.id
                }
                isTextFocused = true
            }
        }
    }

    /// A category (unless the user picked one) and photos from around then. Waits for the inputs to settle first; a newer key cancels this one mid-wait. Offline, or on any failure, nothing changes.
    private func lookUpSuggestions() async {
        guard await MilestoneSuggestionLookup.settle(), network.isConnected else { return }

        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let personId = person?.remoteId.flatMap(Int.init)
        let analysis = AnalysisService.shared

        if text.count >= 3, !categoryTouched,
           let suggestion = await analysis.suggestMilestoneCategory(description: text, personId: personId),
           !Task.isCancelled, !categoryTouched {
            category = suggestion
            categorySuggested = true
        }

        guard let personId, text.count >= 3, when.problem == nil,
              let date = when.resolvedDate(birthday: person?.birthday) else {
            suggestedPhotoRemoteIds = []
            return
        }
        // Nothing excluded, as on the web: a photo attached from the row stays in it, checked, so it can be unattached again.
        let ids = await analysis.suggestMilestonePhotos(personId: personId, description: text, date: date)
        if !Task.isCancelled {
            suggestedPhotoRemoteIds = ids
        }
    }

    private func save() {
        guard let person else {
            error = Copy.milestone.pickPerson
            return
        }
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            error = Copy.milestone.needsText
            return
        }
        if let problem = when.problem {
            error = problem
            return
        }
        guard let date = when.resolvedDate(birthday: person.birthday) else {
            error = "Enter an age in years"
            return
        }

        error = nil
        isSaving = true
        let milestone = Milestone(descriptionText: "", category: category, date: date)
        milestone.setEntry(text, context: context)
        milestone.person = person
        modelContext.insert(milestone)
        defaults.rememberPerson(person.id)

        // Resolved here rather than in the picker, so a photo untagged or deleted while the form was open drops out instead of being sent as an id the server rejects.
        let chosen = photoChoices.filter { selectedPhotoIds.contains($0.id) }
        let tags = tagRemoteIds
        let picked = category == .artwork ? artwork : []

        Task {
            do {
                let photos = chosen + (try await ArtworkPhotos.queue(
                    picked, artist: person, context: modelContext, syncService: syncService
                ))
                // The tags go in the create itself, so there is no window where the milestone is on the server without them.
                try await syncService.addMilestone(
                    milestone,
                    for: person,
                    photos: photos.isEmpty ? nil : photos,
                    tagRemoteIds: tags.isEmpty ? nil : tags
                )
                saved = milestone
            } catch {
                dismiss()
                errorPresenter.report(error, title: "Couldn't Save Milestone")
            }
        }
    }
}
