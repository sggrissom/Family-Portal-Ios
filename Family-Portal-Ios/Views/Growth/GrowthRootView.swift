import SwiftUI
import SwiftData

/// Which reference population the Growth page draws behind the lines.
enum PercentileBands: String, CaseIterable, Identifiable {
    case off, girls, boys

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return Copy.growthPage.bandsOff
        case .girls: return Copy.growthPage.girls
        case .boys: return Copy.growthPage.boys
        }
    }

    var gender: Gender? {
        switch self {
        case .off: return nil
        case .girls: return .female
        case .boys: return .male
        }
    }
}

/// The family's Growth page: one line per chosen person, aligned by age, over optional percentile bands. Tap a point to open it; drag to zoom.
/// Built from the store, so it draws offline.
struct GrowthRootView: View {
    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]
    @Environment(AuthService.self) private var authService
    @Environment(AddFlow.self) private var addFlow

    @State private var type: MeasurementType = .height
    @State private var selected: Set<UUID> = []
    @State private var bands: PercentileBands = .off
    @State private var zoom: AgeRange?
    @State private var openMeasurement: GrowthData?
    @State private var didSeed = false

    private var ordered: [Person] {
        FamilyGroups.chipOrder(people: people, relations: relations.map(\.edge), ownFamilyId: authService.currentUser?.familyId)
            .filter { $0.birthday != nil }
    }

    var body: some View {
        let chosen = ordered.filter { selected.contains($0.id) }
        let series = chosen.enumerated().compactMap { index, person -> AgeSeries? in
            guard let birthday = person.birthday else { return nil }
            let points = AgeChart.chartPoints(person.growthData, birthday: birthday, type: type)
            guard !points.isEmpty else { return nil }
            return AgeSeries(
                id: person.id,
                label: person.name.firstName,
                color: AgeSeries.palette[index % AgeSeries.palette.count],
                points: points
            )
        }
        let maxAge = series.flatMap(\.points).map(\.ageMonths).max() ?? 0
        let band = bands.gender.map { AgeChart.percentileBand(gender: $0, type: type, from: 0, to: maxAge + 1) } ?? []

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker(Copy.growthPage.metric, selection: $type) {
                    ForEach(MeasurementType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    Text(Copy.growthPage.people)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PersonChips(selection: $selected, only: Set(ordered.map(\.id)))
                }

                HStack {
                    Text(Copy.growthPage.bands)
                        .font(.subheadline)
                    Spacer()
                    Picker(Copy.growthPage.bands, selection: $bands) {
                        ForEach(PercentileBands.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if series.isEmpty {
                    Text(people.contains { !$0.growthData.isEmpty } ? Copy.growthPage.empty : Copy.growthPage.noData)
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                } else {
                    AgeChartView(series: series, band: band, type: type, zoom: $zoom) { id in
                        openMeasurement = chosen.flatMap(\.growthData).first { $0.id == id }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(Copy.growthPage.title)
        .toolbar {
            if authService.access.canContributeAnywhere {
                ToolbarItem(placement: .topBarLeading) {
                    Button(Copy.growthPage.measure) {
                        addFlow.open(.measurement(personId: selected.count == 1 ? selected.first : nil))
                    }
                }
            }
        }
        .onChange(of: type) { _, _ in zoom = nil }
        .onChange(of: selected) { _, _ in zoom = nil }
        .onAppear(perform: seed)
        .sheet(item: $openMeasurement) { MeasurementDetailSheetView(measurement: $0) }
    }

    /// The children by default: the youngest generation, or — in a household with no stated relationships — everyone under eighteen.
    private func seed() {
        guard !didSeed, !people.isEmpty else { return }
        didSeed = true
        let youngest = FamilyGroups.group(people: people, relations: relations.map(\.edge))
            .filter { $0.key.hasPrefix("generation-") }
            .last?.people ?? []
        let children = youngest.isEmpty
            ? people.filter { person in
                guard let birthday = person.birthday, !person.isPregnancy else { return false }
                return AgeSteps.monthsOld(birthday: birthday, at: Date()) < 18 * 12
            }
            : youngest
        selected = Set(children.filter { !$0.isPregnancy }.map(\.id))
    }
}
