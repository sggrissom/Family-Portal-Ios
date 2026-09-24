import SwiftUI
import SwiftData

struct EditMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    let measurement: GrowthData

    @State private var measurementType: MeasurementType
    @State private var valueText: String
    @State private var unit: MeasurementUnit
    @State private var usesPoundsAndOunces: Bool
    @State private var poundsText: String
    @State private var ouncesText: String
    @State private var date: Date
    @FocusState private var isPoundsFocused: Bool

    init(measurement: GrowthData) {
        self.measurement = measurement
        _measurementType = State(initialValue: measurement.measurementType)
        _valueText = State(initialValue: Self.format(measurement.value))
        _unit = State(initialValue: measurement.unit)
        _date = State(initialValue: measurement.date)

        let usesPoundsAndOunces = measurement.measurementType == .weight
            && MeasurementConversion.prefersPoundsAndOunces(
                measurement.value,
                unit: measurement.unit,
                ageMonths: MeasurementConversion.ageMonths(of: measurement)
            )
        let split = MeasurementConversion.splitPoundsAndOunces(measurement.value)
        _usesPoundsAndOunces = State(initialValue: usesPoundsAndOunces)
        _poundsText = State(initialValue: usesPoundsAndOunces ? String(split.pounds) : "")
        _ouncesText = State(initialValue: usesPoundsAndOunces ? MeasurementConversion.oneDecimal(split.ounces) : "")
    }

    /// Round-trips through the same text the row displays, so opening the sheet and saving without touching anything is a no-op.
    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    private var offersPoundsAndOunces: Bool {
        measurementType == .weight && unit == .pounds
    }

    private var enteredValue: Double? {
        if offersPoundsAndOunces && usesPoundsAndOunces {
            return MeasurementConversion.parsePoundsAndOunces(pounds: poundsText, ounces: ouncesText)
        }
        return Double(valueText)
    }

    private var isValid: Bool {
        enteredValue != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $measurementType) {
                    ForEach(MeasurementType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized)
                    }
                }

                if offersPoundsAndOunces && usesPoundsAndOunces {
                    PoundsAndOuncesFields(
                        pounds: $poundsText,
                        ounces: $ouncesText,
                        isPoundsFocused: $isPoundsFocused
                    )
                } else {
                    TextField("Value", text: $valueText)
                        .keyboardType(.decimalPad)
                }

                Picker("Unit", selection: $unit) {
                    ForEach(measurementType.validUnits, id: \.self) { option in
                        Text(option.rawValue.capitalized)
                    }
                }

                if offersPoundsAndOunces {
                    Toggle("Pounds & Ounces", isOn: $usesPoundsAndOunces)
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
            .onChange(of: usesPoundsAndOunces) { _, nowSplit in
                // Carry the number across, so flipping the toggle never throws away what was typed.
                if nowSplit, let value = Double(valueText) {
                    let split = MeasurementConversion.splitPoundsAndOunces(value)
                    poundsText = String(split.pounds)
                    ouncesText = MeasurementConversion.oneDecimal(split.ounces)
                } else if !nowSplit,
                          let value = MeasurementConversion.parsePoundsAndOunces(pounds: poundsText, ounces: ouncesText) {
                    valueText = Self.format(value)
                }
            }
            .onChange(of: measurementType) { oldType, newType in
                // Only when the type actually changes, or reopening the sheet would silently rewrite a unit the user chose.
                if oldType != newType {
                    unit = newType.defaultUnit
                }
            }
        }
    }

    private func save() {
        guard let value = enteredValue else { return }

        measurement.measurementType = measurementType
        measurement.value = value
        measurement.unit = unit
        measurement.date = date

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
