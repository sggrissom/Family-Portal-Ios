import SwiftUI
import SwiftData

struct AddMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    @Query private var people: [Person]
    private var person: Person? { people.first }

    @State private var descriptionText: String = ""
    @State private var category: MilestoneCategory = .development
    @State private var date: Date = .now
    @State private var selectedPhotoIds: Set<UUID> = []
    @State private var isSaving = false

    private var isValid: Bool {
        !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var photoChoices: [Photo] {
        milestonePhotoChoices(for: nil, person: person, allPhotos: [])
    }

    init(personId: UUID) {
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
    }

    var body: some View {
        NavigationStack {
            Form {
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
                }

                MilestonePhotosSection(
                    photos: photoChoices,
                    emptyDescription: "Tag \(person?.name ?? "this person") in a photo to attach it to a milestone.",
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
        }
    }

    private func save() {
        guard let person else { return }
        isSaving = true
        let milestone = Milestone(descriptionText: descriptionText.trimmingCharacters(in: .whitespaces), category: category, date: date)
        milestone.person = person
        modelContext.insert(milestone)

        // Resolved here rather than in the picker so a photo untagged or deleted
        // while the sheet was open drops out of the selection instead of being
        // sent as an id the server will reject.
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
