import SwiftUI
import SwiftData

struct AddPersonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    @State private var name = ""
    @State private var type: PersonType = .parent
    @State private var gender: Gender = .male
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

                // Not optional: the server rejects an empty birthdate (validateAddPersonRequest) and every age in the app is derived from it.
                Section {
                    DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                } header: {
                    Text("Birthday")
                } footer: {
                    Text("Used to calculate ages across the app.")
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
            birthday: birthday
        )
        modelContext.insert(person)

        Task {
            do {
                try await syncService?.addPerson(person)
                dismiss()
            } catch {
                // Not a network failure — `addPerson` only queues, so getting here means the person can never be pushed as entered.
                dismiss()
                errorPresenter?.report(error, title: "Couldn't Save Person")
            }
        }
    }
}
