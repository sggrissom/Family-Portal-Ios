import SwiftUI
import SwiftData

struct FamilyMembersView: View {
    @Query(sort: \Person.name) private var people: [Person]

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No Family Members",
                        systemImage: "person.3",
                        description: Text("Manage family members from Settings.")
                    )
                } else {
                    List {
                        FamilyRosterSections(people: people)
                    }
                }
            }
            .navigationTitle("Family")
            .navigationDestination(for: UUID.self) { personId in
                PersonDetailView(personId: personId, allowsManagementActions: false)
            }
        }
    }
}
