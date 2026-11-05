import SwiftUI
import SwiftData

/// One routine across its season: stat tiles (competitions, best placement and where, head-to-head record, adjudications), then how it did at each competition.
/// `GetEntryHistory` resolves through a roster, so it answers with a `SeasonSummary` and an `EventSummary` per performance rather than the full records.
struct RoutineView: View {
    let entryId: Int
    let entryName: String

    @Environment(ActivityService.self) private var service
    @Environment(AuthService.self) private var authService
    @Query private var people: [Person]

    @State private var state = ActivityScreenState<GetEntryHistoryResponseDTO>()
    @State private var isEditing = false

    @Environment(\.dismiss) private var dismiss

    private var labels: ActivityLabels {
        ActivityLabels.forKind(state.value?.season.kind ?? ActivityKind.generic)
    }

    private var editable: Bool {
        guard let entry = state.value?.entry.entry else { return false }
        return authService.access.canContribute(entry.familyId)
    }

    var body: some View {
        ActivityScreen(state: state, read: { service.entryHistory(entryId: entryId) }) { response in
            content(response)
        }
        .navigationTitle(state.value?.entry.entry.name ?? entryName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A view-only member of the routine's family reads it without the editor, as on the web.
            if editable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit \(labels.entry)")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let response = state.value {
                // `GetEntryHistory` carries a `SeasonSummary`, whose id is all the editor needs — this is always an edit.
                RoutineEditorView(
                    seasonId: response.season.id,
                    existing: response.entry,
                    labels: labels,
                    onSaved: { await state.reload() },
                    onDeleted: { dismiss() }
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ response: GetEntryHistoryResponseDTO) -> some View {
        let labels = ActivityLabels.forKind(response.season.kind)
        let people = ActivityPeople(self.people)

        VStack(spacing: 16) {
            header(response, labels: labels, people: people)

            if !response.appearances.isEmpty {
                stats(response, labels: labels)
            }

            GroupBox(labels.appearancePlural) {
                VStack(alignment: .leading, spacing: 12) {
                    if response.appearances.isEmpty {
                        Text("This \(labels.entry.lowercased()) hasn't been to a \(labels.event.lowercased()) yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(response.appearances) { detail in
                            NavigationLink {
                                CompetitionView(eventId: detail.event.id, eventName: detail.event.name)
                            } label: {
                                AppearanceDetailRow(
                                    detail: detail,
                                    people: people,
                                    title: .event,
                                    showsChevron: true,
                                    showsPhotos: false
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            ActivityPhotoStrip(photoIds: detail.photoIds)

                            if detail.id != response.appearances.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal)
    }

    private func stats(_ response: GetEntryHistoryResponseDTO, labels: ActivityLabels) -> some View {
        let events = Set(response.appearances.map(\.event.id)).count
        let best = ActivityResults.bestFinish(response.appearances) { $0.results }
        let tally = Matchups.tally(response.appearances.map { Matchup($0.appearance) })
        let record = Matchups.recordText(tally)
        let adjudications = ActivityResults.adjudicationCounts(response.appearances.flatMap(\.results))

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], alignment: .leading, spacing: 10) {
            statTile(
                value: "\(events)",
                caption: (events == 1 ? labels.event : labels.eventPlural).lowercased()
            )
            if let best, let rank = best.result.rank {
                statTile(value: ActivityResults.ordinal(rank), caption: "best, at \(best.view.event.name)")
            }
            if !record.isEmpty {
                statTile(value: record, caption: Matchups.recordLabel(tally))
            }
            ForEach(adjudications, id: \.label) { count in
                statTile(value: "\(count.count)×", caption: count.label)
            }
        }
    }

    private func statTile(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        .accessibilityElement(children: .combine)
    }

    private func header(
        _ response: GetEntryHistoryResponseDTO,
        labels: ActivityLabels,
        people: ActivityPeople
    ) -> some View {
        GroupBox(response.season.name) {
            VStack(alignment: .leading, spacing: 6) {
                let descriptors = ActivityEntryText.descriptors(response.entry.entry)
                if !descriptors.isEmpty {
                    Text(descriptors)
                        .font(.subheadline)
                }

                if let roster = people.rosterText(response.entry.personIds) {
                    Label("\(labels.roster): \(roster)", systemImage: "person.2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !response.entry.entry.notes.isEmpty {
                    Text(response.entry.entry.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
