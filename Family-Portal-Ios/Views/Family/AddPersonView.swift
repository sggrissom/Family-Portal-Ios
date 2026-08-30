import SwiftUI
import SwiftData

struct AddPersonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?
    @Environment(AuthService.self) private var authService: AuthService?

    @Query(sort: \Person.name) private var people: [Person]
    @Query private var relations: [PersonRelation]

    @State private var name = ""
    @State private var relation: RelationOption?
    @State private var anchorId: UUID?
    @State private var coAnchorIds: [Int] = []
    @State private var gender: Gender = .male
    @State private var birthday = Date()
    @State private var isPregnancy = false
    @State private var isSaving = false

    private var anchor: Person? {
        people.first { $0.id == anchorId }
    }

    private var anchorRemoteId: Int? {
        anchor?.remoteId.flatMap(Int.init)
    }

    /// The person standing in for the signed-in account, which is who a relationship is most often stated against.
    private var ownPerson: Person? {
        guard let personId = authService?.currentUser?.personId, personId != 0 else { return nil }
        return people.first { $0.remoteId.flatMap(Int.init) == personId }
    }

    /// Whoever else the same statement probably also applies to. `personId` is 0 because this person does not exist yet, so nothing can already be stated about them.
    private var coAnchorSuggestions: [CoAnchorSuggestion] {
        guard let stated = relation?.stated, let anchorRemoteId else { return [] }
        return RelationGraph.coAnchorSuggestions(
            relations.map(\.edge),
            stated: stated,
            personId: 0,
            anchorId: anchorRemoteId
        )
    }

    private var showsPregnancyOption: Bool {
        AgeCalculator.offersPregnancyOption(isPregnancy: isPregnancy, birthday: birthday)
    }

    var body: some View {
        let suggestions = coAnchorSuggestions

        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Full Name", text: $name)
                }

                if !people.isEmpty {
                    Section {
                        Picker("Is the", selection: $relation) {
                            Text("Not saying yet").tag(RelationOption?.none)
                            ForEach(RelationOption.all) { option in
                                Text(option.label).tag(RelationOption?.some(option))
                            }
                        }

                        Picker("Of", selection: $anchorId) {
                            ForEach(people, id: \.id) { person in
                                Text(person.name).tag(UUID?.some(person.id))
                            }
                        }
                        .disabled(relation == nil)

                        CoAnchorPicker(
                            suggestions: suggestions,
                            people: people,
                            relationLabel: relation?.label ?? "",
                            disabled: isSaving,
                            selectedIds: $coAnchorIds
                        )
                    } header: {
                        Text("Relationship")
                    } footer: {
                        Text("Optional. Everyone else's relationship is worked out from the ones you state — a grandchild is the daughter or son of one of your children.")
                    }
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
            .onAppear {
                if anchorId == nil {
                    anchorId = (ownPerson ?? people.first)?.id
                }
            }
            // "Daughter" has already said which gender this is, so the picker below follows along; an ungendered word such as "child" leaves whatever was chosen by hand.
            .onChange(of: relation) { _, newValue in
                if let pickedGender = newValue?.gender {
                    gender = pickedGender
                }
            }
            // A tick must not outlive the question it answered — see `CoAnchorPicker.suggestionKey`.
            .onChange(of: CoAnchorPicker.suggestionKey(
                stated: relation?.stated,
                anchorId: anchorRemoteId ?? 0,
                suggestions: suggestions
            )) { _, _ in
                coAnchorIds = CoAnchorPicker.defaultSelection(coAnchorSuggestions)
            }
        }
    }

    private func savePerson() {
        isSaving = true
        let person = Person(
            name: name,
            gender: gender,
            birthday: birthday,
            isPregnancy: isPregnancy
        )
        modelContext.insert(person)

        // Read before the task suspends: the relationship travels with the create, and the pickers are gone by the time it runs.
        let statedRelation = relation?.stated ?? .none
        let statedAnchor = relation == nil ? nil : anchor
        let coAnchors = relation == nil
            ? []
            : people.filter { candidate in
                guard let remoteId = candidate.remoteId.flatMap(Int.init) else { return false }
                return coAnchorIds.contains(remoteId)
            }

        Task {
            do {
                try await syncService?.addPerson(
                    person,
                    stated: statedRelation,
                    anchor: statedAnchor,
                    additionalAnchors: coAnchors
                )
                dismiss()
            } catch {
                // Not a network failure — `addPerson` only queues, so getting here means the person can never be pushed as entered.
                dismiss()
                errorPresenter?.report(error, title: "Couldn't Save Person")
            }
        }
    }
}
