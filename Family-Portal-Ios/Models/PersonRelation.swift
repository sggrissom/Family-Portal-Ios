import Foundation
import SwiftData

/// One stored edge of the family graph — `Relation` in backend/relation.go. Held locally because the roster groups itself by generation, and a group that only forms once the network answers would reshuffle the screen on every launch.
/// The ends are *server* ids rather than SwiftData relationships, the way a photo's tag ids are: the graph is the server's to own, edges arrive and vanish as a set on every pull, and a person still uploading has no server id to be an end of yet.
@Model
final class PersonRelation {
    var id: UUID = UUID()
    var remoteId: String? = nil

    /// For `.parent` this is the parent. For `.sibling` and `.partner` the direction carries no meaning — the edge was stored in whichever direction somebody happened to state it.
    var fromId: Int
    var toId: Int
    var kind: RelationKind

    init(remoteId: String? = nil, fromId: Int, toId: Int, kind: RelationKind) {
        self.id = UUID()
        self.remoteId = remoteId
        self.fromId = fromId
        self.toId = toId
        self.kind = kind
    }
}

/// The same edge as a plain value, which is what the graph walks. `RelationGraph` and `FamilyGroups` take these rather than the `@Model` so they can be reasoned about — and tested — without a `ModelContainer`.
nonisolated struct RelationEdge: Equatable, Hashable, Sendable {
    let id: Int
    let fromId: Int
    let toId: Int
    let kind: RelationKind

    nonisolated init(id: Int = 0, fromId: Int, toId: Int, kind: RelationKind) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.kind = kind
    }
}

extension PersonRelation {
    var edge: RelationEdge {
        RelationEdge(
            id: remoteId.flatMap(Int.init) ?? 0,
            fromId: fromId,
            toId: toId,
            kind: kind
        )
    }
}
