import SwiftUI
import SwiftData

/// Serves both adding and editing, mirroring the website's
/// `milestones/edit-milestone.tsx`.
struct AddMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?

    @Query private var people: [Person]
    private var person: Person? { people.first }

    /// nil when adding.
    private let existing: Milestone?

    @State private var descriptionText: String
    @State private var category: MilestoneCategory
    @State private var dateMode: DateEntryMode
    @State private var date: Date
    @State private var ageYears: Int
    @State private var ageMonths: Int
    @State private var isSaving = false

    private var isValid: Bool {
        !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(personId: UUID) {
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
        existing = nil
        _descriptionText = State(initialValue: "")
        _category = State(initialValue: .development)
        _dateMode = State(initialValue: .today)
        _date = State(initialValue: .now)
        _ageYears = State(initialValue: 0)
        _ageMonths = State(initialValue: 0)
    }

    init(editing milestone: Milestone, personId: UUID) {
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
        existing = milestone
        _descriptionText = State(initialValue: milestone.descriptionText)
        _category = State(initialValue: milestone.category)
        _dateMode = State(initialValue: .date)
        _date = State(initialValue: milestone.date)
        _ageYears = State(initialValue: 0)
        _ageMonths = State(initialValue: 0)
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
                    DateEntryField(
                        mode: $dateMode,
                        date: $date,
                        ageYears: $ageYears,
                        ageMonths: $ageMonths,
                        birthday: person?.birthday
                    )
                }
            }
            .navigationTitle(existing == nil ? "Add Milestone" : "Edit Milestone")
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

        let entry = DateEntryField.resolve(
            mode: dateMode,
            date: date,
            ageYears: ageYears,
            ageMonths: ageMonths,
            birthday: person.birthday
        )
        let trimmed = descriptionText.trimmingCharacters(in: .whitespaces)

        let milestone: Milestone
        if let existing {
            existing.descriptionText = trimmed
            existing.category = category
            existing.date = entry.date
            milestone = existing
        } else {
            milestone = Milestone(descriptionText: trimmed, category: category, date: entry.date)
            milestone.person = person
            modelContext.insert(milestone)
        }

        let isEdit = existing != nil

        // Dismiss without waiting on the network: the write already landed
        // locally and the queue guarantees delivery.
        dismiss()

        Task {
            do {
                if isEdit {
                    try await syncService?.updateMilestone(milestone, dateEntry: entry)
                } else {
                    try await syncService?.addMilestone(milestone, for: person, dateEntry: entry)
                }
            } catch {
                print("Failed to sync milestone: \(error)")
            }
        }
    }
}
