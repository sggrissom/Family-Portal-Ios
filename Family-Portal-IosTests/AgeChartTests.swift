import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/ageChart.test.ts.
@MainActor
@Suite("Age chart")
struct AgeChartTests {

    @Test("One type is plotted by age, in inches, oldest first")
    func chartPoints() {
        let person = DaySummaryTests.person("Clara", born: "2023-05-02T00:00:00Z")
        let metric = GrowthData(measurementType: .height, value: 97.79, unit: .centimeters, date: DaySummaryTests.date("2026-09-02T00:00:00Z"))
        let early = GrowthData(measurementType: .height, value: 30, unit: .inches, date: DaySummaryTests.date("2024-05-02T00:00:00Z"))
        let weight = GrowthData(measurementType: .weight, value: 32, unit: .pounds, date: DaySummaryTests.date("2026-09-02T00:00:00Z"))

        let points = AgeChart.chartPoints([metric, early, weight], birthday: person.birthday!, type: .height)

        #expect(points.map(\.id) == [early.id, metric.id])
        #expect(points[0].ageMonths == 12)
        #expect(points[1].ageMonths == 40)
        #expect(abs(points[1].value - 38.5) < 0.05)
    }

    @Test("Metric converts to inches and pounds")
    func toDisplay() {
        #expect(abs(AgeChart.toDisplay(254, unit: .centimeters) - 100) < 0.001)
        #expect(abs(AgeChart.toDisplay(10, unit: .kilograms) - 22.05) < 0.01)
        #expect(AgeChart.toDisplay(40, unit: .inches) == 40)
    }

    @Test("The band covers the ages asked for, ordered by percentile")
    func band() {
        let band = AgeChart.percentileBand(gender: .female, type: .height, from: 0, to: 24)
        #expect(band.first?.ageMonths == 0)
        #expect(band.last?.ageMonths == 24)
        for row in band {
            #expect(row.p3 < row.p50)
            #expect(row.p50 < row.p97)
        }
        #expect(abs((band.first?.p50 ?? 0) - 19.3) < 0.5)
    }

    @Test("The band stops at twenty years")
    func bandStops() {
        #expect(AgeChart.percentileBand(gender: .male, type: .weight, from: 200, to: 400).last?.ageMonths == 240)
    }

    @Test("Ticks are round")
    func niceTicks() {
        #expect(AgeChart.niceTicks(min: 0, max: 50) == [0, 10, 20, 30, 40, 50])
        #expect(AgeChart.niceTicks(min: 30, max: 41) == [30, 32, 34, 36, 38, 40])
    }

    @Test("Ages read in months for babies and years after")
    func ageTicks() {
        #expect(AgeChart.ageTicks(minMonths: 0, maxMonths: 12).map(\.label) == ["0m", "3m", "6m", "9m", "12m"])
        #expect(AgeChart.ageTicks(minMonths: 0, maxMonths: 60).map(\.label) == ["0y", "1y", "2y", "3y", "4y", "5y"])
        #expect(AgeChart.ageTicks(minMonths: 30, maxMonths: 42).map(\.label) == ["2y 6m", "2y 9m", "3y", "3y 3m", "3y 6m"])
        #expect(AgeChart.ageTicks(minMonths: 12, maxMonths: 16).map(\.label) == ["12m", "13m", "14m", "15m", "16m"])
    }

    private static func points(_ pairs: [(Double, Double)]) -> [ChartPoint] {
        pairs.map { ChartPoint(id: UUID(), ageMonths: $0.0, value: $0.1) }
    }

    private let a = AgeChartTests.points([(0, 20), (12, 30), (24, 34), (60, 44)])
    private let b = AgeChartTests.points([(0, 19), (12, 29), (24, 33.5), (60, 43)])

    @Test("Unzoomed, every point fits")
    func fitsEverything() throws {
        let domain = try #require(AgeChart.chartDomain(series: [a, b], band: [], zoom: nil))
        #expect(domain.zoomed == false)
        #expect(domain.minAge == 0)
        #expect(domain.maxAge == 61)
        #expect(domain.minValue < 19)
        #expect(domain.maxValue > 44)
    }

    @Test("Zoomed, values refit to the ages, including where lines cross the edges")
    func refitsToZoom() throws {
        let domain = try #require(AgeChart.chartDomain(series: [a, b], band: [], zoom: AgeRange(from: 18, to: 30)))
        #expect(domain.zoomed)
        #expect(domain.minAge == 18)
        #expect(domain.maxAge == 30)
        #expect(domain.minValue > 30)
        #expect(domain.maxValue < 37)
    }

    @Test("Band rows just past each edge are kept, so the band reaches the axes")
    func bandReachesEdges() throws {
        let band = AgeChart.percentileBand(gender: .female, type: .height, from: 0, to: 60)
            .filter { Int($0.ageMonths) % 3 == 0 }
        let domain = try #require(AgeChart.chartDomain(series: [a], band: band, zoom: AgeRange(from: 19, to: 29)))
        #expect(domain.band.first?.ageMonths == 18)
        #expect(domain.band.last?.ageMonths == 30)
    }

    @Test("A range is ordered and clamped to the data")
    func clamps() {
        #expect(AgeChart.clampRange(AgeRange(from: 30, to: 12), min: 0, max: 20) == AgeRange(from: 12, to: 20))
        #expect(AgeChart.clampRange(AgeRange(from: 15, to: 5), min: 0, max: 20) == AgeRange(from: 5, to: 15))
    }

    @Test("A tiny selection widens to a month")
    func widens() throws {
        let range = try #require(AgeChart.clampRange(AgeRange(from: 10, to: 10.2), min: 0, max: 20))
        #expect(abs(range.from - 9.6) < 1e-9)
        #expect(abs(range.to - 10.6) < 1e-9)
    }

    @Test("A selection covering everything is no zoom")
    func coversEverything() {
        #expect(AgeChart.clampRange(AgeRange(from: 0, to: 20), min: 0, max: 20) == nil)
    }
}
