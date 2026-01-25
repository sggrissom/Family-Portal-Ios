import SwiftUI
import SwiftData

struct AddMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?

    @Query private var people: [Person]
    private var person: Person? { people.first }

    @State private var measurementType: MeasurementType
    @State private var valueText: String = ""
    @State private var unit: MeasurementUnit
    @State private var date: Date = .now
    @State private var isSaving = false

    private var isValid: Bool {
        Double(valueText) != nil
    }

    init(personId: UUID, initialType: MeasurementType = .height) {
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
        _measurementType = State(initialValue: initialType)
        _unit = State(initialValue: initialType.defaultUnit)
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

                DatePicker("Date", selection: $date, displayedComponents: .date)
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
            } catch {
                print("Failed to sync growth data: \(error)")
            }
            dismiss()
        }
    }
}
