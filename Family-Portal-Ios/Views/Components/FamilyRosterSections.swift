import SwiftUI

/// Parents, then children youngest-first, each linking to the person.
///
/// `FamilyMembersView` and `FamilyManagementView` each carried their own copy of
/// this — the same partition, the same four-case birthday comparison, the same
/// two sections. Two copies of an ordering rule is one copy too many: the two
/// screens show the same roster, and a household that reads one way on the
/// Family tab and another way in Settings is a bug nobody would think to look
/// for.
///
/// The views still differ in what they are for — one is read-only, one manages
/// membership — so what is shared is the list, not the screen.
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
    /// The household's adults, in whatever order they arrived — the callers
    /// query sorted by name.
    static func parents(in people: [Person]) -> [Person] {
        people.filter { $0.type == .parent }
    }

    /// The household's children, oldest first.
    ///
    /// A birthday is optional: a person can be added before anyone knows or
    /// bothers to enter one. Someone with a birthday sorts ahead of someone
    /// without, so the unknowns collect at the end rather than at the top, and
    /// two unknowns fall back to name so the order is at least stable.
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
