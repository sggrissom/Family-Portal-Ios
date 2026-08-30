import Foundation

/// Walks the stored edges the way frontend/lib/relations.ts does, so both clients answer the same questions from the same graph.
/// Deliberately narrow: this names *neighbours*, never relationships. "Grandmother" and "cousin" are the server's to word (backend/relation_label.go) — a client that derived them would disagree with the labels beside them on the same screen.
nonisolated enum RelationGraph {
    /// Everyone joined to `personId` by a symmetric edge of this kind, in either direction.
    private static func peers(_ edges: [RelationEdge], _ personId: Int, _ kind: RelationKind) -> [Int] {
        var ids: [Int] = []
        for edge in edges where edge.kind == kind {
            if edge.fromId == personId {
                ids.append(edge.toId)
            } else if edge.toId == personId {
                ids.append(edge.fromId)
            }
        }
        return ids
    }

    static func partners(_ edges: [RelationEdge], of personId: Int) -> [Int] {
        peers(edges, personId, .partner)
    }

    static func parents(_ edges: [RelationEdge], of personId: Int) -> [Int] {
        edges.filter { $0.kind == .parent && $0.toId == personId }.map(\.fromId)
    }

    static func children(_ edges: [RelationEdge], of personId: Int) -> [Int] {
        edges.filter { $0.kind == .parent && $0.fromId == personId }.map(\.toId)
    }

    /// Mirrors the backend: siblings stated outright plus those sharing a parent.
    /// Stated sibling edges are *not* transitive — A–B and B–C does not make A–C, because half-siblings break that — so this walks one step and stops.
    static func siblings(_ edges: [RelationEdge], of personId: Int) -> [Int] {
        var seen: Set<Int> = [personId]
        var ids: [Int] = []
        func add(_ id: Int) {
            guard !seen.contains(id) else { return }
            seen.insert(id)
            ids.append(id)
        }
        peers(edges, personId, .sibling).forEach(add)
        for parentId in parents(edges, of: personId) {
            children(edges, of: parentId).forEach(add)
        }
        return ids
    }

    static func hasStatedRelation(
        _ edges: [RelationEdge],
        stated: StatedRelation,
        personId: Int,
        anchorId: Int
    ) -> Bool {
        switch stated {
        case .child:
            return children(edges, of: anchorId).contains(personId)
        case .parent:
            return parents(edges, of: anchorId).contains(personId)
        case .sibling:
            return siblings(edges, of: anchorId).contains(personId)
        case .partner:
            return partners(edges, of: anchorId).contains(personId)
        case .none:
            return false
        }
    }
}

/// One more person the same stated relation probably also applies to.
nonisolated struct CoAnchorSuggestion: Identifiable, Equatable, Sendable {
    let anchorId: Int
    /// Whether to tick it without being asked. Only the single-partner co-parent case earns that; anything else is a guess the user should make.
    let defaultChecked: Bool

    var id: Int { anchorId }
}

extension RelationGraph {
    /// The other people the same stated relation most likely also applies to: a child's other parent, or the siblings of whoever the relation was stated against.
    /// Nothing here is *inferred* — the checkboxes only offer, and every edge still has to be stated. Treating a partner's child as your own would be silent and unrefusable, and the step-family case is exactly where it is wrong.
    static func coAnchorSuggestions(
        _ edges: [RelationEdge],
        stated: StatedRelation,
        personId: Int,
        anchorId: Int
    ) -> [CoAnchorSuggestion] {
        guard anchorId != 0 else { return [] }

        let candidates: [Int]
        var defaultChecked = false

        switch stated {
        case .child:
            candidates = partners(edges, of: anchorId)
            // A single partner is the child's other parent often enough to preselect; more than one is ambiguous, so make the choice explicit.
            defaultChecked = candidates.count == 1
        case .parent, .sibling:
            candidates = siblings(edges, of: anchorId)
        case .partner, .none:
            return []
        }

        return candidates
            .filter { $0 != personId && $0 != anchorId }
            .filter { !hasStatedRelation(edges, stated: stated, personId: personId, anchorId: $0) }
            .map { CoAnchorSuggestion(anchorId: $0, defaultChecked: defaultChecked) }
    }
}
