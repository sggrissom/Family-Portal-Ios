import SwiftUI
import SwiftData

/// One season: its competitions and its routines, side by side.
///
/// `GetSeasonOverview` ships each event and each entry once and the appearances
/// as the bare hinge, rather than repeating the parents on every row — a full
/// season is a dozen competitions by a dozen routines, so the detailed shape
/// would send each entry a dozen times over. The join is done here, on `entryId`
/// and `eventId`, exactly as the web does it.
struct SeasonView: View {
    let seasonId: Int
    /// Carried in so the title is right before the payload lands. The response
    /// is authoritative once it does.
    let seasonName: String

    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var state = ActivityScreenState<GetSeasonOverviewResponseDTO>()

    var body: some View {
        ActivityScreen(state: state, read: { service.seasonOverview(seasonId: seasonId) }) { response in
            content(response)
        }
        .navigationTitle(state.value?.season.name ?? seasonName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ response: GetSeasonOverviewResponseDTO) -> some View {
        let labels = ActivityLabels.forKind(response.activity.kind)
        let people = ActivityPeople(self.people)
        let appearancesByEvent = Dictionary(grouping: response.appearances) { $0.appearance.eventId }
        let appearancesByEntry = Dictionary(grouping: response.appearances) { $0.appearance.entryId }

        VStack(spacing: 16) {
            header(response)

            GroupBox(labels.eventPlural) {
                VStack(alignment: .leading, spacing: 4) {
                    if response.events.isEmpty {
                        emptyLine("No \(labels.eventPlural.lowercased()) in this season yet")
                    } else {
                        ForEach(response.events) { event in
                            NavigationLink {
                                CompetitionView(eventId: event.id, eventName: event.name)
                            } label: {
                                eventRow(
                                    event,
                                    appearanceCount: appearancesByEvent[event.id]?.count ?? 0,
                                    labels: labels
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox(labels.entryPlural) {
                VStack(alignment: .leading, spacing: 4) {
                    if response.entries.isEmpty {
                        emptyLine("No \(labels.entryPlural.lowercased()) in this season yet")
                    } else {
                        ForEach(response.entries) { entryView in
                            NavigationLink {
                                RoutineView(entryId: entryView.entry.id, entryName: entryView.entry.name)
                            } label: {
                                entryRow(
                                    entryView,
                                    appearanceCount: appearancesByEntry[entryView.entry.id]?.count ?? 0,
                                    labels: labels,
                                    people: people
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal)
    }

    private func header(_ response: GetSeasonOverviewResponseDTO) -> some View {
        GroupBox(response.activity.name) {
            VStack(alignment: .leading, spacing: 6) {
                if let dates = ActivityDateText.range(from: response.season.startDate, to: response.season.endDate) {
                    Label(dates, systemImage: "calendar")
                        .font(.subheadline)
                }
                if !response.season.notes.isEmpty {
                    Text(response.season.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func eventRow(_ event: ActivityEventDTO, appearanceCount: Int, labels: ActivityLabels) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let subtitle = eventSubtitle(event) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(countText(appearanceCount, labels: labels))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }

    private func eventSubtitle(_ event: ActivityEventDTO) -> String? {
        var parts: [String] = []
        if !event.host.isEmpty { parts.append(event.host) }
        if !event.location.isEmpty { parts.append(event.location) }
        if let dates = ActivityDateText.range(from: event.startDate, to: event.endDate) {
            parts.append(dates)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func entryRow(
        _ entryView: EntryViewDTO,
        appearanceCount: Int,
        labels: ActivityLabels,
        people: ActivityPeople
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entryView.entry.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                let descriptors = ActivityEntryText.descriptors(entryView.entry)
                if !descriptors.isEmpty {
                    Text(descriptors)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let roster = people.rosterText(entryView.personIds) {
                    Text("\(labels.roster): \(roster)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(countText(appearanceCount, labels: labels))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }

    private func countText(_ count: Int, labels: ActivityLabels) -> String {
        count == 1 ? "1 \(labels.appearance.lowercased())" : "\(count) \(labels.appearancePlural.lowercased())"
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
