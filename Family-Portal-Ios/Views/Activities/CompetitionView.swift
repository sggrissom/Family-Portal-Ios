import SwiftUI
import SwiftData

/// One competition, as it happened: every performance in order, plus the
/// weekend's own photos — and, on the day, where they get entered.
///
/// `GetEventDetail` is one walk of the by-event index, so the read is a single
/// call no matter how many routines danced. The season overview alongside it is
/// only for *writing*: it is the one payload that carries the season's whole
/// entry list (which routine to file) and the activity id (which vocabulary to
/// autocomplete from), neither of which the event detail has. It is cached like
/// every other read, and usually already warm from the screen the user came
/// through.
struct CompetitionView: View {
    let eventId: Int
    /// For the title before the payload lands.
    let eventName: String

    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var state = ActivityScreenState<GetEventDetailResponseDTO>()
    @State private var seasonState = ActivityScreenState<GetSeasonOverviewResponseDTO>()

    /// One sheet slot rather than four `.sheet` modifiers stacked on one view.
    /// SwiftUI presents a single sheet per view, so several `isPresented`
    /// bindings on the same node race each other and the loser silently never
    /// appears.
    private enum AppearanceSheet: Identifiable {
        case add
        case edit(AppearanceDetailDTO)
        case results(AppearanceDetailDTO)
        case photos(AppearanceDetailDTO)
        /// The competition itself, and the weekend's own photos.
        case editEvent
        case eventPhotos

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let detail): return "edit-\(detail.id)"
            case .results(let detail): return "results-\(detail.id)"
            case .photos(let detail): return "photos-\(detail.id)"
            case .editEvent: return "event"
            case .eventPhotos: return "event-photos"
            }
        }
    }

    @State private var sheet: AppearanceSheet?

    /// A deleted competition leaves nothing to show, so the screen goes rather
    /// than reloading into a 404.
    @Environment(\.dismiss) private var dismiss

    private var labels: ActivityLabels {
        ActivityLabels.forKind(state.value?.season.kind ?? ActivityKind.generic)
    }

    /// Writing needs the season. Until it lands there is nothing to file a
    /// performance *as*, so the affordance is off rather than presenting a
    /// picker with nothing in it.
    private var canWrite: Bool { seasonState.value != nil }

    var body: some View {
        ActivityScreen(state: state, read: { service.eventDetail(eventId: eventId) }) { response in
            content(response)
        }
        .navigationTitle(state.value?.event.name ?? eventName)
        .navigationBarTitleDisplayMode(.inline)
        // Keyed on the season id so it fires once the event detail names it, and
        // again only if it somehow changes.
        .task(id: state.value?.season.id) {
            guard let seasonId = state.value?.season.id else { return }
            await seasonState.load(service.seasonOverview(seasonId: seasonId))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sheet = .add
                    } label: {
                        Label("Add \(labels.appearance)", systemImage: "plus")
                    }
                    .disabled(!canWrite)

                    Button {
                        sheet = .eventPhotos
                    } label: {
                        Label("\(labels.event) Photos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        sheet = .editEvent
                    } label: {
                        Label("Edit \(labels.event)", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(state.value == nil)
                .accessibilityLabel("\(labels.event) actions")
            }
        }
        .sheet(item: $sheet) { presented in
            switch presented {
            case .add:
                AddAppearanceView(
                    eventId: eventId,
                    entries: seasonState.value?.entries ?? [],
                    labels: labels,
                    onSaved: { await state.reload() }
                )
            case .edit(let detail):
                EditAppearanceView(
                    appearance: detail.appearance,
                    entryName: detail.entry.name,
                    labels: labels,
                    onSaved: { await state.reload() }
                )
            case .results(let detail):
                ResultsEditorView(
                    appearanceId: detail.appearance.id,
                    entryName: detail.entry.name,
                    roster: roster(forEntry: detail.entry.id),
                    activityId: seasonState.value?.activity.id,
                    initialResults: detail.results,
                    labels: labels,
                    onSaved: { await state.reload() }
                )
            case .editEvent:
                if let response = state.value {
                    CompetitionEditorView(
                        seasonId: response.season.id,
                        existing: response.event,
                        labels: labels,
                        hostSuggestions: [],
                        onSaved: { await state.reload() },
                        onDeleted: { dismiss() }
                    )
                }
            case .eventPhotos:
                if let response = state.value {
                    // The competition's *own* photos — the venue, the group in
                    // the lobby. A routine's photos travel with its performance,
                    // which is the other picker.
                    ActivityPhotoPickerView(
                        attachedPhotoIds: response.photoIds,
                        subject: labels.event.lowercased(),
                        save: { photoIds in
                            _ = try await service.setEventPhotos(eventId: response.event.id, photoIds: photoIds)
                        },
                        onSaved: { await state.reload() }
                    )
                }
            case .photos(let detail):
                ActivityPhotoPickerView(
                    attachedPhotoIds: detail.photoIds,
                    subject: labels.appearance.lowercased(),
                    save: { photoIds in
                        _ = try await service.setAppearancePhotos(
                            appearanceId: detail.appearance.id,
                            photoIds: photoIds
                        )
                    },
                    onSaved: { await state.reload() }
                )
            }
        }
    }

    /// The entry's roster, for narrowing a result to one person. Empty when the
    /// season has not loaded — the person picker simply does not appear, and the
    /// server still checks the rule either way.
    private func roster(forEntry entryId: Int) -> [Int] {
        seasonState.value?.entries.first { $0.entry.id == entryId }?.personIds ?? []
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
                            appearanceRow(detail, people: people)

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

    /// The row leads to the routine's history; everything you do *to* the
    /// performance is behind the menu. A `ScrollView` has no swipe actions to
    /// hang them off, and competition day wants them one tap deep rather than
    /// behind a mode switch.
    private func appearanceRow(_ detail: AppearanceDetailDTO, people: ActivityPeople) -> some View {
        HStack(alignment: .top, spacing: 8) {
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

            Menu {
                Button {
                    sheet = .results(detail)
                } label: {
                    Label(detail.results.isEmpty ? "Add Results" : "Edit Results", systemImage: "list.number")
                }
                Button {
                    sheet = .photos(detail)
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    sheet = .edit(detail)
                } label: {
                    Label("Edit \(labels.appearance)", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .accessibilityLabel("Actions for \(detail.entry.name)")
        }
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
