import SwiftUI

/// Activities, pushed from More: what is in season first — a card per season under way across every program — then programs between seasons, then past seasons. Renaming and deleting sit behind Manage. The web's `/activities`, from one `GetActivitiesHome` call.
struct ActivitiesRootView: View {
    @Environment(ActivityService.self) private var service
    @Environment(AuthService.self) private var authService

    @State private var state = ActivityScreenState<GetActivitiesHomeResponseDTO>()
    @State private var sheet: Sheet?
    @State private var isManaging = false

    private enum Sheet: Identifiable {
        case addActivity
        case editActivity(ActivityDTO)
        case addSeason(activityId: Int)
        case editSeason(SeasonDTO)

        var id: String {
            switch self {
            case .addActivity: return "activity-new"
            case .editActivity(let activity): return "activity-\(activity.id)"
            case .addSeason(let activityId): return "season-new-\(activityId)"
            case .editSeason(let season): return "season-\(season.id)"
            }
        }
    }

    var body: some View {
        ActivityScreen(state: state, read: { service.activitiesHome() }) { response in
            // A view-only member of the family sees its programs and none of the controls that add to or change them, as on the web.
            let editable = authService.access.canContribute(response.familyId == 0 ? nil : response.familyId)
            if response.activities.isEmpty {
                ContentUnavailableView {
                    Label("No Activities", systemImage: "trophy")
                } description: {
                    Text("Track a competitive season — the competitions or games, the routines or teams, and how each one did.")
                } actions: {
                    if editable {
                        Button("Add a Program") { sheet = .addActivity }
                    }
                }
                .padding(.top, 40)
            } else {
                content(response, editable: editable)
            }
        }
        .navigationTitle(Copy.account.activities)
        .sheet(item: $sheet) { presented in
            switch presented {
            case .addActivity:
                ActivityEditorView(onSaved: { await state.reload() })
            case .editActivity(let activity):
                ActivityEditorView(existing: activity, onSaved: { await state.reload() }, onDeleted: { await state.reload() })
            case .addSeason(let activityId):
                SeasonEditorView(activityId: activityId, onSaved: { await state.reload() })
            case .editSeason(let season):
                SeasonEditorView(activityId: season.activityId, existing: season, onSaved: { await state.reload() }, onDeleted: { await state.reload() })
            }
        }
    }

