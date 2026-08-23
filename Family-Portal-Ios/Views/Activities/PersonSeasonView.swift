import SwiftUI
import SwiftData

/// "How is her season going?" — one kid's routines, their results, the photos.
///
/// The headline activities screen and the one this feature exists for on a
/// phone: read-only, one proc, no navigation tree to walk first.
///
/// `GetPersonSeason` resolves through the roster rather than through the family,
/// which makes it the one activities proc that is always safe to call for any
/// person the app can see. Everything it links to has to hold that line, which
/// is why the only destination here is `RoutineView` (`GetEntryHistory`, also
/// roster-scoped) and not the season or competition views — those are
/// whole-family reads a linked household cannot reach.
struct PersonSeasonView: View {
    let personId: Int
    let personName: String

    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var state = ActivityScreenState<GetPersonSeasonResponseDTO>()

    var body: some View {
        ActivityScreen(state: state, read: { service.personSeason(personId: personId) }) { response in
            content(response)
        }
        .navigationTitle("\(personName)'s Seasons")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ response: GetPersonSeasonResponseDTO) -> some View {
        let people = ActivityPeople(self.people)
        let appearancesByEntry = Dictionary(grouping: response.appearances) { $0.appearance.entryId }

        if response.seasons.isEmpty {
            ContentUnavailableView(
                "No Seasons Yet",
                systemImage: "trophy",
                description: Text("\(personName) isn't on any rosters.")
            )
            .padding(.top, 40)
        } else {
            VStack(spacing: 16) {
                ForEach(response.seasons) { season in
                    seasonSection(
                        season,
                        entries: response.entries.filter { $0.entry.seasonId == season.id },
                        appearancesByEntry: appearancesByEntry,
                        people: people
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    private func seasonSection(
        _ season: SeasonSummaryDTO,
        entries: [EntryViewDTO],
        appearancesByEntry: [Int: [AppearanceDetailDTO]],
        people: ActivityPeople
    ) -> some View {
        // Read the label pack from the season summary: this response carries no
        // `Activity`, and the backend added `kind` here for exactly that reason.
        let labels = ActivityLabels.forKind(season.kind)

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if let dates = ActivityDateText.range(from: season.startDate, to: season.endDate) {
                    Text(dates)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if entries.isEmpty {
                    Text("No \(labels.entryPlural.lowercased()) in this season")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entryView in
                        entrySection(
                            entryView,
                            appearances: appearancesByEntry[entryView.entry.id] ?? [],
                            labels: labels,
                            people: people
                        )

                        if entryView.id != entries.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } label: {
            Text(season.name)
        }
    }

    private func entrySection(
        _ entryView: EntryViewDTO,
        appearances: [AppearanceDetailDTO],
        labels: ActivityLabels,
        people: ActivityPeople
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink {
                RoutineView(entryId: entryView.entry.id, entryName: entryView.entry.name)
            } label: {
                HStack(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entryView.entry.name)
                            .font(.headline)

                        let descriptors = ActivityEntryText.descriptors(entryView.entry)
                        if !descriptors.isEmpty {
                            Text(descriptors)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Who else is in it. A group routine reached through one
                        // shared child legitimately names its co-performers —
                        // that is what a shared routine means.
                        if let roster = people.rosterText(entryView.personIds) {
                            Text("\(labels.roster): \(roster)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if appearances.isEmpty {
                Text("No \(labels.appearancePlural.lowercased()) yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appearances) { detail in
                    AppearanceDetailRow(
                        detail: detail,
                        people: people,
                        title: .event
                    )
                    .padding(.leading, 8)
                }
            }
        }
    }
}
