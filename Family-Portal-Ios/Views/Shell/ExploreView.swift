import SwiftData
import SwiftUI

/// The Explore tab: the web's `/explore` directory as a native list, in the same fixed order, then a few rotating previews. Each destination is pushed onto Explore's own stack, so it stays put when the user leaves the tab and comes back.
struct ExploreView: View {
    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]

    @Environment(ChatService.self) private var chatService: ChatService?
    @Environment(AuthService.self) private var authService
    @Environment(AppNavigator.self) private var navigator
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    @State private var previews = ExplorePreviews()
    private let visit = MemoryVisit.shared

    private static let minYearsOld = 3

    var body: some View {
        List {
            Section {
                row(.photos, title: Copy.nav.photos, blurb: Copy.explore.photos, systemImage: "photo.on.rectangle")
                row(.history, title: Copy.nav.history, blurb: Copy.explore.history, systemImage: "calendar")
                row(.growth, title: Copy.nav.growth, blurb: Copy.explore.growth, systemImage: "chart.line.uptrend.xyaxis")
                row(.activities, title: Copy.nav.activities, blurb: Copy.explore.activities, systemImage: "trophy")
                row(.interviews, title: Copy.nav.interviews, blurb: Copy.explore.interviews, systemImage: "mic")
                row(.books, title: Copy.nav.books, blurb: Copy.explore.books, systemImage: "book.closed")
                // A direct visit: the server starts at the richest comparison.
                row(.sameAge(ageMonths: nil, fromRemoteId: 0), title: Copy.nav.sameAge, blurb: Copy.explore.sameAge, systemImage: "person.2")
                row(.chat, title: Copy.nav.chat, blurb: Copy.explore.chat, systemImage: "bubble.left.and.bubble.right")
                    .badge(chatService?.unreadCount ?? 0)
            }

            if let sameAge = previews.sameAge {
                Section {
                    sameAgePreview(sameAge)
                } header: {
                    previewHeader(AgeSteps.ageHeading(sameAge.ageMonths), link: Copy.explore.compare) {
                        navigator.push(.sameAge(ageMonths: sameAge.ageMonths, fromRemoteId: 0))
                    }
                }
            }

            if !previews.said.isEmpty {
                Section(Copy.explore.said) {
                    ForEach(previews.said) { memory in
                        MemoryTileView(memory: memory, people: memoryPeople) {
                            MemoryOpener(context: modelContext, navigator: navigator).open(memory)
                        }
                    }
                }
            }

            if let years = previews.years {
                Section {
                    yearsPreview(years)
                } header: {
                    previewHeader(Copy.explore.throughTheYears(years.personName.firstName), link: Copy.explore.seeStory) {
                        navigator.push(.person(years.personId))
                    }
                }
            }
        }
        .navigationTitle(Copy.explore.title)
        .task(id: network.isConnected) {
            guard network.isConnected else { return }
            await previews.load(candidates: candidates, visit: visit)
        }
    }

    // MARK: - Directory

    private func row(_ route: AppRoute, title: String, blurb: String, systemImage: String) -> some View {
        NavigationLink(value: route) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(blurb)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    // MARK: - Previews

    private var memoryPeople: [Int: (name: String, birthday: Date?)] {
        var byId: [Int: (name: String, birthday: Date?)] = [:]
        for person in people {
            if let id = person.serverId { byId[id] = (person.name, person.isPregnancy ? nil : person.birthday) }
        }
        return byId
    }

    /// Who a "through the years" strip could be about: people with a few years behind them, in the strip's order.
    private var candidates: [(id: UUID, serverId: Int, name: String)] {
        let cutoff = Calendar.current.date(byAdding: .year, value: -Self.minYearsOld, to: Date()) ?? Date()
        return FamilyGroups.chipOrder(
            people: people,
            relations: relations.map(\.edge),
            ownFamilyId: authService.currentUser?.familyId
        )
        .compactMap { person in
            guard let serverId = person.serverId, let birthday = person.birthday, birthday <= cutoff else { return nil }
            return (person.id, serverId, person.name)
        }
    }

    private func previewHeader(_ title: String, link: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(link, action: action)
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
        }
    }

    private func sameAgePreview(_ sameAge: GetSameAgeResponseDTO) -> some View {
        let rows = SameAgeText.portraitOrder(sameAge.rows.filter(ExplorePreviews.hasRecords))
        let local = people.byServerId()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(rows) { row in
                    Button {
                        navigator.push(.sameAge(ageMonths: sameAge.ageMonths, fromRemoteId: row.person.id))
                    } label: {
                        VStack(spacing: 4) {
                            face(row, local: local[row.person.id])
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                            Text(row.person.name.firstName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(width: 80)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func face(_ row: SameAgeRowDTO, local: Person?) -> some View {
        if let portrait = row.portraits.first {
            FaceCropView(photoId: portrait.photoId, box: portrait.box, size: 72)
        } else if let local {
            PersonAvatarView(person: local, size: 72)
        } else {
            PersonAvatarView(name: row.person.name, profilePhotoRemoteId: row.person.profilePhotoId, size: 72)
        }
    }

    private func yearsPreview(_ years: ExplorePreviews.Years) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(years.memories) { memory in
                    Button {
                        MemoryOpener(context: modelContext, navigator: navigator).open(memory)
                    } label: {
                        RemotePhotoView(remoteId: memory.photoIds[0], size: .thumb)
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .bottomLeading) {
                                Text(Memories.yearLabel(memory))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.black.opacity(0.65), in: Capsule())
                                    .padding(6)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
