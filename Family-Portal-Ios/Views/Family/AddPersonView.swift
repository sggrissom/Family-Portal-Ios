import SwiftUI
import SwiftData

struct AddPersonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?

    @State private var name = ""
    @State private var type: PersonType = .parent
    @State private var gender: Gender = .male
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Full Name", text: $name)
                }

                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(PersonType.allCases, id: \.self) { personType in
                            Text(personType.rawValue.capitalized)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Gender") {
                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases, id: \.self) { genderOption in
                            Text(genderOption.rawValue.capitalized)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Birthday") {
                    Toggle("Add Birthday", isOn: $hasBirthday)

                    if hasBirthday {
                        DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Add Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePerson()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func savePerson() {
        isSaving = true
        let person = Person(
            name: name,
            type: type,
            gender: gender,
            birthday: hasBirthday ? birthday : nil
        )
        modelContext.insert(person)

        Task {
            do {
                try await syncService?.addPerson(person)
            } catch {
                // Person is saved locally, sync will retry later
                print("Failed to sync person: \(error)")
            }
            dismiss()
        }
    }
}
