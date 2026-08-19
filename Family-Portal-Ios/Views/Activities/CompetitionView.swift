import SwiftUI
import SwiftData

/// One competition, as it happened: every performance in order, plus the
/// weekend's own photos.
///
/// `GetEventDetail` is one walk of the by-event index, so this is a single call
/// no matter how many routines danced.
struct CompetitionView: View {
    let eventId: Int
    /// For the title before the payload lands.
    let eventName: String

    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var state = ActivityScreenState<GetEventDetailResponseDTO>()

    var body: some View {
        ActivityScreen(state: state, read: { service.eventDetail(eventId: eventId) }) { response in
            content(response)
        }
        .navigationTitle(state.value?.event.name ?? eventName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ response: GetEventDetailResponseDTO) -> some View {
        // The season summary carries the activity's kind for exactly this: the
        // response holds no `Activity`, and without it the screen would render
        // "Event" — the one word the label map exists to avoid.
        let labels = ActivityLabels.forKind(response.season.kind)
        let people = ActivityPeople(self.people)

        VStack(spacing: 16) {
            header(response, labels: labels)

            GroupBox(labels.appearancePlural) {
                VStack(alignment: .leading, spacing: 12) {
                    if response.appearances.isEmpty {
                        Text("No \(labels.appearancePlural.lowercased()) recorded yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(response.appearances) { detail in
                            NavigationLink {
                                RoutineView(entryId: detail.entry.id, entryName: detail.entry.name)
                            } label: {
                                AppearanceDetailRow(
                                    detail: detail,
                                    people: people,
                                    title: .entry,
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

    private func header(_ response: GetEventDetailResponseDTO, labels: ActivityLabels) -> some View {
        GroupBox(response.season.name) {
            VStack(alignment: .leading, spacing: 6) {
                if !response.event.host.isEmpty {
                    Label(response.event.host, systemImage: "building.2")
                        .font(.subheadline)
                }
                if !response.event.location.isEmpty {
                    Label(response.event.location, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                }
                if let dates = ActivityDateText.range(from: response.event.startDate, to: response.event.endDate) {
                    Label(dates, systemImage: "calendar")
                        .font(.subheadline)
                }
                if !response.event.notes.isEmpty {
                    Text(response.event.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // The competition's own photos — the venue, the group in the
                // lobby. A routine's photos travel with its performance.
                ActivityPhotoStrip(photoIds: response.photoIds)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
