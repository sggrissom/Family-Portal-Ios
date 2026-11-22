import Foundation

// Recap links (backend/recap_links.go): an account-free page at /recap/<token>
// holding one approved competition recap. Online only, never queued.

nonisolated struct RecapResultDTO: Codable, Sendable, Equatable {
    let kind: String
    let text: String
    let detail: String
}

nonisolated struct RecapPerformanceInputDTO: Encodable, Sendable, Equatable {
    let appearanceId: Int
    let revision: Int
    let when: String
    let matchup: String
    let results: [RecapResultDTO]
}

nonisolated struct RecapRoutineInputDTO: Encodable, Sendable, Equatable {
    let entryId: Int
    let name: String
    let descriptors: String
    let roster: String
    let summary: String
    let performances: [RecapPerformanceInputDTO]
}

nonisolated struct RecapInputDTO: Encodable, Sendable, Equatable {
    let eventName: String
    let subtitle: String
    let place: String
    let snapshotLabel: String
    let routines: [RecapRoutineInputDTO]
}

nonisolated struct CreateRecapLinkRequestDTO: Encodable, Sendable {
    let eventId: Int
    let expiresInDays: Int
    let recap: RecapInputDTO
}

nonisolated struct RecapLinkDTO: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let createdAt: Date
    var expiresAt: Date? = nil
    let expired: Bool
    @OrZero var createdByName: String
    let canRevoke: Bool
    let routineCount: Int
    @OrZero var snapshotLabel: String
}

nonisolated struct CreateRecapLinkResponseDTO: Decodable, Sendable {
    let link: RecapLinkDTO
    /// The only copy of the link: the server keeps a hash of its token.
    let url: String
}

nonisolated struct ListRecapLinksRequestDTO: Encodable, Sendable {
    let eventId: Int
}

nonisolated struct ListRecapLinksResponseDTO: Decodable, Sendable {
    let links: [RecapLinkDTO]
}

nonisolated struct RevokeRecapLinkRequestDTO: Encodable, Sendable {
    let id: Int
}
