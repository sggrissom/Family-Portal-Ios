import SwiftUI

/// Parents, then children youngest-first, each linking to the person. Shared by `FamilyMembersView` and `FamilyManagementView` so the two cannot order a household differently.
struct FamilyRosterSections: View {
    let people: [Person]

    var body: some View {
        if !Person.parents(in: people).isEmpty {
            Section("Parents") {
                ForEach(Person.parents(in: people), id: \.id) { person in
                    NavigationLink(value: person.id) {
                        PersonRowView(person: person)
                    }
                }
            }
        }

        if !Person.children(in: people).isEmpty {
            Section("Children") {
                ForEach(Person.children(in: people), id: \.id) { person in
                    NavigationLink(value: person.id) {
                        PersonRowView(person: person)
                    }
                }
            }
        }
    }
}

extension Person {
    static func parents(in people: [Person]) -> [Person] {
        people.filter { $0.type == .parent }
    }

    /// The household's children, oldest first. A person with no birthday sorts last, then by name so the order is stable.
    static func children(in people: [Person]) -> [Person] {
        people
            .filter { $0.type == .child }
            .sorted { left, right in
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
