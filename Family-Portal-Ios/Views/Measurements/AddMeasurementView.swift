import SwiftUI
import SwiftData

/// Serves both adding and editing. `SyncService.updateGrowthData` has been
/// implemented and unreachable since it was written — this is the edit UI.
struct AddMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?

    @Query private var people: [Person]
    private var person: Person? { people.first }

    /// nil when adding.
    private let existing: GrowthData?

    @State private var measurementType: MeasurementType
    @State private var valueText: String
    @State private var unit: MeasurementUnit
    @State private var dateMode: DateEntryMode
    @State private var date: Date
    @State private var ageYears: Int
    @State private var ageMonths: Int
    @State private var isSaving = false
    @State private var saveError: String?

    private var isValid: Bool {
        Double(valueText) != nil
    }

    init(personId: UUID, initialType: MeasurementType = .height) {
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
        existing = nil
        _measurementType = State(initialValue: initialType)
        _valueText = State(initialValue: "")
        _unit = State(initialValue: initialType.defaultUnit)
        _dateMode = State(initialValue: .today)
        _date = State(initialValue: .now)
        _ageYears = State(initialValue: 0)
        _ageMonths = State(initialValue: 0)
    }

    init(editing measurement: GrowthData, personId: UUID) {
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
        existing = measurement
        _measurementType = State(initialValue: measurement.measurementType)
        _valueText = State(initialValue: Self.format(measurement.value))
        _unit = State(initialValue: measurement.unit)
        // Editing always starts on an explicit date: that's what's stored, and
        // re-deriving "today" or an age from it would be a guess.
        _dateMode = State(initialValue: .date)
        _date = State(initialValue: measurement.date)
        _ageYears = State(initialValue: 0)
        _ageMonths = State(initialValue: 0)
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    DateEntryField(
                        mode: $dateMode,
                        date: $date,
                        ageYears: $ageYears,
                        ageMonths: $ageMonths,
                        birthday: person?.birthday
                    )
                }

                if let saveError {
                    Section {
                        Text(saveError)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Measurement" : "Edit Measurement")
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
                // Keep an edit's stored unit unless the type actually changes
                // out from under it.
                if !newType.validUnits.contains(unit) {
                    unit = newType.defaultUnit
                }
            }
        }
    }

    private func save() {
        guard let value = Double(valueText), let person else { return }
        isSaving = true
        saveError = nil

        let entry = DateEntryField.resolve(
            mode: dateMode,
            date: date,
            ageYears: ageYears,
            ageMonths: ageMonths,
            birthday: person.birthday
        )

        let measurement: GrowthData
        if let existing {
            existing.measurementType = measurementType
            existing.value = value
            existing.unit = unit
            existing.date = entry.date
            measurement = existing
        } else {
            measurement = GrowthData(
                measurementType: measurementType,
                value: value,
                unit: unit,
                date: entry.date
            )
            measurement.person = person
            modelContext.insert(measurement)
        }

        let isEdit = existing != nil

        // Dismiss without waiting on the network: the write already landed
        // locally and the queue guarantees delivery.
        dismiss()

        Task {
            do {
                if isEdit {
                    try await syncService?.updateGrowthData(measurement, dateEntry: entry)
                } else {
                    try await syncService?.addGrowthData(measurement, for: person, dateEntry: entry)
                }
            } catch {
                print("Failed to sync growth data: \(error)")
            }
        }
    }
}
