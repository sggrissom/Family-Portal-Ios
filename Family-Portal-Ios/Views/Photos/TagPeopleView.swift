import SwiftUI
import SwiftData

struct TagPeopleView: View {
    @Bindable var photo: Photo
    @Query(sort: \Person.name) private var people: [Person]
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    var body: some View {
        List(people) { person in
            HStack(spacing: 12) {
                PersonAvatarView(person: person, size: 36)
                Text(person.name)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { photo.taggedPeople.contains(where: { $0.id == person.id }) },
                    set: { isTagged in
                        // The toggle is applied locally first and the queue delivers it, so an error here means nothing was queued at all — undoing keeps the switch honest.
                        if isTagged {
                            photo.taggedPeople.append(person)
                            Task {
                                do {
                                    try await syncService?.addPeopleToPhoto(photo, people: [person])
                                } catch {
                                    photo.taggedPeople.removeAll(where: { $0.id == person.id })
                                    errorPresenter?.report(error, title: "Couldn't Tag \(person.name)")
                                }
                            }
                        } else {
                            photo.taggedPeople.removeAll(where: { $0.id == person.id })
                            Task {
                                do {
                                    try await syncService?.removePersonFromPhoto(photo, person: person)
                                } catch {
                                    photo.taggedPeople.append(person)
                                    errorPresenter?.report(error, title: "Couldn't Untag \(person.name)")
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
