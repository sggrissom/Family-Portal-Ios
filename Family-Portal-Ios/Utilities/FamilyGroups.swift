import Foundation

/// One band of the roster — a generation, or the people no stated relationship reaches.
struct PersonGroup: Identifiable {
    let key: String
    let title: String
    let people: [Person]

    var id: String { key }
}

/// Lays the household out generation by generation from the stated edges, mirroring frontend/lib/familyGroups.ts so the phone and the dashboard band a family the same way.
/// Generations are read off the *bottom* of the tree: whoever is youngest present is always "Children" and whoever is above them are their parents. Reading from the top would rename every band the moment a grandparent was added.
enum FamilyGroups {
    // Indexed by how far above the youngest generation a band sits.
    private static let generationTitles = ["Children", "Parents", "Grandparents", "Great-grandparents"]
    private static let olderTitle = "Earlier generations"
    private static let loneGenerationTitle = "Family"
    private static let unlinkedTitle = "Not linked yet"

    /// Oldest generation first, so parents come before their children. People no relationship reaches go last, since nothing says where they belong — that includes anyone added offline, who has no server id to be an end of an edge yet.
    static func group(people: [Person], relations: [RelationEdge]) -> [PersonGroup] {
        var byId: [Int: Person] = [:]
        for person in people {
            if let remoteId = person.remoteId.flatMap(Int.init) {
                byId[remoteId] = person
            }
        }

        let edges = relations.filter { byId[$0.fromId] != nil && byId[$0.toId] != nil }

        var linkedIds = Set<Int>()
        for edge in edges {
            linkedIds.insert(edge.fromId)
            linkedIds.insert(edge.toId)
        }

        var linked: [Int] = []
        var unlinked: [Person] = []
        for person in people {
            if let remoteId = person.remoteId.flatMap(Int.init), linkedIds.contains(remoteId) {
                linked.append(remoteId)
            } else {
                unlinked.append(person)
            }
        }
        unlinked.sort { isOlder($0, $1) }

        let depths = generationDepths(of: linked, edges: edges)
        var generations: [Int: [Int]] = [:]
        for personId in linked {
            generations[depths[personId] ?? 0, default: []].append(personId)
        }
        let deepest = generations.keys.max() ?? 0

        var groups: [PersonGroup] = []
        // Where a generation's members sit in the band above, so the one below can follow their parents.
        var placed: [Int: Int] = [:]
        for depth in generations.keys.sorted() {
            let ordered = orderGeneration(generations[depth]!, edges: edges, placed: placed, byId: byId)
            for personId in ordered {
                placed[personId] = placed.count
            }
            groups.append(PersonGroup(
                key: "generation-\(depth)",
                title: title(depth: depth, deepest: deepest),
                people: ordered.compactMap { byId[$0] }
            ))
        }

        if !unlinked.isEmpty {
            groups.append(PersonGroup(key: "unlinked", title: unlinkedTitle, people: unlinked))
        }
        return groups
    }

    /// Places everyone one step below their parents, and level with their partners and siblings, by relaxing those three rules until they hold. Passes are capped at the number of people so a parent cycle still terminates.
    private static func generationDepths(of people: [Int], edges: [RelationEdge]) -> [Int: Int] {
        var depths = [Int: Int](uniqueKeysWithValues: people.map { ($0, 0) })

        for _ in 0..<people.count {
            var changed = false
            for personId in people {
                var depth = depths[personId] ?? 0
                for parentId in RelationGraph.parents(edges, of: personId) {
                    depth = max(depth, (depths[parentId] ?? 0) + 1)
                }
                for peerId in RelationGraph.partners(edges, of: personId) {
                    depth = max(depth, depths[peerId] ?? 0)
                }
                for peerId in RelationGraph.siblings(edges, of: personId) {
                    depth = max(depth, depths[peerId] ?? 0)
                }
                if depth > (depths[personId] ?? 0) {
                    depths[personId] = depth
                    changed = true
                }
            }
            if !changed { break }
        }
        return depths
    }

    /// Lists a generation under the parents it belongs to: everyone follows whoever came first among their parents, and partners stay side by side.
    private static func orderGeneration(
        _ members: [Int],
        edges: [RelationEdge],
        placed: [Int: Int],
        byId: [Int: Person]
    ) -> [Int] {
        func parentRank(_ personId: Int) -> Int {
            RelationGraph.parents(edges, of: personId)
                .reduce(Int.max) { rank, parentId in min(rank, placed[parentId] ?? Int.max) }
        }

        let memberSet = Set(members)
        let sorted = members.sorted { left, right in
            let leftRank = parentRank(left)
            let rightRank = parentRank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            guard let leftPerson = byId[left], let rightPerson = byId[right] else { return left < right }
            return isOlder(leftPerson, rightPerson)
        }

        var ordered: [Int] = []
        var seen = Set<Int>()
        for personId in sorted {
            guard !seen.contains(personId) else { continue }
            seen.insert(personId)
            ordered.append(personId)
            for partnerId in RelationGraph.partners(edges, of: personId)
            where memberSet.contains(partnerId) && !seen.contains(partnerId) {
                seen.insert(partnerId)
                ordered.append(partnerId)
            }
        }
        return ordered
    }

    private static func title(depth: Int, deepest: Int) -> String {
        guard deepest != 0 else { return loneGenerationTitle }
        let stepsAboveTheYoungest = deepest - depth
        return generationTitles.indices.contains(stepsAboveTheYoungest)
            ? generationTitles[stepsAboveTheYoungest]
            : olderTitle
    }

    /// Oldest first. A person with no birthday sorts last, then by name so the order is stable.
    static func isOlder(_ left: Person, _ right: Person) -> Bool {
        switch (left.birthday, right.birthday) {
        case let (leftBirthday?, rightBirthday?):
            if leftBirthday != rightBirthday { return leftBirthday < rightBirthday }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        case (nil, nil):
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        }
    }
}

extension Person {
    /// The household, oldest first, ungrouped. Kept for the places that want a plain list — `FamilyGroups.group` is what the roster renders.
    static func roster(in people: [Person]) -> [Person] {
        people.sorted { FamilyGroups.isOlder($0, $1) }
    }
}
