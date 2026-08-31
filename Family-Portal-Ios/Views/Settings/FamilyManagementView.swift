import SwiftUI
import SwiftData

struct FamilyManagementView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @State private var showingAddPerson = false
    @State private var rowQuickAdd: PersonQuickAdd?

    var body: some View {
        List {
            if people.isEmpty {
                ContentUnavailableView(
                    "No Family Members",
                    systemImage: "person.3",
                    description: Text("Tap Add Member to start setting up your family.")
                )
            } else {
                FamilyRosterSections(people: people) { rowQuickAdd = $0 }
            }
        }
        .navigationTitle("Family Management")
        .navigationDestination(for: UUID.self) { personId in
            PersonDetailView(personId: personId)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddPerson = true
                } label: {
                    Label("Add Member", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonView()
        }
        .sheet(item: $rowQuickAdd) { PersonQuickAddSheet(request: $0) }
    }
}
