import SwiftUI
import SwiftData

struct CompetitionView: View {
    let eventId: Int
    let eventName: String

    @Environment(ActivityService.self) private var service
    @Environment(AuthService.self) private var authService
    @Query private var people: [Person]

    @State private var state = ActivityScreenState<GetEventDetailResponseDTO>()
    @State private var seasonState = ActivityScreenState<GetSeasonOverviewResponseDTO>()

    /// One sheet slot rather than several `.sheet` modifiers: SwiftUI presents one sheet per view, and several `isPresented` bindings on the same node race each other.
    private enum AppearanceSheet: Identifiable {
        /// A new performance, of this routine when one is given.
        case record(entryId: Int?)
        case performance(AppearanceDetailDTO)
        case editEvent
        case eventPhotos

        var id: String {
            switch self {
            case .record(let entryId): return "record-\(entryId ?? 0)"
            case .performance(let detail): return "performance-\(detail.id)"
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

    /// A view-only member of the event's family sees it with no actions, as on the web.
    private var editable: Bool {
        guard let event = state.value?.event else { return false }
        return authService.access.canContribute(event.familyId)
    }

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
            if editable {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            sheet = .record(entryId: nil)
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
                    .accessibilityLabel("\(labels.event) actions")
                }
            }
        }
        .sheet(item: $sheet) { presented in
            switch presented {
            case .record(let entryId):
                performanceEditor(existing: nil, entryId: entryId)
            case .performance(let detail):
                performanceEditor(existing: detail, entryId: nil)
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
            }
        }
    }

    private func performanceEditor(existing: AppearanceDetailDTO?, entryId: Int?) -> some View {
        PerformanceEditorView(
            eventId: eventId,
            existing: existing,
            entryId: entryId,
            entries: seasonState.value?.entries ?? [],
            activityId: seasonState.value?.activity.id,
            activityKind: state.value?.season.kind ?? ActivityKind.generic,
            labels: labels,
            onSaved: { await state.reload() }
        )
    }

    @ViewBuilder
    private func content(_ response: GetEventDetailResponseDTO) -> some View {
        // The season summary carries the activity's kind; without it the screen renders "Event", the one word the label map exists to avoid.
        let labels = ActivityLabels.forKind(response.season.kind)
        let people = ActivityPeople(self.people)

        VStack(spacing: 16) {
            header(response, labels: labels)

            ForEach(cards(response)) { card in
                routineCard(card, labels: labels, people: people)
            }

            if response.appearances.isEmpty && (!editable || cards(response).isEmpty) {
                Text("No \(labels.appearancePlural.lowercased()) recorded yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }

    /// A card for every routine in the season, recorded or not, so a weekend's results are entered from here rather than by adding each performance first. Routines the season no longer lists still show when they have performances here.
    private struct RoutineCard: Identifiable {
        let entryId: Int
        let name: String
        let appearances: [AppearanceDetailDTO]
        var id: Int { entryId }
    }

    private func cards(_ response: GetEventDetailResponseDTO) -> [RoutineCard] {
        let byEntry = Dictionary(grouping: response.appearances) { $0.entry.id }
        var cards = (seasonState.value?.entries ?? []).map { view in
            RoutineCard(entryId: view.entry.id, name: view.entry.name, appearances: byEntry[view.entry.id] ?? [])
        }
        let listed = Set(cards.map(\.entryId))
        for run in Matchups.group(response.appearances, by: { $0.entry.id }) {
            guard let first = run.first, !listed.contains(first.entry.id) else { continue }
            cards.append(RoutineCard(entryId: first.entry.id, name: first.entry.name, appearances: run))
        }
        return cards
    }

    @ViewBuilder
    private func routineCard(_ card: RoutineCard, labels: ActivityLabels, people: ActivityPeople) -> some View {
        if card.appearances.isEmpty {
            if editable {
                Button {
                    sheet = .record(entryId: card.entryId)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.name)
                                .font(.headline)
                            Text("Not recorded yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("Record results", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(.secondary)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    // An entry's rounds stay together, under how its run went.
                    let summary = card.appearances.count > 1 ? Matchups.runSummary(card.appearances.map { Matchup($0.appearance) }) : ""
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline.weight(.semibold))
                    }
                    ForEach(card.appearances) { detail in
                        appearanceRow(detail, people: people)
                        if detail.id != card.appearances.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    private func appearanceRow(_ detail: AppearanceDetailDTO, people: ActivityPeople) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                NavigationLink {
                    RoutineView(entryId: detail.entry.id, entryName: detail.entry.name)
                } label: {
                    AppearanceDetailRow(
                        detail: detail,
                        people: people,
                        title: .entry,
                        showsChevron: true,
                        showsPhotos: false
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if editable {
                    Button {
                        sheet = .performance(detail)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(detail.results.isEmpty ? "Record results for \(detail.entry.name)" : "Edit results for \(detail.entry.name)")
                }
            }

            ActivityPhotoStrip(photoIds: detail.photoIds)
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
