import SwiftUI
import SwiftData

struct TagPeopleView: View {
    @Bindable var photo: Photo
    @Query(sort: \Person.name) private var people: [Person]

    var body: some View {
        List(people) { person in
            HStack(spacing: 12) {
                PersonAvatarView(name: person.name, type: person.type, size: 36)
                Text(person.name)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { photo.taggedPeople.contains(where: { $0.id == person.id }) },
                    set: { isTagged in
                        if isTagged {
                            photo.taggedPeople.append(person)
                        } else {
                            photo.taggedPeople.removeAll(where: { $0.id == person.id })
                        }
                    }
                ))
                .labelsHidden()
            }
        }
        .navigationTitle("Tag People")
        .navigationBarTitleDisplayMode(.inline)
    }
}
