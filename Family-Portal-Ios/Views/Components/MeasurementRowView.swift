import SwiftUI

struct MeasurementRowView: View {
    let value: Double
    let unit: MeasurementUnit
    let date: Date

    private var formattedValue: String {
        let formatted = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted) \(unit.rawValue)"
    }

    var body: some View {
        HStack {
            Text(formattedValue)
                .font(.body)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
