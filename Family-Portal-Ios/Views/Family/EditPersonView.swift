import SwiftUI
import SwiftData

struct EditPersonView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    @Query(sort: \Person.name) private var people: [Person]

    let person: Person

    @State private var name: String
    @State private var gender: Gender
    @State private var birthday: Date
    @State private var isPregnancy: Bool
    @State private var isSaving = false

    init(person: Person) {
        self.person = person
        _name = State(initialValue: person.name)
        _gender = State(initialValue: person.gender)
        // A person predating the required-birthday change may still have none; showing today gives the user something concrete to correct.
        _birthday = State(initialValue: person.birthday ?? Date())
        _isPregnancy = State(initialValue: person.isPregnancy)
    }

    private var showsPregnancyOption: Bool {
        AgeCalculator.offersPregnancyOption(isPregnancy: isPregnancy, birthday: birthday)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Full Name", text: $name)
                }

                Section("Gender") {
                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases, id: \.self) { genderOption in
                            Text(genderOption.rawValue.capitalized)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // The flag is sent on every save whether or not it is on screen: `UpdatePerson` assigns it unconditionally, so an editor that left it out would quietly un-pregnancy the record.
                Section {
                    if showsPregnancyOption {
                        Toggle("Baby isn't born yet", isOn: $isPregnancy)
                    }
                    DatePicker(
                        isPregnancy ? "Due Date" : "Birthday",
                        selection: $birthday,
                        displayedComponents: .date
                    )
                } header: {
                    Text(isPregnancy ? "Due Date" : "Birthday")
                } footer: {
                    Text(isPregnancy
                         ? "An unborn record's age reads in weeks, and keeps counting in weeks past the due date."
                         : "Used to calculate ages across the app.")
                }

                // Relationships live on the server and are named from the whole graph, so there is nothing to show for a person it has never seen.
                if let personId = person.remoteId.flatMap(Int.init) {
                    PersonRelationsSection(
                        personId: personId,
                        personName: person.name,
                        candidates: relationCandidates
                    )
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

    /// Everyone but this person who has a server id to state a relationship against.
    private var relationCandidates: [Person] {
        people.filter { $0.id != person.id && $0.remoteId != nil }
    }

    private func savePerson() {
        isSaving = true
        person.name = name
        person.gender = gender
        person.birthday = birthday
        person.isPregnancy = isPregnancy

        Task {
            do {
                try await syncService?.updatePerson(person)
                dismiss()
            } catch {
                dismiss()
                errorPresenter?.report(error, title: "Couldn't Save Changes")
            }
        }
    }
}
