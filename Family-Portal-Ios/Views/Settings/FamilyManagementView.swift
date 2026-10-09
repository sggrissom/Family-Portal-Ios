import SwiftUI
import SwiftData

struct FamilyManagementView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @Environment(AuthService.self) private var authService
    @State private var showingAddPerson = false

    private var canAdd: Bool { authService.access.canContributeAnywhere }

    var body: some View {
        List {
            if people.isEmpty {
                ContentUnavailableView(
                    "No Family Members",
                    systemImage: "person.3",
                    description: Text(canAdd ? "Tap Add Member to start setting up your family." : "")
                )
            } else {
                FamilyRosterSections(people: people, manages: true)
            }
        }
        .navigationTitle("Family Management")
        .toolbar {
            if canAdd {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddPerson = true
                    } label: {
                        Label("Add Member", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonView()
        }
    }
}
