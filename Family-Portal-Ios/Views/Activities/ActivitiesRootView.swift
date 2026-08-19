import SwiftUI

/// The Activities tab: the family's programs, and the seasons under each.
///
/// One call for the programs plus one per program for its seasons. There is no
/// proc that lists seasons across activities, and N is about 1 — a family runs
/// one program, occasionally two — so the fan-out this shape usually warns
/// against does not apply.
struct ActivitiesRootView: View {
    @Environment(ActivityService.self) private var service

    @State private var state = ActivityScreenState<ListActivitiesResponseDTO>()
    @State private var isAddingActivity = false

    var body: some View {
        NavigationStack {
            ActivityScreen(state: state, read: { service.activities() }) { response in
                if response.activities.isEmpty {
                    ContentUnavailableView {
                        Label("No Activities", systemImage: "trophy")
                    } description: {
                        Text("An activity is a program the family is in — dance, soccer, swim. Its seasons, competitions and routines hang off it.")
                    } actions: {
                        Button("New Activity") { isAddingActivity = true }
                    }
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 16) {
                        ForEach(response.activities) { activity in
                            ActivitySeasonsSection(activity: activity, onChanged: { await state.reload() })
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Activities")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingActivity = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Activity")
                }
            }
            .sheet(isPresented: $isAddingActivity) {
                ActivityEditorView(onSaved: { await state.reload() })
            }
        }
    }
}

/// One program and its seasons.
///
/// Its own screen state rather than a slice of the parent's: each list is its
/// own call and its own cache entry, so a program whose seasons fail to load
/// says so under that program instead of blanking the tab.
private struct ActivitySeasonsSection: View {
    let activity: ActivityDTO
    /// The activity list itself has to reload when a program is renamed or
    /// deleted, which is the parent's business, not this section's.
    let onChanged: @MainActor () async -> Void

    @Environment(ActivityService.self) private var service

    @State private var state = ActivityScreenState<ListSeasonsResponseDTO>()
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case editActivity
        case addSeason
        case editSeason(SeasonDTO)

        var id: String {
            switch self {
            case .editActivity: return "activity"
            case .addSeason: return "season-new"
            case .editSeason(let season): return "season-\(season.id)"
            }
        }
    }

    private var labels: ActivityLabels { .forKind(activity.kind) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if let seasons = state.value?.seasons {
                    if seasons.isEmpty {
                        Text("No seasons yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(seasons) { season in
                            seasonRow(season)
                        }
                    }
                } else if let error = state.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    sheet = .addSeason
                } label: {
                    Label("Add Season", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text(activity.name)
                Spacer()
                Text(ActivityKind.displayName(activity.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    sheet = .editActivity
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Edit \(activity.name)")
            }
        }
        .task { await state.load(service.seasons(activityId: activity.id)) }
        .sheet(item: $sheet) { presented in
            switch presented {
            case .editActivity:
                ActivityEditorView(existing: activity, onSaved: {
                    // A renamed or deleted program changes the list above as
                    // well as the seasons below it.
                    await onChanged()
                    await state.reload()
                })
            case .addSeason:
                SeasonEditorView(activityId: activity.id, onSaved: { await state.reload() })
            case .editSeason(let season):
                SeasonEditorView(
                    activityId: activity.id,
                    existing: season,
                    onSaved: { await state.reload() }
                )
            }
        }
    }

    private func seasonRow(_ season: SeasonDTO) -> some View {
        HStack {
            NavigationLink {
                SeasonView(seasonId: season.id, seasonName: season.name)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(season.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let dates = ActivityDateText.range(from: season.startDate, to: season.endDate) {
                            Text(dates)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .accessibilityLabel("\(season.name), \(labels.eventPlural.lowercased()) and \(labels.entryPlural.lowercased())")
            }
            .buttonStyle(.plain)

            Button {
                sheet = .editSeason(season)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(season.name)")
        }
        .padding(.vertical, 6)
    }
}
