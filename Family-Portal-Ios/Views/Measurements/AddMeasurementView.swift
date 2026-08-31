import SwiftUI
import SwiftData

struct AddMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    /// The whole roster rather than one person, for the reason given in `AddMilestoneView`: a `@Query` predicate cannot follow a `@State` selection.
    @Query(sort: \Person.name) private var people: [Person]
    /// For the fallback in `QuickAddDefaults.person`, which bands the roster to find the youngest generation.
    @Query private var relations: [PersonRelation]

    private let defaults = QuickAddDefaults()

    @State private var selectedPersonId: UUID?
    @State private var measurementType: MeasurementType
    @State private var valueText: String = ""
    @State private var unit: MeasurementUnit
    @State private var date: Date = .now
    @State private var isSaving = false
    /// Set by "Save and add another", so the sheet stays up and the next value lands on the same person and date.
    @FocusState private var isValueFocused: Bool

    private var person: Person? {
        people.first { $0.id == selectedPersonId }
    }

    private var isValid: Bool {
        person != nil && Double(valueText) != nil
    }

    /// `nil` opens the sheet asking who this is for. A caller already standing on somebody names them, and can still be corrected in place.
    /// `initialType` nil means the caller has no opinion — the quick-add menu — so the type last taken is used.
    init(personId: UUID? = nil, initialType: MeasurementType? = nil) {
        let defaults = QuickAddDefaults()
        let type = initialType ?? defaults.rememberedMeasurementType ?? .height
        _selectedPersonId = State(initialValue: personId)
        _measurementType = State(initialValue: type)
        _unit = State(initialValue: defaults.unit(for: type))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PersonPickerRow(people: people, selection: $selectedPersonId)
                }

                Picker("Type", selection: $measurementType) {
                    ForEach(MeasurementType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized)
                    }
                }

                TextField("Value", text: $valueText)
                    .keyboardType(.decimalPad)
                    .focused($isValueFocused)

                Picker("Unit", selection: $unit) {
                    ForEach(measurementType.validUnits, id: \.self) { u in
                        Text(u.rawValue.capitalized)
                    }
                }

                Section {
                    DateEntryPicker(birthday: person?.birthday, date: $date)
                        // Keyed on the person, for the reason given in `AddMilestoneView`: an age is resolved against the birthday the picker was handed.
                        .id(person?.id)
                }

                Section {
                    // Height and weight are taken in the same minute for the same person, and without this that is two full trips through the sheet.
                    Button("Save and Add Another") {
                        save(keepingOpen: true)
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .navigationTitle("Add Measurement")
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
            .onChange(of: measurementType) { _, newType in
                unit = defaults.unit(for: newType)
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

    private func save(keepingOpen: Bool = false) {
        guard let value = Double(valueText), let person else { return }
        isSaving = true
        let measurement = GrowthData(measurementType: measurementType, value: value, unit: unit, date: date)
        measurement.person = person
        modelContext.insert(measurement)
        defaults.rememberPerson(person.id)
        defaults.rememberMeasurement(type: measurementType, unit: unit)

        if keepingOpen {
            // The person and the date are what the next measurement shares; the value is the only thing that changes.
            valueText = ""
            isSaving = false
            isValueFocused = true
        }

        Task {
            do {
                try await syncService?.addGrowthData(measurement, for: person)
                if !keepingOpen { dismiss() }
            } catch {
                // The sheet has to go before the error can be shown: an alert owned by a closing sheet never appears.
                dismiss()
                errorPresenter?.report(error, title: "Couldn't Save Measurement")
            }
        }
    }
}
