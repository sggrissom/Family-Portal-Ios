import SwiftUI
import SwiftData

struct FamilyMembersView: View {
    @Query(sort: \Person.name) private var people: [Person]

    private var parents: [Person] {
        people.filter { $0.type == .parent }
    }

    private var children: [Person] {
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
                        if !parents.isEmpty {
                            Section("Parents") {
                                ForEach(parents, id: \.id) { person in
                                    NavigationLink(value: person.id) {
                                        PersonRowView(
                                            name: person.name,
                                            type: person.type,
                                            birthday: person.birthday,
                                            profilePhotoRemoteId: person.profilePhotoId
                                        )
                                    }
                                }
                            }
                        }

                        if !children.isEmpty {
                            Section("Children") {
                                ForEach(children, id: \.id) { person in
                                    NavigationLink(value: person.id) {
                                        PersonRowView(
                                            name: person.name,
                                            type: person.type,
                                            birthday: person.birthday,
                                            profilePhotoRemoteId: person.profilePhotoId
                                        )
                                    }
                                }
                            }
                        }
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
