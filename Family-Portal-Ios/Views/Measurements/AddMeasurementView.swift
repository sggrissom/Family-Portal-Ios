import SwiftUI
import SwiftData

struct AddMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    /// The whole roster rather than one person, for the reason given in `AddMilestoneView`: a `@Query` predicate cannot follow a `@State` selection.
    @Query(sort: \Person.name) private var people: [Person]

    @State private var selectedPersonId: UUID?
    @State private var measurementType: MeasurementType
    @State private var valueText: String = ""
    @State private var unit: MeasurementUnit
    @State private var date: Date = .now
    @State private var isSaving = false

    private var person: Person? {
        people.first { $0.id == selectedPersonId }
    }

    private var isValid: Bool {
        person != nil && Double(valueText) != nil
    }

    /// `nil` opens the sheet asking who this is for. A caller already standing on somebody names them, and can still be corrected in place.
    init(personId: UUID? = nil, initialType: MeasurementType = .height) {
        _selectedPersonId = State(initialValue: personId)
        _measurementType = State(initialValue: initialType)
        _unit = State(initialValue: initialType.defaultUnit)
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
                unit = newType.defaultUnit
            }
        }
    }

    private func save() {
        guard let value = Double(valueText), let person else { return }
        isSaving = true
        let measurement = GrowthData(measurementType: measurementType, value: value, unit: unit, date: date)
        measurement.person = person
        modelContext.insert(measurement)

        Task {
            do {
                try await syncService?.addGrowthData(measurement, for: person)
                dismiss()
            } catch {
                dismiss()
                errorPresenter?.report(error, title: "Couldn't Save Measurement")
            }
        }
    }
}
