import SwiftUI

/// The relationships a person is stated to be in, edited in place. Online only, like the membership screens: the server owns the graph and words every label from it, so there is nothing useful to show for an edit it has not accepted yet.
/// Only stated edges appear here. A grandmother or a cousin is the server walking two of these outward, and removing one of *those* would mean nothing — the edge to remove is always one somebody typed.
struct PersonRelationsSection: View {
    let personId: Int
    let personName: String
    /// Everyone else the anchor picker can offer, already narrowed to people the server knows about.
    let candidates: [Person]

    @State private var graph: GetPersonRelationsResponseDTO?
    @State private var pickedRelation: RelationOption?
    @State private var anchorId: UUID?
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

    var body: some View {
        Section {
            if let graph {
                if graph.relations.isEmpty {
                    Text("Nobody is recorded as related to \(personName) yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(graph.relations) { relation in
                        relationRow(relation, manageable: graph.manageable)
                    }
                }

                if graph.manageable && !candidates.isEmpty {
                    addControls
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
        .task(id: personId) { await load() }
    }

    private func relationRow(_ relation: RelationViewDTO, manageable: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(relation.personName)
                Text("\(personName)'s \(relation.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    @ViewBuilder
    private var addControls: some View {
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
                stated: stated
            )
            pickedRelation = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ relation: RelationViewDTO) async {
        isBusy = true
        defer { isBusy = false }

        do {
            graph = try await service.removeRelation(relationId: relation.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
