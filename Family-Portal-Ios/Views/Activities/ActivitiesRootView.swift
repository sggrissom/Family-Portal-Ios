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

    var body: some View {
        NavigationStack {
            ActivityScreen(state: state, read: { service.activities() }) { response in
                if response.activities.isEmpty {
                    ContentUnavailableView(
                        "No Activities",
                        systemImage: "trophy",
                        description: Text("Seasons, competitions and routines are set up on the web. Once a program exists, it shows up here.")
                    )
                    .padding(.top, 40)
                } else {
                    VStack(spacing: 16) {
                        ForEach(response.activities) { activity in
                            ActivitySeasonsSection(activity: activity)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Activities")
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

    @Environment(ActivityService.self) private var service

    @State private var state = ActivityScreenState<ListSeasonsResponseDTO>()

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
                            NavigationLink {
                                SeasonView(seasonId: season.id, seasonName: season.name)
                            } label: {
                                seasonRow(season)
                            }
                            .buttonStyle(.plain)
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
            }
        }
        .task { await state.load(service.seasons(activityId: activity.id)) }
    }

    private func seasonRow(_ season: SeasonDTO) -> some View {
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
        .padding(.vertical, 6)
        .accessibilityLabel("\(season.name), \(labels.eventPlural.lowercased()) and \(labels.entryPlural.lowercased())")
    }
}
