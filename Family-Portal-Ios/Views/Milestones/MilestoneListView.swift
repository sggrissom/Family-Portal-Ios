import SwiftUI
import SwiftData

struct MilestoneListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService: SyncService?

    @Query private var people: [Person]
    private var person: Person? { people.first }

    @State private var selectedCategory: MilestoneCategory?
    @State private var showingAddMilestone = false

    private let personId: UUID

    private var filteredMilestones: [Milestone] {
        guard let person else { return [] }
        let milestones: [Milestone]
        if let selectedCategory {
            milestones = person.milestones.filter { $0.category == selectedCategory }
        } else {
            milestones = person.milestones
        }
        return milestones.sorted { $0.date > $1.date }
    }

    init(personId: UUID) {
        self.personId = personId
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(label: "All", category: nil)
                    ForEach(MilestoneCategory.allCases, id: \.self) { category in
                        categoryChip(label: category.rawValue.capitalized, category: category)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }

            if filteredMilestones.isEmpty {
                ContentUnavailableView(
                    "No Milestones",
                    systemImage: "star",
                    description: Text("Tap + to record a milestone.")
                )
            } else {
                List {
                    ForEach(filteredMilestones, id: \.id) { milestone in
                        MilestoneRowView(milestone: milestone)
                    }
                    .onDelete(perform: deleteMilestones)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Milestones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddMilestone = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMilestone) {
            AddMilestoneView(personId: personId)
        }
    }

    private func categoryChip(label: String, category: MilestoneCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
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

    private func deleteMilestones(at offsets: IndexSet) {
        for index in offsets {
            let milestone = filteredMilestones[index]
            Task {
                do {
                    try await syncService?.deleteMilestone(milestone)
                } catch {
                    print("Failed to sync delete milestone: \(error)")
                }
            }
        }
    }
}
