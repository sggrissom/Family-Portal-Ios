import SwiftUI
import SwiftData

struct FamilyMembersView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @State private var path = NavigationPath()

    /// A person's season, reached by the server id a link carries. The route carries the name too, so the destination need not look the person up again.
    private struct PersonSeasonRoute: Hashable {
        let personRemoteId: Int
        let personName: String
    }

    var body: some View {
        NavigationStack(path: $path) {
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
            .navigationDestination(for: PersonSeasonRoute.self) { route in
                PersonSeasonView(personId: route.personRemoteId, personName: route.personName)
            }
        }
        .task { openPendingLink() }
        .onChange(of: deepLinkRouter.pending) { _, _ in openPendingLink() }
        .onChange(of: people.count) { _, _ in openPendingLink() }
    }

    private func openPendingLink() {
        guard let link = deepLinkRouter.pending else { return }

        let remoteId: Int
        switch link {
        case .person(let id), .personActivities(let id):
            remoteId = id
        default:
            return
        }

        // Links carry server ids; the local store is keyed by UUID. An id this device has never seen is left pending rather than dropped — the sync after a cold launch usually brings it moments later.
        guard let person = people.first(where: { $0.remoteId.flatMap(Int.init) == remoteId }) else {
            return
        }
        _ = deepLinkRouter.claim { $0 == link }

        switch link {
        case .person:
            path = NavigationPath([person.id])
        case .personActivities:
            path = NavigationPath()
            path.append(person.id)
            // Pushed on top of the person, not instead of them, so backing out of a season lands where the same screen is reached from by hand.
            path.append(PersonSeasonRoute(personRemoteId: remoteId, personName: person.name))
        default:
            break
        }
    }
}
