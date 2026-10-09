import SwiftUI
import SwiftData

/// Home: the family strip, up to two nudges, what's in season, on this day, and the last two weeks — the web's dashboard.
/// The strip and Recent render from the store, so they are up before the network answers. Nudges, In season and On this day come from `GetDashboard`, cached: the last good answer shows at once and is replaced when a fetch lands.
/// A cached dashboard from an earlier day is stale in exactly the sections that name a day — a birthday "tomorrow", an event "Today" — so those three are held back until a fresh one arrives.
struct HomeView: View {
    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]
    @Query(sort: \Milestone.date, order: .reverse) private var milestones: [Milestone]
    @Query(sort: \GrowthData.date, order: .reverse) private var growth: [GrowthData]
    @Query(sort: \Photo.photoDate, order: .reverse) private var photos: [Photo]

    @Environment(AuthService.self) private var authService
    @Environment(AppNavigator.self) private var navigator
    @Environment(AddFlow.self) private var addFlow
    @Environment(ActivityService.self) private var activityService

    @State private var dashboard = ActivityScreenState<GetDashboardResponseDTO>()
    @State private var dismissedVersion = 0

    private let dismissals = NudgeDismissals()
    private static let recentDays = 14

    private var today: String { WhenEntry.localDateString(Date()) }

    /// Whether the dashboard in hand answers for today.
    private var current: GetDashboardResponseDTO? {
        guard let value = dashboard.value, value.today == today else { return nil }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                familyStrip

                if let current {
                    nudges(current)
                    inSeason(current)
                    onThisDay(current)
                }

                recent
            }
            .padding(.vertical)
        }
        .navigationTitle(Copy.nav.home)
        .safeAreaInset(edge: .top, spacing: 0) {
            if dashboard.isShowingCached, !dashboard.isLoading, dashboard.value != nil {
                ActivityStaleNote(fetchedAt: dashboard.fetchedAt)
            }
        }
        .refreshable { await dashboard.reload() }
        .task {
            await dashboard.load(activityService.dashboard(today: today))
        }
    }

    // MARK: - Family strip

    private var familyStrip: some View {
        let ordered = people.filter(\.isPregnancy) + FamilyGroups.chipOrder(
            people: people,
            relations: relations.map(\.edge),
            ownFamilyId: authService.currentUser?.familyId
        )
        let names = FamilyGroups.chipLabels(ordered)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(ordered) { person in
                    NavigationLink(value: AppRoute.person(person.id)) {
                        stripPerson(person, name: names[person.id] ?? person.name)
                    }
                    .buttonStyle(.plain)
                }
                if authService.access.canContributeAnywhere {
                    Button {
                        addFlow.open(.person)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.title3)
                                .frame(width: 56, height: 56)
                                .background(Color(.secondarySystemBackground), in: Circle())
                            Text(Copy.home.addPerson)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .frame(width: 72)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func stripPerson(_ person: Person, name: String) -> some View {
        let age: String = person.birthday.map { birthday in
            person.isPregnancy
                ? FamilyStrip.dueSummary(dueDate: birthday, today: Date().localRecordDay())
                : FamilyStrip.compactAge(birthday: birthday, today: Date().localRecordDay())
        } ?? ""
        return VStack(spacing: 4) {
            PersonAvatarView(person: person, size: 56)
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(age)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(age.isEmpty ? person.name : "\(person.name), \(age)")
    }

    // MARK: - Nudges

    @ViewBuilder
    private func nudges(_ dashboard: GetDashboardResponseDTO) -> some View {
        let _ = dismissedVersion
        let shown = dismissals.visible(dashboard.nudges)
        if !shown.isEmpty {
            VStack(spacing: 8) {
                ForEach(shown) { nudge in
                    HStack {
                        Button {
                            act(on: nudge)
                        } label: {
                            Text(nudge.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button {
                            dismissals.dismiss(nudge.key)
                            dismissedVersion += 1
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                        }
                        .accessibilityLabel(Copy.home.dismiss)
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal)
        }
    }

    /// Where a nudge leads: a measurement for the person, their page, or face review.
    private func act(on nudge: DashboardNudgeDTO) {
        let person = people.first { $0.serverId == nudge.personId }
        switch nudge.kind {
        case "measure":
            addFlow.open(.measurement(personId: person?.id))
        case "faces":
            navigator.push(.faces)
        default:
            if let person { navigator.push(.person(person.id)) }
        }
    }

    // MARK: - In season

    @ViewBuilder
    private func inSeason(_ dashboard: GetDashboardResponseDTO) -> some View {
        if !dashboard.seasons.isEmpty {
            section(Copy.home.inSeason) {
                ForEach(dashboard.seasons) { season in
                    VStack(alignment: .leading, spacing: 6) {
                        NavigationLink {
                            SeasonView(seasonId: season.season.id, seasonName: season.season.name)
                        } label: {
                            Text("🏆 \(season.activityName) · \(season.season.name)")
                                .font(.subheadline.weight(.semibold))
                        }
                        if let event = season.event {
                            Button {
                                navigator.push(.event(id: event.id, name: event.name))
                            } label: {
                                Text("\(Copy.home.eventTiming[season.eventTiming] ?? ""): \(event.name) · \(DaySummaries.dayLabel(event.startDate.recordDayKey, today: today))")
                                    .font(.subheadline)
                            }
                            if season.canContribute {
                                HStack {
                                    Button(Copy.home.addPhotos) {
                                        navigator.push(.event(id: event.id, name: event.name))
                                    }
                                    .buttonStyle(.bordered)
                                    if season.canAddResults {
                                        Button(Copy.home.addResults) {
                                            navigator.push(.event(id: event.id, name: event.name))
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // MARK: - On this day

    @ViewBuilder
    private func onThisDay(_ dashboard: GetDashboardResponseDTO) -> some View {
        if !dashboard.onThisDay.isEmpty {
            let names = people.byServerId().mapValues(\.name.firstName)
            let photosById = photos.byServerId()
            section(Copy.home.onThisDay) {
                ForEach(dashboard.onThisDay) { year in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Copy.home.yearsAgo(year.yearsAgo))
                            .font(.subheadline.weight(.semibold))
                        if !year.photos.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(year.photos, id: \.id) { image in
                                        onThisDayPhoto(image.id, local: photosById[image.id])
                                    }
                                }
                            }
                        }
                        ForEach(year.milestones, id: \.id) { milestone in
                            let category = MilestoneCategory(rawValue: milestone.category) ?? .other
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: category.icon)
                                    .foregroundStyle(category.color)
                                Text(names[milestone.personId] ?? "").fontWeight(.semibold)
                                    + Text(" \(milestone.displayText)")
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func onThisDayPhoto(_ remoteId: Int, local photo: Photo?) -> some View {
        let thumb = RemotePhotoView(remoteId: remoteId, size: .thumb)
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        if let photo {
            NavigationLink(value: PhotoRoute(id: photo.id)) { thumb }
                .accessibilityLabel("View photo")
        } else {
            thumb
        }
    }

    // MARK: - Recent

    /// The last two weeks, from the store: what was just added shows here before it has synced.
    private var recent: some View {
        let from = recentFrom
        let records = DayRecords(
            photos: photos.filter { $0.photoDate.recordDayKey >= from },
            growth: growth.filter { $0.date.recordDayKey >= from },
            milestones: milestones.filter { $0.date.recordDayKey >= from }
        )
        let days = DaySummaries.summarize(records, people: people, range: (from: from, to: today))
        return section(Copy.home.recent, trailing: {
            NavigationLink(value: AppRoute.history) {
                Text(Copy.home.seeAll).font(.subheadline)
            }
        }) {
            if days.isEmpty {
                Text(Copy.home.nothingRecent)
                    .foregroundStyle(.secondary)
            } else {
                DaySummaryList(days: days, today: today)
            }
        }
    }

    /// The dashboard's own window when it has one for today, else the same 14 days counted here.
    private var recentFrom: String {
        if let current, !current.recent.from.isEmpty { return current.recent.from }
        let start = Calendar.current.date(byAdding: .day, value: -(Self.recentDays - 1), to: Date()) ?? Date()
        return WhenEntry.localDateString(start)
    }

    // MARK: - Layout

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        section(title, trailing: { EmptyView() }, content: content)
    }

    private func section<Trailing: View, Content: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title3.weight(.bold))
                Spacer()
                trailing()
            }
            content()
        }
        .padding(.horizontal)
    }
}
