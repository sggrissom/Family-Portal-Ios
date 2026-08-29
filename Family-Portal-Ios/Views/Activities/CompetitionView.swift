import SwiftUI
import SwiftData

struct CompetitionView: View {
    let eventId: Int
    let eventName: String

    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var state = ActivityScreenState<GetEventDetailResponseDTO>()
    @State private var seasonState = ActivityScreenState<GetSeasonOverviewResponseDTO>()

    /// One sheet slot rather than four `.sheet` modifiers: SwiftUI presents one sheet per view, and several `isPresented` bindings on the same node race each other.
    private enum AppearanceSheet: Identifiable {
        case add
        case edit(AppearanceDetailDTO)
        case results(AppearanceDetailDTO)
        case photos(AppearanceDetailDTO)
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

    @Environment(\.dismiss) private var dismiss

    private var labels: ActivityLabels {
        ActivityLabels.forKind(state.value?.season.kind ?? ActivityKind.generic)
    }

    private var canWrite: Bool { seasonState.value != nil }

    var body: some View {
        ActivityScreen(state: state, read: { service.eventDetail(eventId: eventId) }) { response in
            content(response)
        }
        .navigationTitle(state.value?.event.name ?? eventName)
        .navigationBarTitleDisplayMode(.inline)
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

    private func roster(forEntry entryId: Int) -> [Int] {
        seasonState.value?.entries.first { $0.entry.id == entryId }?.personIds ?? []
    }

    @ViewBuilder
    private func content(_ response: GetEventDetailResponseDTO) -> some View {
        // The season summary carries the activity's kind; without it the screen renders "Event", the one word the label map exists to avoid.
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

                ActivityPhotoStrip(photoIds: response.photoIds)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
