import SwiftUI
import SwiftData

enum TimelineItem: Identifiable {
    case milestone(Milestone)
    case growthData(GrowthData)

    var id: UUID {
        switch self {
        case .milestone(let milestone):
            return milestone.id
        case .growthData(let data):
            return data.id
        }
    }

    var date: Date {
        switch self {
        case .milestone(let milestone):
            return milestone.date
        case .growthData(let data):
            return data.date
        }
    }

    var person: Person? {
        switch self {
        case .milestone(let milestone):
            return milestone.person
        case .growthData(let data):
            return data.person
        }
    }
}

struct TimelineView: View {
    @Query(sort: \GrowthData.date, order: .reverse) private var growthData: [GrowthData]
    @Query(sort: \Milestone.date, order: .reverse) private var milestones: [Milestone]
    @Environment(SyncService.self) private var syncService

    private var timelineItems: [TimelineItem] {
        let milestoneItems = milestones.map { TimelineItem.milestone($0) }
        let growthItems = growthData.map { TimelineItem.growthData($0) }
        return (milestoneItems + growthItems).sorted { $0.date > $1.date }
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
                    List(timelineItems) { item in
                        TimelineRowView(item: item)
                    }
                }
            }
            .navigationTitle("Timeline")
            .refreshable {
                await syncService.performFullSync()
            }
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
        }
    }

    private var badgeText: String {
        switch item {
        case .milestone(let milestone):
            return milestone.category.rawValue.capitalized
        case .growthData(let data):
            return data.measurementType.rawValue.capitalized
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let person = item.person {
                PersonAvatarView(name: person.name, type: person.type, size: 32)
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

                    if let person = item.person {
                        Text(person.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(descriptionText)
                    .font(.body)
                    .lineLimit(2)
            }

            Spacer()

            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TimelineView()
        .modelContainer(for: [Person.self, GrowthData.self, Milestone.self], inMemory: true)
        .environment(SyncService(
            modelContext: ModelContext(try! ModelContainer(for: Person.self, GrowthData.self, Milestone.self)),
            apiClient: APIClient(),
            networkMonitor: NetworkMonitor()
        ))
}
