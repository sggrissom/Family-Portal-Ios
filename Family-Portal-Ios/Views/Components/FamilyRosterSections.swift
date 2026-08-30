import SwiftUI
import SwiftData

/// The household banded by generation, each row linking to the person. Shared by `FamilyMembersView` and `FamilyManagementView` so the two cannot order a household differently.
/// Bands come from the stated edges, not from any field on a person: the parent/child enum that used to split this list is gone, and a *relationship* is viewer-relative — the person who is a mother to one viewer is a daughter to another. A *generation* is not, which is why the graph can band the roster when a relationship word could not. Each row still carries its own relationship label.
struct FamilyRosterSections: View {
    let people: [Person]

    @Query private var relations: [PersonRelation]

    private var groups: [PersonGroup] {
        FamilyGroups.group(people: people, relations: relations.map(\.edge))
    }

    var body: some View {
        let groups = self.groups
        ForEach(groups) { group in
            // A single band is the whole household, so naming it after a generation would say less than nothing — a family that has stated no relationships at all would read "Not linked yet" across every row.
            Section(groups.count > 1 ? group.title : "Family") {
                ForEach(group.people, id: \.id) { person in
                    NavigationLink(value: person.id) {
                        PersonRowView(person: person)
                    }
                }
            }
        }
    }
}
