import SwiftUI
import SwiftData

/// One routine across its season: where it went, and how it did each time.
///
/// `GetEntryHistory` is the other direction off the same hinge as
/// `GetEventDetail`, and one of the two procs that resolve through a roster — so
/// it answers with a `SeasonSummary` and an `EventSummary` per performance
/// rather than the full records.
struct RoutineView: View {
    let entryId: Int
    /// For the title before the payload lands.
    let entryName: String

    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var state = ActivityScreenState<GetEntryHistoryResponseDTO>()

    var body: some View {
        ActivityScreen(state: state, read: { service.entryHistory(entryId: entryId) }) { response in
            content(response)
        }
        .navigationTitle(state.value?.entry.entry.name ?? entryName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ response: GetEntryHistoryResponseDTO) -> some View {
        let labels = ActivityLabels.forKind(response.season.kind)
        let people = ActivityPeople(self.people)

        VStack(spacing: 16) {
            header(response, labels: labels, people: people)

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
                                    showsChevron: true
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

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
