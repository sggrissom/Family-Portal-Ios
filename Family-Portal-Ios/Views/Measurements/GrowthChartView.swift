import SwiftUI
import Charts

struct GrowthChartView: View {
    let measurements: [GrowthData]
    let measurementType: MeasurementType

    private var sortedMeasurements: [GrowthData] {
        measurements.sorted { $0.date < $1.date }
    }

    private var chartColor: Color {
        measurementType == .height ? .blue : .red
    }

    private var unitLabel: String {
        sortedMeasurements.first?.unit.rawValue ?? ""
    }

    var body: some View {
        Chart(sortedMeasurements, id: \.id) { measurement in
            LineMark(
                x: .value("Date", measurement.date),
                y: .value("Value", measurement.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(chartColor)

            PointMark(
                x: .value("Date", measurement.date),
                y: .value("Value", measurement.value)
            )
            .foregroundStyle(chartColor)
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartYAxisLabel(unitLabel, position: .leading)
        .frame(height: 220)
        .padding()
    }
}
