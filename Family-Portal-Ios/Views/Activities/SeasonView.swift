import SwiftUI
import SwiftData

/// One season: its competitions and its routines, side by side.
/// `GetSeasonOverview` ships each event and each entry once and the appearances as the bare hinge; the join is done here on `entryId` and `eventId`, exactly as the web does it.
struct SeasonView: View {
    let seasonId: Int
    /// Carried in so the title is right before the payload lands.
    let seasonName: String

    @Environment(ActivityService.self) private var service
    @Query private var people: [Person]

    @State private var state = ActivityScreenState<GetSeasonOverviewResponseDTO>()
    @State private var vocabulary = ActivityScreenState<ListActivityVocabularyResponseDTO>()
    @State private var sheet: Sheet?

    /// One slot, because SwiftUI presents a single sheet per view and several bindings on the same node race each other.
    private enum Sheet: Identifiable {
        case addEvent
        case editEvent(ActivityEventDTO)
        case addEntry
        case editEntry(EntryViewDTO)

        var id: String {
            switch self {
            case .addEvent: return "event-new"
            case .editEvent(let event): return "event-\(event.id)"
            case .addEntry: return "entry-new"
            case .editEntry(let entry): return "entry-\(entry.id)"
            }
        }
    }

    private var labels: ActivityLabels {
        ActivityLabels.forKind(state.value?.activity.kind ?? ActivityKind.generic)
    }

    var body: some View {
        ActivityScreen(state: state, read: { service.seasonOverview(seasonId: seasonId) }) { response in
            content(response)
        }
        .navigationTitle(state.value?.season.name ?? seasonName)
        .navigationBarTitleDisplayMode(.inline)
        // Nothing normalizes these fields at write time, so without autocomplete a season ends up with "Jazz", "jazz" and "JAZZ" as three different styles.
        .task(id: state.value?.activity.id) {
            guard let activityId = state.value?.activity.id else { return }
            await vocabulary.load(service.vocabulary(activityId: activityId))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        sheet = .addEvent
                    } label: {
                        Label("Add \(labels.event)", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        sheet = .addEntry
                    } label: {
                        Label("Add \(labels.entry)", systemImage: "music.note.list")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(state.value == nil)
                .accessibilityLabel("Add to this season")
            }
        }
        .sheet(item: $sheet) { presented in
            switch presented {
            case .addEvent:
                CompetitionEditorView(
                    seasonId: seasonId,
                    labels: labels,
                    hostSuggestions: vocabulary.value?.hosts ?? [],
                    onSaved: { await state.reload() }
                )
            case .editEvent(let event):
                CompetitionEditorView(
                    seasonId: seasonId,
                    existing: event,
                    labels: labels,
                    hostSuggestions: vocabulary.value?.hosts ?? [],
                    onSaved: { await state.reload() }
                )
            case .addEntry:
                RoutineEditorView(
                    seasonId: seasonId,
                    labels: labels,
                    vocabulary: vocabulary.value,
                    onSaved: { await state.reload() }
                )
            case .editEntry(let entry):
                RoutineEditorView(
                    seasonId: seasonId,
                    existing: entry,
                    labels: labels,
                    vocabulary: vocabulary.value,
                    onSaved: { await state.reload() }
                )
            }
        }
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
                            HStack {
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

                                editButton(for: event.name) { sheet = .editEvent(event) }
                            }
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
                            HStack {
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

                                editButton(for: entryView.entry.name) { sheet = .editEntry(entryView) }
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
                .accessibilityHidden(true)
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
                .accessibilityHidden(true)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }

    private func editButton(for name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(name)")
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
