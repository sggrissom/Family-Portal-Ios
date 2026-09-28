import SwiftUI
import SwiftData

/// The Home tab. Until the dashboard lands (phase 5) it is the roster under a new name — the family strip replaces it then. `FamilyManagementView` in Settings stays the full directory.
struct HomeView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @Environment(AddFlow.self) private var addFlow

    var body: some View {
        List {
            if people.isEmpty {
                ContentUnavailableView(
                    "No Family Members",
                    systemImage: "person.3",
                    description: Text("Add someone to start recording.")
                )
            } else {
                FamilyRosterSections(people: people)
            }

            Section {
                Button {
                    addFlow.open(.person)
                } label: {
                    Label(Copy.home.addPerson, systemImage: "person.badge.plus")
                }
            }
        }
        .navigationTitle(Copy.nav.home)
    }
}
