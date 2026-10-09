import SwiftUI
import SwiftData

/// History: every day the family recorded something, newest first, under pinned month headers — the web's History page, built from the store.
/// Filters live on `AppNavigator`, above the stack, so opening a record and coming back keeps both them and the scroll position.
struct HistoryView: View {
    @Query private var people: [Person]
    @Query(sort: \Milestone.date, order: .reverse) private var milestones: [Milestone]
    @Query(sort: \GrowthData.date, order: .reverse) private var growth: [GrowthData]
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]
    @Query private var tags: [FamilyTag]

    @Environment(AppNavigator.self) private var navigator
    @Environment(ActivityService.self) private var activityService

    @State private var activities = ActivityScreenState<GetFamilyTimelineResponseDTO>()
    @State private var openMeasurement: GrowthData?

    private var filters: HistoryFilters { navigator.historyFilters }

    private var filtersBinding: Binding<HistoryFilters> {
        Binding(get: { navigator.historyFilters }, set: { navigator.historyFilters = $0 })
    }

    private var today: String { WhenEntry.localDateString(Date()) }

    var body: some View {
        let content = History.view(
            people: people,
            milestones: milestones,
            growth: growth,
            photos: photos,
            appearances: activities.value?.appearances ?? [],
            filters: filters,
            today: today
        )
        let days = DaySummaries.summarize(content.records, people: content.birthdayPeople, range: content.range)
        let months = DaySummaries.groupByMonth(days)
        let years = History.years(milestones: milestones, growth: growth, photos: photos)

        ScrollViewReader { proxy in
            ScrollView {
                filterRow
                    .padding(.horizontal)

                if !filters.trimmedSearch.isEmpty {
                    Text(Copy.history.resultsFor(filters.trimmedSearch, content.records.milestones.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }

                if months.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        ForEach(months) { month in
                            Section {
                                ForEach(month.days) { day in
                                    DaySummaryView(day: day, today: today, people: peopleById) { openMeasurement = $0 }
                                        .padding(.horizontal)
                                }
                            } header: {
                                Text(month.label)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .background(.bar)
                                    .id(month.month)
                            }
                        }
                    }
                }
            }
            .toolbar {
                if years.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu(Copy.history.years) {
                            ForEach(years, id: \.self) { year in
                                Button(String(year)) {
                                    if let target = months.first(where: { $0.month.hasPrefix("\(year)-") }) {
                                        withAnimation { proxy.scrollTo(target.month, anchor: .top) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Copy.nav.history)
        .searchable(text: filtersBinding.search, prompt: Copy.history.searchPlaceholder)
        .refreshable { await activities.reload() }
        .task {
            await activities.load(activityService.timelineAppearances())
        }
        .sheet(item: $openMeasurement) { MeasurementDetailSheetView(measurement: $0) }
    }

    private var peopleById: [UUID: Person] {
        Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Person chips, then **More** (Show and Tags), then **Clear** — one row.
    private var filterRow: some View {
        HStack(spacing: 8) {
            PersonChips(selection: filtersBinding.personIds)

            Menu {
                Section(Copy.history.show) {
                    ForEach(HistoryType.allCases) { type in
                        Toggle(type.label, isOn: Binding(
                            get: { filters.types.contains(type) },
                            set: { on in
                                if on { navigator.historyFilters.types.insert(type) } else { navigator.historyFilters.types.remove(type) }
                            }
                        ))
                    }
                }
                if !tags.isEmpty {
                    Section(Copy.history.tags) {
                        ForEach(tags.sorted { $0.name.lowercased() < $1.name.lowercased() }) { tag in
                            if let remoteId = tag.remoteId.flatMap(Int.init) {
                                Toggle(tag.name, isOn: Binding(
                                    get: { filters.tagIds.contains(remoteId) },
                                    set: { on in
                                        if on { navigator.historyFilters.tagIds.insert(remoteId) } else { navigator.historyFilters.tagIds.remove(remoteId) }
                                    }
                                ))
                            }
                        }
                    }
                }
            } label: {
                Label(Copy.history.more, systemImage: "line.3.horizontal.decrease.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
            }
            .fixedSize()

            if filters.isActive {
                Button(Copy.history.clear) {
                    navigator.historyFilters = HistoryFilters()
                }
                .font(.subheadline)
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        if filters.isActive {
            ContentUnavailableView {
                Label(Copy.history.noMatches, systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button(Copy.history.clear) { navigator.historyFilters = HistoryFilters() }
            }
        } else {
            ContentUnavailableView(Copy.history.empty, systemImage: "clock")
        }
    }
}