    @ViewBuilder
    private func content(_ response: GetActivitiesHomeResponseDTO, editable: Bool) -> some View {
        let today = Date().localRecordDay().recordDayKey
        let inSeason = response.seasons
            .filter { ActivityHome.phase(of: $0.season, today: today) != .past }
            .sorted { $0.season.startDate < $1.season.startDate }
        let past = response.seasons.filter { ActivityHome.phase(of: $0.season, today: today) == .past }
        let idle = response.activities.filter { activity in
            !inSeason.contains { $0.season.activityId == activity.id }
        }
        let activity = { (season: SeasonDTO) in response.activities.first { $0.id == season.activityId } }

        VStack(alignment: .leading, spacing: 20) {
            if !inSeason.isEmpty {
                section("In season") {
                    ForEach(inSeason) { home in
                        SeasonCard(home: home, activity: activity(home.season), today: today, editable: editable)
                    }
                }
            }

            if !idle.isEmpty {
                section(inSeason.isEmpty ? "Programs" : "Between seasons") {
                    ForEach(idle) { program in
                        idleProgram(program, response: response, editable: editable)
                    }
                }
            }

            if !past.isEmpty {
                section("Past seasons") {
                    GroupBox {
                        VStack(spacing: 0) {
                            ForEach(past) { home in
                                pastSeason(home, activity: activity(home.season))
                                if home.id != past.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }

            if editable {
                // A text button rather than a toolbar `+`: the one **+** in the app is the add sheet's, and a second one here would mean something else.
                Button {
                    sheet = .addActivity
                } label: {
                    Label("New Program", systemImage: "plus.circle")
                }

                DisclosureGroup("Manage programs and seasons", isExpanded: $isManaging) {
                    manage(response)
                }
            }
        }
        .padding(.horizontal)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }

    private func idleProgram(_ program: ActivityDTO, response: GetActivitiesHomeResponseDTO, editable: Bool) -> some View {
        let last = response.seasons.first { $0.season.activityId == program.id }
        return GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(program.name, systemImage: ActivityKind.symbol(program.kind))
                        .font(.headline)
                    Text(last.map { "Last season: \($0.season.name)" } ?? "No seasons yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if editable {
                    Button("Start a Season") { sheet = .addSeason(activityId: program.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private func pastSeason(_ home: HomeSeasonDTO, activity: ActivityDTO?) -> some View {
        let labels = ActivityLabels.forKind(activity?.kind ?? ActivityKind.generic)
        let events = home.events.count
        let entries = home.entries.count
        let counts = "\(events) \((events == 1 ? labels.event : labels.eventPlural).lowercased()) · \(entries) \((entries == 1 ? labels.entry : labels.entryPlural).lowercased())"
        let dates = ActivityDateText.range(from: home.season.startDate, to: home.season.endDate)

        return NavigationLink {
            SeasonView(seasonId: home.season.id, seasonName: home.season.name)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(home.season.name)
                        .font(.subheadline.weight(.semibold))
                    Text([activity?.name, dates].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(counts)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Renaming and deleting programs and seasons: rarely wanted, so folded away.
    private func manage(_ response: GetActivitiesHomeResponseDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(response.activities) { program in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(program.name)
                            .font(.subheadline.weight(.semibold))
                        Text(ActivityKind.displayName(program.kind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit") { sheet = .editActivity(program) }
                            .accessibilityLabel("Edit \(program.name)")
                    }
                    ForEach(response.seasons.filter { $0.season.activityId == program.id }) { home in
                        HStack {
                            Text(home.season.name)
                                .font(.subheadline)
                            Spacer()
                            Button("Edit") { sheet = .editSeason(home.season) }
                                .accessibilityLabel("Edit \(home.season.name)")
                        }
                        .padding(.leading, 12)
                    }
                    Button {
                        sheet = .addSeason(activityId: program.id)
                    } label: {
                        Label("Add Season", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                    .padding(.leading, 12)
                }
            }
        }
        .padding(.top, 8)
    }
}

/// A season under way: its program, its routines, and the competitions worth a look right now — the latest with results, any held one still missing them (with Add results), today's, and the next.
private struct SeasonCard: View {
    let home: HomeSeasonDTO
    let activity: ActivityDTO?
    let today: String
    let editable: Bool

    private var labels: ActivityLabels { .forKind(activity?.kind ?? ActivityKind.generic) }

    var body: some View {
        let progress = ActivityHome.progress(of: home, today: today)
        let starts = ActivityHome.phase(of: home.season, today: today) == .upcoming

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink {
                    SeasonView(seasonId: home.season.id, seasonName: home.season.name)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        if let activity {
                            Label(activity.name, systemImage: ActivityKind.symbol(activity.kind))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text(home.season.name)
                                .font(.headline)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let dates = ActivityDateText.range(from: home.season.startDate, to: home.season.endDate) {
                            Text(starts ? "Starts \(dates)" : dates)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !home.entries.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(home.entries) { view in
                                NavigationLink(view.entry.name) {
                                    RoutineView(entryId: view.entry.id, entryName: view.entry.name)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                ForEach(progress.focus, id: \.event.id) { item in
                    eventRow(item.event, focus: item.focus)
                }

                Text(home.events.isEmpty
                     ? "No \(labels.eventPlural.lowercased()) yet"
                     : "\(progress.recorded) of \(progress.held) \(labels.eventPlural.lowercased()) recorded · \(home.events.count) this season")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func eventRow(_ item: HomeEventDTO, focus: ActivityHome.Focus) -> some View {
        NavigationLink {
            CompetitionView(eventId: item.event.id, eventName: item.event.name)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(focus == .needsResults ? Color.orange : Color.secondary)
                    Text(item.event.name)
                        .font(.subheadline.weight(.medium))
                    if let day = ActivityDateText.day(item.event.startDate) {
                        Text(day)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if editable && (focus == .needsResults || focus == .now) {
                    Text("Add results")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                } else if focus == .latest {
                    let n = item.appearances
                    Text("\(n) \((n == 1 ? labels.appearance : labels.appearancePlural).lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
