import SwiftUI
import SwiftData

/// `SyncService.updateGrowthData` and the backend's `UpdateGrowthData` proc were
/// both fully implemented and unreachable: nothing in the app could edit a
/// measurement once it was saved. The website has had this since GrowthForm.tsx.
struct EditMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    let measurement: GrowthData

    @State private var measurementType: MeasurementType
    @State private var valueText: String
    @State private var unit: MeasurementUnit
    @State private var date: Date

    init(measurement: GrowthData) {
        self.measurement = measurement
        _measurementType = State(initialValue: measurement.measurementType)
        _valueText = State(initialValue: Self.format(measurement.value))
        _unit = State(initialValue: measurement.unit)
        _date = State(initialValue: measurement.date)
    }

    /// Round-trips through the same text the row displays, so opening the sheet
    /// and saving without touching anything is a no-op.
    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    private var isValid: Bool {
        Double(valueText) != nil
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
                    ForEach(measurementType.validUnits, id: \.self) { option in
                        Text(option.rawValue.capitalized)
                    }
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Edit Measurement")
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
            .onChange(of: measurementType) { oldType, newType in
                // Only when the type actually changes, or reopening the sheet
                // would silently rewrite a unit the user chose.
                if oldType != newType {
                    unit = newType.defaultUnit
                }
            }
        }
    }

    private func save() {
        guard let value = Double(valueText) else { return }

        measurement.measurementType = measurementType
        measurement.value = value
        measurement.unit = unit
        measurement.date = date

        // The write is already local and the queue guarantees delivery, so the
        // sheet doesn't wait on the network to close.
        dismiss()

        Task { [measurement] in
            do {
                try await syncService?.updateGrowthData(measurement)
            } catch {
                errorPresenter?.report(error, title: "Couldn't Save Measurement")
            }
        }
    }
}
