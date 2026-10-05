import SwiftUI

struct MeasurementRowView: View {
    let measurement: GrowthData

    var body: some View {
        HStack {
            Text(MeasurementConversion.format(measurement))
                .font(.body)
            Spacer()
            Text(measurement.date.displayDay().formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
