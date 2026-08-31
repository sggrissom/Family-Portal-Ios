import SwiftUI

/// The whole measurement, shown when a row is tapped. Tapping used to drop straight into the editor; a measurement
/// is recorded once and read back many times, so the editor now sits behind the Edit button here.
/// Shared by the measurement list and the timeline.
struct MeasurementDetailSheetView: View {
    let measurement: GrowthData

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    /// The same number in the other unit this type is kept in, so a record entered in pounds still answers "how many kilos".
    private var alternateValue: (label: String, value: String)? {
        guard let other = measurement.measurementType.validUnits.first(where: { $0 != measurement.unit }) else {
            return nil
        }
        let converted = MeasurementConversion.convert(measurement.value, from: measurement.unit, to: other)
        return ("In \(other.rawValue)", MeasurementConversion.format(converted, unit: other))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DetailSheetHeader(
                        icon: measurement.measurementType.icon,
                        tint: measurement.measurementType.color,
                        badge: measurement.measurementType.label,
                        title: MeasurementConversion.format(measurement.value, unit: measurement.unit),
                        titleFont: .largeTitle
                    )

                    DetailFieldGroup {
                        DetailFieldRow(
                            label: "Date",
                            value: measurement.date.formatted(date: .long, time: .omitted)
                        )

                        if let person = measurement.person {
                            Divider()
                            DetailFieldRow(label: "Person", value: person.name)

                            if let age = person.age(on: measurement.date) {
                                Divider()
                                DetailFieldRow(label: "Age", value: age)
                            }
                        }

                        if let alternateValue {
                            Divider()
                            DetailFieldRow(label: alternateValue.label, value: alternateValue.value)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") {
                        isEditing = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                EditMeasurementView(measurement: measurement)
            }
        }
    }
}
