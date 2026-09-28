import SwiftUI
import Charts

/// One person's line on an age chart.
struct AgeSeries: Identifiable {
    let id: UUID
    let label: String
    let color: Color
    var points: [ChartPoint]
    /// Drawn quietly behind the main line — a sibling's curve on a person's own chart.
    var faint = false

    static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .brown, .indigo]
}

/// Measurements by age, in inches or pounds, over an optional percentile band — the web's `AgeChart`, drawn with Swift Charts.
/// Tapping a point opens its measurement. Dragging across the chart zooms to those ages, using `AgeChart`'s zoom model; **Reset zoom** undoes it.
struct AgeChartView: View {
    let series: [AgeSeries]
    let band: [BandRow]
    let type: MeasurementType
    @Binding var zoom: AgeRange?
    let onSelect: (UUID) -> Void

    @State private var dragRange: AgeRange?

    private var domain: ChartDomain? {
        AgeChart.chartDomain(series: series.map(\.points), band: band, zoom: zoom)
    }

    var body: some View {
        if let domain {
            VStack(alignment: .leading, spacing: 6) {
                chart(domain)
                    .frame(height: 260)
                HStack {
                    Text(Copy.ageChart.zoomHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if domain.zoomed {
                        Button(Copy.ageChart.resetZoom) { zoom = nil }
                            .font(.caption)
                    }
                }
                if series.count > 1 {
                    legend
                }
            }
        }
    }

    private func chart(_ domain: ChartDomain) -> some View {
        let unit = AgeChart.displayUnit(type)
        let ticks = AgeChart.ageTicks(minMonths: domain.minAge, maxMonths: domain.maxAge)
        let labels = Dictionary(ticks.map { ($0.months, $0.label) }, uniquingKeysWith: { first, _ in first })

        return Chart {
            ForEach(Array(domain.band.enumerated()), id: \.offset) { _, row in
                AreaMark(
                    x: .value("Age", row.ageMonths),
                    yStart: .value("P3", row.p3),
                    yEnd: .value("P97", row.p97),
                    series: .value("Band", "outer")
                )
                .foregroundStyle(Color.gray.opacity(0.10))
                AreaMark(
                    x: .value("Age", row.ageMonths),
                    yStart: .value("P15", row.p15),
                    yEnd: .value("P85", row.p85),
                    series: .value("Band", "inner")
                )
                .foregroundStyle(Color.gray.opacity(0.14))
                LineMark(
                    x: .value("Age", row.ageMonths),
                    y: .value("P50", row.p50),
                    series: .value("Band", "median")
                )
                .foregroundStyle(Color.gray.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            ForEach(series) { line in
                ForEach(line.points) { point in
                    LineMark(
                        x: .value("Age", point.ageMonths),
                        y: .value(unit, point.value),
                        series: .value("Person", line.id.uuidString)
                    )
                    .foregroundStyle(line.color.opacity(line.faint ? 0.35 : 1))
                    .lineStyle(StrokeStyle(lineWidth: line.faint ? 1.5 : 2.5))
                    PointMark(
                        x: .value("Age", point.ageMonths),
                        y: .value(unit, point.value)
                    )
                    .foregroundStyle(line.color.opacity(line.faint ? 0.35 : 1))
                    .symbolSize(line.faint ? 16 : 36)
                }
            }

            if let dragRange {
                RectangleMark(
                    xStart: .value("From", min(dragRange.from, dragRange.to)),
                    xEnd: .value("To", max(dragRange.from, dragRange.to))
                )
                .foregroundStyle(Color.accentColor.opacity(0.15))
            }
        }
        .chartXScale(domain: domain.minAge...domain.maxAge)
        .chartYScale(domain: domain.minValue...domain.maxValue)
        .chartXAxis {
            AxisMarks(values: ticks.map(\.months)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let months = value.as(Double.self) {
                        Text(labels[months] ?? "")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: AgeChart.niceTicks(min: domain.minValue, max: domain.maxValue)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text("\(Int(number.rounded())) \(unit)")
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard abs(value.translation.width) > 8,
                                      let from = age(at: value.startLocation, proxy: proxy, geometry: geometry),
                                      let to = age(at: value.location, proxy: proxy, geometry: geometry) else { return }
                                dragRange = AgeRange(from: from, to: to)
                            }
                            .onEnded { value in
                                defer { dragRange = nil }
                                if abs(value.translation.width) > 8, let range = dragRange {
                                    zoom = AgeChart.clampRange(range, min: domain.minAge, max: domain.maxAge) ?? zoom
                                } else {
                                    select(at: value.location, proxy: proxy, geometry: geometry)
                                }
                            }
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.label) by age")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(series.filter { !$0.faint || series.count > 1 }) { line in
                HStack(spacing: 4) {
                    Circle()
                        .fill(line.color.opacity(line.faint ? 0.35 : 1))
                        .frame(width: 8, height: 8)
                    Text(line.label)
                        .font(.caption)
                }
            }
        }
    }

    private func plotPoint(_ location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> CGPoint? {
        guard let anchor = proxy.plotFrame else { return nil }
        let frame = geometry[anchor]
        return CGPoint(x: location.x - frame.origin.x, y: location.y - frame.origin.y)
    }

    private func age(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Double? {
        guard let point = plotPoint(location, proxy: proxy, geometry: geometry) else { return nil }
        return proxy.value(atX: point.x, as: Double.self)
    }

    /// The nearest point to a tap, within a thumb's reach.
    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let tap = plotPoint(location, proxy: proxy, geometry: geometry) else { return }
        var best: (id: UUID, distance: CGFloat)?
        for line in series {
            for point in line.points {
                guard let position = proxy.position(for: (x: point.ageMonths, y: point.value)) else { continue }
                let distance = hypot(position.x - tap.x, position.y - tap.y)
                if distance < 28, distance < (best?.distance ?? .infinity) {
                    best = (point.id, distance)
                }
            }
        }
        if let best { onSelect(best.id) }
    }
}
