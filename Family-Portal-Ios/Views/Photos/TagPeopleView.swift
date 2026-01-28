import SwiftUI
import SwiftData

struct TagPeopleView: View {
    @Bindable var photo: Photo
    @Query(sort: \Person.name) private var people: [Person]
    @Environment(SyncService.self) private var syncService: SyncService?

    var body: some View {
        List(people) { person in
            HStack(spacing: 12) {
                PersonAvatarView(
                    name: person.name,
                    type: person.type,
                    profilePhotoRemoteId: person.profilePhotoId,
                    size: 36
                )
                Text(person.name)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { photo.taggedPeople.contains(where: { $0.id == person.id }) },
                    set: { isTagged in
                        if isTagged {
                            photo.taggedPeople.append(person)
                            Task {
                                do {
                                    try await syncService?.addPeopleToPhoto(photo, people: [person])
                                } catch {
                                    print("Failed to sync add person to photo: \(error)")
                                }
                            }
                        } else {
                            photo.taggedPeople.removeAll(where: { $0.id == person.id })
                            Task {
                                do {
                                    try await syncService?.removePersonFromPhoto(photo, person: person)
                                } catch {
                                    print("Failed to sync remove person from photo: \(error)")
                                }
                            }
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
