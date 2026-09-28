import SwiftUI
import SwiftData

/// A person's page: a header, then **Story · Photos · Growth · Activities**. Switching person keeps the tab, and the tab is part of the deep link (`/profile/<id>?tab=`).
struct PersonDetailView: View {
    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]

    @Environment(AddFlow.self) private var addFlow
    @Environment(AuthService.self) private var authService: AuthService?

    @State private var personId: UUID
    @State private var tab: PersonTab
    @State private var showEditSheet = false
    @State private var showProfilePhotoPicker = false
    let allowsManagementActions: Bool

    init(personId: UUID, tab: PersonTab = .story, allowsManagementActions: Bool = true) {
        _personId = State(initialValue: personId)
        _tab = State(initialValue: tab)
        self.allowsManagementActions = allowsManagementActions
    }

    private var person: Person? { people.first { $0.id == personId } }

    /// The roster in chip order, for the switcher.
    private var roster: [Person] {
        FamilyGroups.chipOrder(people: people, relations: relations.map(\.edge), ownFamilyId: authService?.currentUser?.familyId)
    }

    var body: some View {
        if let person {
            VStack(spacing: 0) {
                header(person)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                Picker(Copy.person.tabs.story, selection: $tab) {
                    ForEach(PersonTab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                tabContent(person)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The contextual add: the same sheet as the tab bar's **+**, with this person chosen. Not gated on `allowsManagementActions` — recording a measurement is the day-to-day use of this screen, not management of the record.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addFlow.present(for: person.id)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add for \(person.name)")
                }
                if allowsManagementActions {
                    // No delete affordance: the backend has no DeletePerson proc, so a local delete is undone by the next pull.
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showEditSheet = true
                            } label: {
                                Label("Edit \(person.name)", systemImage: "pencil")
                            }
                            if !person.photos.isEmpty {
                                Button {
                                    showProfilePhotoPicker = true
                                } label: {
                                    Label("Choose Profile Photo", systemImage: "person.crop.circle")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Manage \(person.name)")
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditPersonView(person: person)
            }
            .navigationDestination(isPresented: $showProfilePhotoPicker) {
                ProfilePhotoPickerView(person: person)
            }
        } else {
            ContentUnavailableView("Person Not Found", systemImage: "person.slash")
        }
    }

    // MARK: - Header

    private func header(_ person: Person) -> some View {
        HStack(spacing: 14) {
            PersonAvatarView(person: person, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Menu {
                    ForEach(roster) { other in
                        Button {
                            personId = other.id
                        } label: {
                            if other.id == person.id {
                                Label(other.name, systemImage: "checkmark")
                            } else {
                                Text(other.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(person.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("\(person.name), switch person")

                if let birthday = person.birthday {
                    let age = AgeCalculator.age(from: birthday, isPregnancy: person.isPregnancy)
                    Text("\(age) · \(Copy.person.born(birthday.localDay().formatted(date: .long, time: .omitted)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let relationship = person.relationship {
                    Text(relationship.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private func tabContent(_ person: Person) -> some View {
        switch tab {
        case .story:
            PersonStoryTab(person: person, onShowActivities: { tab = .activities })
        case .photos:
            PersonPhotosTab(person: person)
        case .growth:
            PersonGrowthTab(person: person)
        case .activities:
            // `GetPersonSeason` is addressed by server id; somebody created offline has no server record yet.
            if let remoteId = person.remoteId.flatMap(Int.init) {
                PersonSeasonView(personId: remoteId, personName: person.name, setsTitle: false)
                    .id(remoteId)
            } else {
                ContentUnavailableView("Not synced yet", systemImage: "icloud.and.arrow.up")
            }
        }
    }
}
