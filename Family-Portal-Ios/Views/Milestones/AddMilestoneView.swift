import SwiftUI
import SwiftData

struct AddMilestoneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var people: [Person]
    private var person: Person? { people.first }

    @State private var descriptionText: String = ""
    @State private var category: MilestoneCategory = .development
    @State private var date: Date = .now

    private var isValid: Bool {
        !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty
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
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
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
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        guard let person else { return }
        let milestone = Milestone(descriptionText: descriptionText.trimmingCharacters(in: .whitespaces), category: category, date: date)
        milestone.person = person
        modelContext.insert(milestone)
        dismiss()
    }
}
