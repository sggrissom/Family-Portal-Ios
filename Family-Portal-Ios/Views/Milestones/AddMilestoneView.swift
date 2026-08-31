import SwiftUI
import SwiftData

struct AddMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    /// The whole roster rather than one person: a `@Query` predicate is fixed at `init` and cannot follow a `@State` selection, so the sheet fetches everyone and picks in memory. A household is small enough that the breadth costs nothing.
    @Query(sort: \Person.name) private var people: [Person]
    /// For the fallback in `QuickAddDefaults.person`, which bands the roster to find the youngest generation.
    @Query private var relations: [PersonRelation]

    private let defaults = QuickAddDefaults()

    @State private var selectedPersonId: UUID?
    @State private var descriptionText: String = ""
    @State private var category: MilestoneCategory = .development
    @State private var date: Date = .now
    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var isSaving = false

    private var person: Person? {
        people.first { $0.id == selectedPersonId }
    }

    private var isValid: Bool {
        person != nil && !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var photoChoices: [Photo] {
        milestonePhotoChoices(for: nil, person: person, allPhotos: [])
    }

    /// `nil` opens the sheet asking who this is for. A caller already standing on somebody names them, and can still be corrected in place.
    init(personId: UUID? = nil) {
        _selectedPersonId = State(initialValue: personId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PersonPickerRow(people: people, selection: $selectedPersonId)
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(MilestoneCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue.capitalized)
                        }
                    }
                }

                Section {
                    TextField("Description", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    DateEntryPicker(birthday: person?.birthday, date: $date)
                        // Keyed on the person: the age steppers resolve against the birthday they were handed, so a picker carried over to somebody else would hold a date worked out from the wrong one.
                        .id(person?.id)
                }

                MilestonePhotosSection(
                    photos: photoChoices,
                    emptyDescription: person.map { "Tag \($0.name) in a photo to attach it to a milestone." }
                        ?? "Choose who this milestone is for to see their photos.",
                    selection: $selectedPhotoIds
                )
            }
            .navigationTitle("Add Milestone")
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
                    .disabled(!isValid || isSaving)
                }
            }
            // The eligible photos are the person's, so a selection made against somebody else is no longer about anything. `save()` filters through `photoChoices` and so could never send a stale id, but the count beside "Attach Photos" would go on claiming them.
            .onChange(of: selectedPersonId) { _, _ in
                selectedPhotoIds.removeAll()
            }
            .onAppear {
                if selectedPersonId == nil {
                    selectedPersonId = QuickAddDefaults.person(
                        in: people,
                        remembered: defaults.rememberedPersonId,
                        relations: relations.map(\.edge)
                    )?.id
                }
            }
        }
    }

    private func save() {
        guard let person else { return }
        isSaving = true
        let milestone = Milestone(descriptionText: descriptionText.trimmingCharacters(in: .whitespaces), category: category, date: date)
        milestone.person = person
        modelContext.insert(milestone)
        defaults.rememberPerson(person.id)

        // Resolved here rather than in the picker, so a photo untagged or deleted while the sheet was open drops out instead of being sent as an id the server rejects.
        let photos = photoChoices.filter { selectedPhotoIds.contains($0.id) }

        Task {
            do {
                try await syncService?.addMilestone(milestone, for: person, photos: photos)
                dismiss()
            } catch {
                dismiss()
                errorPresenter?.report(error, title: "Couldn't Save Milestone")
            }
        }
    }
}
