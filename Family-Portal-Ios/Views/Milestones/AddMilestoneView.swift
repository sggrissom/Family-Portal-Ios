import SwiftUI
import SwiftData

/// The milestone form: who, then what happened (focused), then a category chip, then when. Photos and tags sit behind one disclosure, since most milestones have neither.
/// Save opens the milestone's own page in place of the form; its Done returns to wherever the form was opened from.
struct AddMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

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
    @FocusState private var isTextFocused: Bool

    private var person: Person? {
        people.first { $0.id == selectedPersonId }
    }

    private var photoChoices: [Photo] {
        milestonePhotoChoices(for: nil, person: person, allPhotos: [])
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

                Section(Copy.milestone.category) {
                    FlowLayout(spacing: 8) {
                        ForEach(MilestoneCategory.allCases, id: \.self) { option in
                            categoryChip(option)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    WhenControl(entry: $when, birthday: person?.birthday)
                        .id(person?.id)
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
