import SwiftUI
import SwiftData

/// The milestone form: who, then what happened (focused), then a category chip, then when. Photos and tags sit behind one disclosure, since most milestones have neither.
/// Save opens the milestone's own page in place of the form; its Done returns to wherever the form was opened from.
struct AddMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?

    /// The whole roster rather than one person: a `@Query` predicate is fixed at `init` and cannot follow a `@State` selection.
    @Query(sort: \Person.name) private var people: [Person]
    /// For the fallback in `QuickAddDefaults.person`, which bands the roster to find the youngest generation.
    @Query private var relations: [PersonRelation]

    private let defaults = QuickAddDefaults()

    @State private var selectedPersonId: UUID?
    @State private var descriptionText = ""
    @State private var category: MilestoneCategory = .development
    @State private var when = WhenEntry()
    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var tagRemoteIds: [Int] = []
    @State private var showsMore = false
    @State private var error: String?
    @State private var isSaving = false
    @State private var saved: Milestone?
    /// Set by the user's own tap on a chip; after that a suggestion never moves the selection.
    @State private var categoryTouched = false
    /// The selected chip came from `SuggestMilestoneCategory`, and is marked as such.
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

    /// What the suggestions depend on. A change restarts the lookup after a pause, the way the web waits for typing to stop.
    private var lookupKey: String {
        let text = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = when.problem == nil ? when.resolvedDate(birthday: person?.birthday).map { dateToAPIString($0) } : nil
        return [person?.remoteId ?? "-", text, date ?? "-", String(network?.isConnected ?? true)].joined(separator: "|")
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
                    PersonChips(selection: $selectedPersonId)
                }

                Section(Copy.milestone.whatHappened) {
                    TextField(Copy.milestone.placeholder, text: $descriptionText, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($isTextFocused)
                }

                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(MilestoneCategory.allCases, id: \.self) { option in
                            categoryChip(option)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(categorySuggested ? "\(Copy.milestone.category) · \(Copy.milestone.suggested)" : Copy.milestone.category)
                }

                Section {
                    WhenControl(entry: $when, birthday: person?.birthday)
                        .id(person?.id)
                }

                if !suggestedPhotos.isEmpty {
                    Section(Copy.milestone.photosAroundThen) {
                        suggestedPhotoRow
                    }
                }

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
                        in: people,
                        remembered: defaults.rememberedPersonId,
                        relations: relations.map(\.edge)
                    )?.id
                }
                isTextFocused = true
            }
        }
    }

    private func categoryChip(_ option: MilestoneCategory) -> some View {
        let selected = category == option
        return Button {
            category = option
            categoryTouched = true
            categorySuggested = false
        } label: {
            Label(option.label, systemImage: option.icon)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? .white : option.color)
                .background(selected ? option.color : option.color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var suggestedPhotoRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestedPhotos) { photo in
                    let selected = selectedPhotoIds.contains(photo.id)
                    Button {
                        if selected {
                            selectedPhotoIds.remove(photo.id)
                        } else {
                            selectedPhotoIds.insert(photo.id)
                        }
                    } label: {
                        RemotePhotoView(remoteId: photo.remoteId.flatMap(Int.init) ?? 0, size: .thumb)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color.accentColor)
                                        .padding(4)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selected ? Copy.milestone.detachPhoto : Copy.milestone.attachPhoto)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// A category (unless the user picked one) and photos from around then. Waits for the inputs to settle first; a newer key cancels this one mid-wait. Offline, or on any failure, nothing changes.
    private func lookUpSuggestions() async {
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, network?.isConnected ?? true else { return }

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
        let milestone = Milestone(descriptionText: text, category: category, date: date)
        milestone.person = person
        modelContext.insert(milestone)
        defaults.rememberPerson(person.id)

        // Resolved here rather than in the picker, so a photo untagged or deleted while the form was open drops out instead of being sent as an id the server rejects.
        let photos = photoChoices.filter { selectedPhotoIds.contains($0.id) }
        let tags = tagRemoteIds

        Task {
            do {
                // The tags go in the create itself, so there is no window where the milestone is on the server without them.
                try await syncService?.addMilestone(
                    milestone,
                    for: person,
                    photos: photos.isEmpty ? nil : photos,
                    tagRemoteIds: tags.isEmpty ? nil : tags
                )
                saved = milestone
            } catch {
                dismiss()
                errorPresenter?.report(error, title: "Couldn't Save Milestone")
            }
        }
    }
}
