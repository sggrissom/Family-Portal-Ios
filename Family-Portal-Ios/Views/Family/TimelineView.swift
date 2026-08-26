import SwiftUI
import SwiftData

enum TimelineItem: Identifiable {
    case milestone(Milestone)
    case growthData(GrowthData)
    case photo(Photo)

    var id: UUID {
        switch self {
        case .milestone(let milestone):
            return milestone.id
        case .growthData(let data):
            return data.id
        case .photo(let photo):
            return photo.id
        }
    }

    var date: Date {
        switch self {
        case .milestone(let milestone):
            return milestone.date
        case .growthData(let data):
            return data.date
        case .photo(let photo):
            return photo.photoDate
        }
    }

    var people: [Person] {
        switch self {
        case .milestone(let milestone):
            return [milestone.person].compactMap { $0 }
        case .growthData(let data):
            return [data.person].compactMap { $0 }
        case .photo(let photo):
            return photo.taggedPeople
        }
    }

    var person: Person? {
        people.first
    }
}

struct TimelineView: View {
    @Query(sort: \GrowthData.date, order: .reverse) private var growthData: [GrowthData]
    @Query(sort: \Milestone.date, order: .reverse) private var milestones: [Milestone]
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]
    @Query private var people: [Person]
    @Environment(SyncService.self) private var syncService

    @State private var selectedPersonId: UUID? = nil
    @State private var selectedItemType: TimelineFilterType = .all
    @State private var selectedMilestoneCategory: MilestoneCategory? = nil
    @State private var selectedMeasurementType: MeasurementType? = nil
    @State private var selectedYear: Int? = nil
    @State private var searchText = ""

    @State private var debouncedSearchText = ""

    @State private var cachedPeople: [Person] = []

    @State private var availableYears: [Int] = []

    private var hasAnyActivity: Bool {
        !milestones.isEmpty || !growthData.isEmpty || !photos.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasAnyActivity {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "clock",
                        description: Text("Milestones and measurements will appear here")
                    )
                } else {
                    VStack(spacing: 0) {
                        filterChips
                        TimelineResultsView(
                            personId: selectedPersonId,
                            itemType: selectedItemType,
                            year: selectedYear,
                            category: selectedMilestoneCategory,
                            measurementType: selectedMeasurementType,
                            searchText: debouncedSearchText
                        )
                    }
                }
            }
            .navigationTitle("Timeline")
            .refreshable {
                await syncService.performFullSync()
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search timeline")
        // `task(id:)` cancels the pending run on the next keystroke, which is the whole debounce. Clearing is immediate.
        .task(id: searchText) {
            if searchText.isEmpty {
                debouncedSearchText = ""
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            debouncedSearchText = searchText
        }
        .onAppear {
            cachedPeople = people
            recomputeAvailableYears()
        }
        .onChange(of: people) { _, newValue in
            if !newValue.isEmpty || cachedPeople.isEmpty {
                cachedPeople = newValue
            }
        }
        .onChange(of: milestones) { _, _ in recomputeAvailableYears() }
        .onChange(of: growthData) { _, _ in recomputeAvailableYears() }
        .onChange(of: photos) { _, _ in recomputeAvailableYears() }
        .onChange(of: selectedItemType) { _, newValue in
            switch newValue {
            case .all:
                selectedMilestoneCategory = nil
                selectedMeasurementType = nil
            case .milestones:
                selectedMeasurementType = nil
            case .measurements:
                selectedMilestoneCategory = nil
            case .photos:
                selectedMilestoneCategory = nil
                selectedMeasurementType = nil
            }
        }
    }

    private func recomputeAvailableYears() {
        let calendar = Calendar.current
        var years: Set<Int> = []
        for milestone in milestones { years.insert(calendar.component(.year, from: milestone.date)) }
        for data in growthData { years.insert(calendar.component(.year, from: data.date)) }
        for photo in photos { years.insert(calendar.component(.year, from: photo.photoDate)) }
        availableYears = years.sorted(by: >)
    }

    @ViewBuilder
    private var filterChips: some View {
        VStack(spacing: 0) {
            filterSection {
                filterChip(label: "All People", isSelected: selectedPersonId == nil) {
                    selectedPersonId = nil
                }
                ForEach(cachedPeople, id: \.id) { person in
                    filterChip(label: person.name, isSelected: selectedPersonId == person.id) {
                        selectedPersonId = person.id
                    }
                }
            }

            filterSection {
                ForEach(TimelineFilterType.allCases, id: \.self) { itemType in
                    filterChip(label: itemType.label, isSelected: selectedItemType == itemType) {
                        selectedItemType = itemType
                    }
                }
            }

            if selectedItemType == .milestones {
                filterSection {
                    filterChip(label: "All Categories", isSelected: selectedMilestoneCategory == nil) {
                        selectedMilestoneCategory = nil
                    }
                    ForEach(MilestoneCategory.allCases, id: \.self) { category in
                        filterChip(label: category.rawValue.capitalized, isSelected: selectedMilestoneCategory == category) {
                            selectedMilestoneCategory = category
                        }
                    }
                }
            }

            if selectedItemType == .measurements {
                filterSection {
                    filterChip(label: "All Measurements", isSelected: selectedMeasurementType == nil) {
                        selectedMeasurementType = nil
                    }
                    ForEach(MeasurementType.allCases, id: \.self) { measurement in
                        filterChip(label: measurement.rawValue.capitalized, isSelected: selectedMeasurementType == measurement) {
                            selectedMeasurementType = measurement
                        }
                    }
                }
            }

            if !availableYears.isEmpty {
                filterSection {
                    filterChip(label: "All Years", isSelected: selectedYear == nil) {
                        selectedYear = nil
                    }
                    ForEach(availableYears, id: \.self) { year in
                        filterChip(label: String(year), isSelected: selectedYear == year) {
                            selectedYear = year
                        }
                    }
                }
            }
        }
    }

    private func filterSection(@ViewBuilder content: () -> some View) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// The list itself, fetched already narrowed. Its own view because that is the only way `@Query` takes a predicate depending on state: the descriptors are built in `init`.
private struct TimelineResultsView: View {
    @Query private var milestones: [Milestone]
    @Query private var growthData: [GrowthData]
    @Query private var photos: [Photo]

    private let category: MilestoneCategory?
    private let measurementType: MeasurementType?
    private let searchText: String

    init(
        personId: UUID?,
        itemType: TimelineFilterType,
        year: Int?,
        category: MilestoneCategory?,
        measurementType: MeasurementType?,
        searchText: String
    ) {
        self.category = category
        self.measurementType = measurementType
        self.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Half-open, so a record at midnight on 1 January belongs to exactly one year — the same answer that built the chip the user tapped.
        let bounds = TimelineYear.bounds(year)
        let start = bounds.start
        let end = bounds.end

        // Each branch is built outside the macro so every predicate body holds nothing but concrete comparisons.
        let milestonePredicate: Predicate<Milestone>
        if !itemType.includes(.milestones) {
            milestonePredicate = #Predicate<Milestone> { _ in false }
        } else if let personId {
            milestonePredicate = #Predicate<Milestone> { $0.person?.id == personId && $0.date >= start && $0.date < end }
        } else {
            milestonePredicate = #Predicate<Milestone> { $0.date >= start && $0.date < end }
        }

        let growthPredicate: Predicate<GrowthData>
        if !itemType.includes(.measurements) {
            growthPredicate = #Predicate<GrowthData> { _ in false }
        } else if let personId {
            growthPredicate = #Predicate<GrowthData> { $0.person?.id == personId && $0.date >= start && $0.date < end }
        } else {
            growthPredicate = #Predicate<GrowthData> { $0.date >= start && $0.date < end }
        }

        let photoPredicate: Predicate<Photo>
        if !itemType.includes(.photos) {
            photoPredicate = #Predicate<Photo> { _ in false }
        } else if let personId {
            photoPredicate = #Predicate<Photo> { photo in
                photo.taggedPeople.contains { $0.id == personId }
                    && photo.photoDate >= start && photo.photoDate < end
            }
        } else {
            photoPredicate = #Predicate<Photo> { $0.photoDate >= start && $0.photoDate < end }
        }

        _milestones = Query(filter: milestonePredicate, sort: \Milestone.date, order: .reverse)
        _growthData = Query(filter: growthPredicate, sort: \GrowthData.date, order: .reverse)
        _photos = Query(filter: photoPredicate, sort: \Photo.photoDate, order: .reverse)
    }

    private var items: [TimelineItem] {
        let merged = milestones.map(TimelineItem.milestone)
            + growthData.map(TimelineItem.growthData)
            + photos.map(TimelineItem.photo)

        return merged
            .filter { item in
                switch item {
                case .milestone(let milestone):
                    if let category, milestone.category != category { return false }
                case .growthData(let data):
                    if let measurementType, data.measurementType != measurementType { return false }
                case .photo:
                    break
                }
                return matchesSearch(item)
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let visibleItems = items
        if visibleItems.isEmpty {
            ContentUnavailableView(
                "No matching activity",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try adjusting your filters.")
            )
        } else {
            List(visibleItems) { item in
                TimelineRowView(item: item)
            }
        }
    }

    private func matchesSearch(_ item: TimelineItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        var haystacks: [String] = item.people.map(\.name)
        switch item {
        case .milestone(let milestone):
            haystacks.append(milestone.descriptionText)
            haystacks.append(milestone.category.rawValue)
        case .growthData(let data):
            haystacks.append(data.measurementType.rawValue)
            haystacks.append(data.unit.rawValue)
            haystacks.append(String(format: "%.1f", data.value))
        case .photo(let photo):
            haystacks.append(photo.title)
            haystacks.append(photo.descriptionText)
        }
        return haystacks.contains { $0.localizedCaseInsensitiveContains(searchText) }
    }
}

enum TimelineYear {
    static func bounds(_ year: Int?, calendar: Calendar = .current) -> (start: Date, end: Date) {
        guard let year else { return (.distantPast, .distantFuture) }
        guard let start = calendar.date(from: DateComponents(year: year)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else {
            return (.distantPast, .distantFuture)
        }
        return (start, end)
    }
}

enum TimelineFilterType: CaseIterable {
    case all
    case milestones
    case measurements
    case photos

    func includes(_ other: TimelineFilterType) -> Bool {
        self == .all || self == other
    }

    var label: String {
        switch self {
        case .all:
            return "All Activity"
        case .milestones:
            return "Milestones"
        case .measurements:
            return "Measurements"
        case .photos:
            return "Photos"
        }
    }
}

struct TimelineRowView: View {
    let item: TimelineItem

    private var categoryIcon: String {
        switch item {
        case .milestone(let milestone):
            switch milestone.category {
            case .development: return "leaf.fill"
            case .behavior: return "face.smiling.fill"
            case .health: return "heart.fill"
            case .achievement: return "trophy.fill"
            case .first: return "star.fill"
            case .other: return "note.text"
            }
        case .growthData(let data):
            switch data.measurementType {
            case .height: return "ruler"
            case .weight: return "scalemass"
            }
        case .photo:
            return "photo"
        }
    }

    private var itemColor: Color {
        switch item {
        case .milestone(let milestone):
            switch milestone.category {
            case .development: return .green
            case .behavior: return .orange
            case .health: return .red
            case .achievement: return .yellow
            case .first: return .purple
            case .other: return .gray
            }
        case .growthData(let data):
            switch data.measurementType {
            case .height: return .blue
            case .weight: return .teal
            }
        case .photo:
            return .indigo
        }
    }

    private var descriptionText: String {
        switch item {
        case .milestone(let milestone):
            return milestone.descriptionText
        case .growthData(let data):
            let formatted = data.value.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", data.value)
                : String(format: "%.1f", data.value)
            return "\(data.measurementType.rawValue.capitalized): \(formatted) \(data.unit.rawValue)"
        case .photo(let photo):
            let title = photo.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
            let description = photo.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            return description.isEmpty ? "Photo" : description
        }
    }

    private var badgeText: String {
        switch item {
        case .milestone(let milestone):
            return milestone.category.rawValue.capitalized
        case .growthData(let data):
            return data.measurementType.rawValue.capitalized
        case .photo:
            return "Photo"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let person = item.person {
                PersonAvatarView(person: person, size: 44)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(badgeText, systemImage: categoryIcon)
                        .font(.caption)
                        .foregroundStyle(itemColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(itemColor.opacity(0.15), in: Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)

                    if let person = item.person {
                        Text(person.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Text(descriptionText)
                    .font(.body)
                    .lineLimit(2)
            }

            Spacer()

            if case .photo(let photo) = item {
                PhotoThumbnailView(imageData: photo.imageData, title: "", remoteId: photo.remoteId)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(descriptionText)
            }

            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TimelineView()
        .modelContainer(for: [Person.self, GrowthData.self, Milestone.self, Photo.self, FamilyTag.self], inMemory: true)
        .environment(SyncService(
            modelContext: ModelContext(try! ModelContainer(for: Person.self, GrowthData.self, Milestone.self, Photo.self, FamilyTag.self)),
            apiClient: APIClient(),
            networkMonitor: NetworkMonitor()
        ))
}
