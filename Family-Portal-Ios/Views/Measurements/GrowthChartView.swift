import SwiftUI
import Charts

/// A person's measurements over time, plotted in one unit — everything is converted through `MeasurementConversion` before it reaches a mark, since records keep whatever unit they were entered in.
struct GrowthChartView: View {
    let measurements: [GrowthData]
    let measurementType: MeasurementType

    /// The unit the axis is in. Starts at whatever the family measured in most recently, and can be switched.
    @State private var displayUnit: MeasurementUnit?

    private var resolvedUnit: MeasurementUnit {
        displayUnit ?? MeasurementConversion.preferredUnit(for: measurements, type: measurementType)
    }

    /// Converted once per render rather than inside the mark builders, where the same record would be converted twice and none of it could be tested.
    private var points: [MeasurementConversion.Normalized] {
        MeasurementConversion.normalized(measurements, type: measurementType, to: resolvedUnit)
    }

    private var chartColor: Color {
        measurementType == .height ? .blue : .red
    }

    private var unitChoices: [MeasurementUnit] {
        measurementType.validUnits
    }

    var body: some View {
        VStack(spacing: 8) {
            chart
            unitPicker
        }
        .padding()
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Value", point.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(chartColor)

            PointMark(
                x: .value("Date", point.date),
                y: .value("Value", point.value)
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
        .chartYAxisLabel(MeasurementConversion.abbreviation(resolvedUnit), position: .leading)
        .frame(height: 220)
        // A line chart is nothing to VoiceOver without this.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(measurementType.rawValue.capitalized) over time, in \(MeasurementConversion.abbreviation(resolvedUnit))")
        .accessibilityValue(accessibilitySummary)
    }

    @ViewBuilder
    private var unitPicker: some View {
        if unitChoices.count > 1 {
            Picker("Units", selection: Binding(
                get: { resolvedUnit },
                set: { displayUnit = $0 }
            )) {
                ForEach(unitChoices, id: \.self) { unit in
                    Text(MeasurementConversion.abbreviation(unit)).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Chart units")
        }
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else {
            return "No measurements"
        }
        let unit = resolvedUnit
        let span = first.date.formatted(.dateTime.month(.abbreviated).year())
        let end = last.date.formatted(.dateTime.month(.abbreviated).year())
        return "\(points.count) measurements, from "
            + "\(MeasurementConversion.format(first.value, unit: unit)) in \(span) to "
            + "\(MeasurementConversion.format(last.value, unit: unit)) in \(end)"
    }
}
