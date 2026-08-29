import SwiftUI

/// The household as one list, oldest first, each row linking to the person. Shared by `FamilyMembersView` and `FamilyManagementView` so the two cannot order a household differently.
/// One list rather than the Parents/Children split it replaced, matching the web dashboard: the enum that split them is gone, and a relationship is viewer-relative — the person who is a mother to one viewer is a daughter to another, so there is no household-wide bucket to sort anyone into. Each row carries its own relationship instead.
struct FamilyRosterSections: View {
    let people: [Person]

    var body: some View {
        Section("Family") {
            ForEach(Person.roster(in: people), id: \.id) { person in
                NavigationLink(value: person.id) {
                    PersonRowView(person: person)
                }
            }
        }
    }
}

extension Person {
    /// The household, oldest first. A person with no birthday sorts last, then by name so the order is stable.
    static func roster(in people: [Person]) -> [Person] {
        people.sorted { left, right in
            switch (left.birthday, right.birthday) {
            case let (leftBirthday?, rightBirthday?):
                return leftBirthday < rightBirthday
            case (nil, nil):
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }
}
