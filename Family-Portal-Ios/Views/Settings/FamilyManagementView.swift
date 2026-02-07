import SwiftUI
import SwiftData

struct FamilyManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.name) private var people: [Person]
    @State private var showingAddPerson = false

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
        List {
            if people.isEmpty {
                ContentUnavailableView(
                    "No Family Members",
                    systemImage: "person.3",
                    description: Text("Tap Add Member to start setting up your family.")
                )
            } else {
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
                        .onDelete { offsets in
                            deletePeople(offsets, from: parents)
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
                        .onDelete { offsets in
                            deletePeople(offsets, from: children)
                        }
                    }
                }
            }
        }
        .navigationTitle("Family Management")
        .navigationDestination(for: UUID.self) { personId in
            PersonDetailView(personId: personId)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddPerson = true
                } label: {
                    Label("Add Member", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonView()
        }
    }

    private func deletePeople(_ offsets: IndexSet, from source: [Person]) {
        for index in offsets {
            modelContext.delete(source[index])
        }
    }
}
