import SwiftUI
import SwiftData

struct EditPersonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?

    let person: Person

    @State private var name: String
    @State private var type: PersonType
    @State private var gender: Gender
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var isSaving = false

    init(person: Person) {
        self.person = person
        _name = State(initialValue: person.name)
        _type = State(initialValue: person.type)
        _gender = State(initialValue: person.gender)
        _hasBirthday = State(initialValue: person.birthday != nil)
        _birthday = State(initialValue: person.birthday ?? Date())
    }

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
            .navigationTitle("Edit Person")
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
        person.name = name
        person.type = type
        person.gender = gender
        person.birthday = hasBirthday ? birthday : nil

        Task {
            do {
                try await syncService?.updatePerson(person)
            } catch {
                print("Failed to sync person update: \(error)")
            }
            dismiss()
        }
    }
}
