import SwiftUI
import SwiftData

/// The relationships a person is in, edited in place. Online only, like the membership screens: the server owns the graph and words every label from it, so there is nothing useful to show for an edit it has not accepted yet.
/// Two lists, because they are two different things. A **stated** row is one somebody typed and is the only kind there is anything to remove — the edge behind it is what every other label is derived from. An **implied** row is the graph answering: the siblings that follow from a shared parent, a grandmother two parent edges up. Showing only the first reads as "the siblings aren't recorded" when they always were; offering to remove the second would mean nothing, since there is no row to delete.
struct PersonRelationsSection: View {
    let personId: Int
    let personName: String
    /// Everyone else the anchor picker can offer, already narrowed to people the server knows about.
    let candidates: [Person]

    /// The stored edges, as the last pull left them. Only used to work out which co-anchors to offer — the labels beside them are always the server's.
    @Query private var relations: [PersonRelation]

    /// Pulled after a write so the suggestions, and the roster's generation bands, reflect the edge that was just stated. `GetPersonRelations` answers with labels rather than edges, so the graph itself only arrives with a sync.
    @Environment(SyncService.self) private var syncService: SyncService?

    @State private var graph: GetPersonRelationsResponseDTO?
    @State private var pickedRelation: RelationOption?
    @State private var anchorId: UUID?
    @State private var coAnchorIds: [Int] = []
    @State private var errorMessage: String?
    @State private var isBusy = false

    private let service = PersonRelationService()

    private var anchor: Person? {
        candidates.first { $0.id == anchorId }
    }

    private var canAdd: Bool {
        !isBusy && pickedRelation != nil && anchorRemoteId != nil
    }

    private var anchorRemoteId: Int? {
        anchor?.remoteId.flatMap(Int.init)
    }

    private var statedRows: [RelationViewDTO] {
        graph?.relations.filter(\.stored) ?? []
    }

    private var impliedRows: [RelationViewDTO] {
        graph?.relations.filter { !$0.stored } ?? []
    }

    private var coAnchorSuggestions: [CoAnchorSuggestion] {
        guard let stated = pickedRelation?.stated, let anchorRemoteId else { return [] }
        return RelationGraph.coAnchorSuggestions(
            relations.map(\.edge),
            stated: stated,
            personId: personId,
            anchorId: anchorRemoteId
        )
    }

    var body: some View {
        let suggestions = coAnchorSuggestions

        Group {
            content(suggestions: suggestions)
        }
        .task(id: personId) { await load() }
        // A tick survives a redraw but must not survive the question changing: reset when the word, the anchor, or who is on offer moves. Watched from here rather than recomputed in `body`, which would be a write during view evaluation.
        .onChange(of: CoAnchorPicker.suggestionKey(
            stated: pickedRelation?.stated,
            anchorId: anchorRemoteId ?? 0,
            suggestions: suggestions
        )) { _, _ in
            coAnchorIds = CoAnchorPicker.defaultSelection(coAnchorSuggestions)
        }
    }

    @ViewBuilder
    private func content(suggestions: [CoAnchorSuggestion]) -> some View {
        Section {
            if let graph {
                if statedRows.isEmpty {
                    Text("Nobody is recorded as related to \(personName) yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(statedRows) { relation in
                        statedRow(relation, manageable: graph.manageable)
                    }
                }

                if graph.manageable && !candidates.isEmpty {
                    addControls(suggestions: suggestions)
                }
            } else if errorMessage == nil {
                ProgressView()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Relationships")
        } footer: {
            Text("Everyone else's relationship is worked out from these — a grandchild is the daughter or son of one of your children.")
        }

        if !impliedRows.isEmpty {
            Section {
                ForEach(impliedRows) { relation in
                    impliedRow(relation)
                }
            } header: {
                Text("Worked out from the above")
            } footer: {
                Text("Nothing to enter for these, and nothing to remove — they follow from the relationships you stated.")
            }
        }
    }

    private func statedRow(_ relation: RelationViewDTO, manageable: Bool) -> some View {
        HStack {
            relationLabel(relation)

            if manageable {
                Spacer()
                Button("Remove") {
                    Task { await remove(relation) }
                }
                // Without this the whole row becomes one tap target and every button in it fires together.
                .buttonStyle(.borderless)
                .disabled(isBusy)
            }
        }
    }

    private func impliedRow(_ relation: RelationViewDTO) -> some View {
        HStack {
            relationLabel(relation)
            Spacer()
            Text("implied")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func relationLabel(_ relation: RelationViewDTO) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(relation.personName)
            Text("\(personName)'s \(relation.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func addControls(suggestions: [CoAnchorSuggestion]) -> some View {
        Picker("Is the", selection: $pickedRelation) {
            Text("Pick one").tag(RelationOption?.none)
            ForEach(RelationOption.all) { option in
                Text(option.label).tag(RelationOption?.some(option))
            }
        }

        Picker("Of", selection: $anchorId) {
            ForEach(candidates, id: \.id) { person in
                Text(person.name).tag(UUID?.some(person.id))
            }
        }
        .disabled(pickedRelation == nil)

        CoAnchorPicker(
            suggestions: suggestions,
            people: candidates,
            relationLabel: pickedRelation?.label ?? "",
            disabled: isBusy,
            selectedIds: $coAnchorIds
        )

        Button("Add Relationship") {
            Task { await add() }
        }
        .buttonStyle(.borderless)
        .disabled(!canAdd)
    }

    private func load() async {
        if anchorId == nil {
            anchorId = candidates.first?.id
        }
        do {
            graph = try await service.relations(personId: personId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add() async {
        guard let stated = pickedRelation?.stated, let anchorId = anchorRemoteId else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            graph = try await service.addRelation(
                personId: personId,
                anchorId: anchorId,
                stated: stated,
                additionalAnchorIds: coAnchorIds
            )
            pickedRelation = nil
            coAnchorIds = []
            errorMessage = nil
            await syncService?.pullFamilyData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ relation: RelationViewDTO) async {
        isBusy = true
        defer { isBusy = false }

        do {
            graph = try await service.removeRelation(relationId: relation.relationId)
            errorMessage = nil
            await syncService?.pullFamilyData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
