import SwiftUI
import SwiftData

struct FamilyMembersView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @State private var path = NavigationPath()

    /// A person's season, reached by the server id a link carries.
    /// `PersonSeasonView` is addressed by server id and wants a name to title
    /// itself with, so the route carries both rather than making the destination
    /// look the person up again.
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
        // `.task` covers the cold launch, where this view does not exist yet
        // when the link arrives; `.onChange` covers a link followed while the
        // app is already open.
        .task { openPendingLink() }
        .onChange(of: deepLinkRouter.pending) { _, _ in openPendingLink() }
        // A link can name someone this device has not pulled yet. The pull that
        // follows a cold launch is what makes them resolvable, so the attempt is
        // repeated when the roster changes rather than abandoned.
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

        // Links carry server ids; the local store is keyed by UUID. An id this
        // device has never seen is left pending rather than dropped — the sync
        // that follows a cold launch usually arrives moments later, and
        // `onChange(of: people.count)` brings us back here when it does.
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
            // Pushed on top of the person, not instead of them: backing out of a
            // season should land on the person it belongs to, which is where
            // the same screen is reached from by hand.
            path.append(PersonSeasonRoute(personRemoteId: remoteId, personName: person.name))
        default:
            break
        }
    }
}
