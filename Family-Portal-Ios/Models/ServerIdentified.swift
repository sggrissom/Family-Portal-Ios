import Foundation

/// A record the server also holds. `remoteId` stays a string because that is how the store was first written, but every server id is an integer: read and write it as one through `serverId`.
protocol ServerIdentified: AnyObject {
    var remoteId: String? { get set }
}

extension ServerIdentified {
    /// The server's id for this record, or `nil` until it has synced.
    var serverId: Int? {
        get { remoteId.flatMap(Int.init) }
        set { remoteId = newValue.map(String.init) }
    }
}

extension Sequence where Element: ServerIdentified {
    /// Keyed by server id, for resolving many ids against one fetch: a `first(where:)` per id is a scan of every stored record for each row drawn.
    func byServerId() -> [Int: Element] {
        var index: [Int: Element] = [:]
        for record in self {
            if let id = record.serverId, index[id] == nil {
                index[id] = record
            }
        }
        return index
    }
}

extension Family: ServerIdentified {}
extension Person: ServerIdentified {}
extension PersonRelation: ServerIdentified {}
extension GrowthData: ServerIdentified {}
extension Milestone: ServerIdentified {}
extension Photo: ServerIdentified {}
extension FamilyTag: ServerIdentified {}
extension User: ServerIdentified {}
extension ChatMessage: ServerIdentified {}
