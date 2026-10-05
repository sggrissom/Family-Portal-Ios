import SwiftUI
import SwiftData

/// A person's page: a header, then **Story · Quotes · Artwork · Photos · Growth · Activities**, Quotes and Artwork only once there are some. Switching person keeps the tab, and the tab is part of the deep link (`/profile/<id>?tab=`).
struct PersonDetailView: View {
    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]

    @Environment(AddFlow.self) private var addFlow
    @Environment(AuthService.self) private var authService: AuthService?
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(ErrorPresenter.self) private var errorPresenter: ErrorPresenter?

    @State private var personId: UUID
    @State private var tab: PersonTab
    @State private var showEditSheet = false
    @State private var showProfilePhotoPicker = false
    /// `GetPersonPhotoInsights` for the person on screen: the cached answer first, then a fresh one when online.
    @State private var insights: GetPersonPhotoInsightsResponseDTO?
    let allowsManagementActions: Bool

    init(personId: UUID, tab: PersonTab = .story, allowsManagementActions: Bool = true) {
        _personId = State(initialValue: personId)
        _tab = State(initialValue: tab)
        self.allowsManagementActions = allowsManagementActions
    }

    private var person: Person? { people.first { $0.id == personId } }

    /// Whether the account can change this person and add to their record.
    private var canEdit: Bool {
        person.map { authService.access.canContribute(to: $0) } ?? false
    }

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
                    ForEach(tabs(for: person)) { Text($0.label).tag($0) }
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
                // The web's 📖 Books on a profile: the family's shelf, since a book is often about several people.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.books) {
                        Image(systemName: "book.closed")
                    }
                    .accessibilityLabel(Copy.account.books)
                }
                // The contextual add: the same sheet as the tab bar's **+**, with this person chosen. Not gated on `allowsManagementActions` — recording a measurement is the day-to-day use of this screen, not management of the record. Gated on the account's role in the person's family instead: a view-only member sees the page and nothing to change on it.
                if canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            addFlow.present(for: person.id)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add for \(person.name)")
                    }
                }
                if allowsManagementActions && canEdit {
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
                            if let suggested = suggestedProfilePhoto(for: person) {
                                Button {
                                    useAsProfilePhoto(suggested, for: person)
                                } label: {
                                    Label(Copy.person.useAsProfilePhoto, systemImage: "face.smiling")
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
            .task(id: person.remoteId) {
                await loadInsights(for: person)
            }
        } else {
            ContentUnavailableView("Person Not Found", systemImage: "person.slash")
        }
    }

    // MARK: - Header

    private func header(_ person: Person) -> some View {
        HStack(spacing: 14) {
            // The server's pick of a recent face stands in for the initials, and stays a suggestion: nothing is written to the person.
            if person.profilePhotoId == nil, let header = insights?.header {
                FaceCropView(photoId: header.photoId, box: header.box, size: 64)
                    .clipShape(Circle())
                    .accessibilityLabel("\(person.name), from a recent photo")
            } else {
                PersonAvatarView(person: person, size: 64)
            }
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
                    Text("\(age) · \(Copy.person.born(birthday.displayDay().formatted(date: .long, time: .omitted)))")
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

    // MARK: - Insights

    private func loadInsights(for person: Person) async {
        guard let remoteId = person.remoteId.flatMap(Int.init) else {
            insights = nil
            return
        }
        let analysis = AnalysisService.shared
        insights = analysis.cachedPersonPhotoInsights(personId: remoteId)
        guard network?.isConnected ?? true else { return }
        if let fresh = await analysis.refreshPersonPhotoInsights(personId: remoteId), !Task.isCancelled {
            insights = fresh
        }
    }

    /// The header face as a local photo the person is tagged in — what `setProfilePhoto` needs. `nil` while the person already has a profile photo, or the photo hasn't reached this device.
    private func suggestedProfilePhoto(for person: Person) -> Photo? {
        guard person.profilePhotoId == nil, let header = insights?.header else { return nil }
        return RemotePhotoResolution.resolve([header.photoId], in: person.photos).first
    }

    private func useAsProfilePhoto(_ photo: Photo, for person: Person) {
        Task {
            do {
                try await syncService?.setProfilePhoto(photo, for: person)
            } catch {
                errorPresenter?.report(error, title: "Couldn't Set Profile Photo")
            }
        }
    }

    // MARK: - Tabs

    /// Quotes and Artwork only for somebody who has some, as on the web.
    private func tabs(for person: Person) -> [PersonTab] {
        let hasQuotes = person.milestones.contains { milestone in milestone.category == .quote }
        let hasArtwork = person.milestones.contains { milestone in milestone.category == .artwork }
        return PersonTab.allCases.filter { option in
            switch option {
            case .quotes: hasQuotes || tab == .quotes
            case .artwork: hasArtwork || tab == .artwork
            default: true
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ person: Person) -> some View {
        switch tab {
        case .story:
            PersonStoryTab(person: person, onShowActivities: { tab = .activities })
        case .quotes:
            PersonQuotesTab(person: person)
        case .artwork:
            PersonArtworkTab(person: person)
        case .photos:
            PersonPhotosTab(person: person, insights: insights)
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
