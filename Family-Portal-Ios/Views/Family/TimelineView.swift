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

    /// A photo can be tagged with several people, so person filtering matches
    /// any of them; `person` is only what the row shows.
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
    @State private var cachedPeople: [Person] = []

    private var timelineItems: [TimelineItem] {
        let milestoneItems = milestones.map { TimelineItem.milestone($0) }
        let growthItems = growthData.map { TimelineItem.growthData($0) }
        let photoItems = photos.map { TimelineItem.photo($0) }
        return (milestoneItems + growthItems + photoItems).sorted { $0.date > $1.date }
    }

    private var availableYears: [Int] {
        let years = Set(timelineItems.map { Calendar.current.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    private var filteredTimelineItems: [TimelineItem] {
        timelineItems.filter { item in
            if let selectedPersonId, !item.people.contains(where: { $0.id == selectedPersonId }) {
                return false
            }

            switch selectedItemType {
            case .all:
                break
            case .milestones:
                guard case .milestone = item else { return false }
            case .measurements:
                guard case .growthData = item else { return false }
            case .photos:
                guard case .photo = item else { return false }
            }

            if let selectedYear {
                let year = Calendar.current.component(.year, from: item.date)
                if year != selectedYear {
                    return false
                }
            }

            switch item {
            case .milestone(let milestone):
                if let selectedMilestoneCategory, milestone.category != selectedMilestoneCategory {
                    return false
                }
            case .growthData(let data):
                if let selectedMeasurementType, data.measurementType != selectedMeasurementType {
                    return false
                }
            case .photo:
                break
            }

            return matchesSearch(item)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if timelineItems.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "clock",
                        description: Text("Milestones and measurements will appear here")
                    )
                } else {
                    VStack(spacing: 0) {
                        filterChips
                        if filteredTimelineItems.isEmpty {
                            ContentUnavailableView(
                                "No matching activity",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Try adjusting your filters.")
                            )
                        } else {
                            List(filteredTimelineItems) { item in
                                TimelineRowView(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Timeline")
            .refreshable {
                await syncService.performFullSync()
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search timeline")
        .onAppear {
            cachedPeople = people
        }
        .onChange(of: people) { _, newValue in
            if !newValue.isEmpty || cachedPeople.isEmpty {
                cachedPeople = newValue
            }
        }
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

    private func matchesSearch(_ item: TimelineItem) -> Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return true }
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
        return haystacks.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
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

private enum TimelineFilterType: CaseIterable {
    case all
    case milestones
    case measurements
    case photos

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
            // Photos are uploaded with no title from the gallery today, so fall
            // back to something better than an empty row.
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
