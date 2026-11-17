import Foundation
import SwiftData

// The activity records competition result entry writes to on this phone, and the outbox that carries those writes to the server. Kept in their own store (`ActivityLocalStore`), apart from the family store: a write here must be durable before the editor closes, and an activity store that fails to open must never take the family's records down with it.
//
// Every row carries the account (`ownerUserId`) and family it belongs to. Nothing here is shown to, or sent as, another account.

/// One performance as this phone knows it: the server's copy, or a local change to it that has not reached the server yet.
/// Identified by `localId`, never by competition and routine: two performances of one routine at one competition are legitimate (rounds), and a performance created offline has no server id until its create is acknowledged.
@Model
final class LocalPerformance {
    @Attribute(.unique) var localId: UUID
    var ownerUserId: Int
    var familyId: Int
    /// `nil` until the server has acknowledged the create.
    var serverId: Int?
    var eventId: Int
    var entryId: Int

    /// The whole performance: `PerformanceSnapshot`, encoded. One blob rather than columns so the record and its results sheet are always written together.
    var snapshotData: Data

    /// The server revision this copy is based on: the one a local edit was made against, or the server's own copy's. 0 for a performance created here and not yet acknowledged.
    var serverRevision: Int
    /// Bumped by every local save or delete.
    var localGeneration: Int
    /// The newest local generation the server has acknowledged. A performance with `localGeneration > acknowledgedGeneration` has changes the server has not seen, and a pull never overwrites it.
    var acknowledgedGeneration: Int
    /// Deleted on this phone. Not `isDeleted`, which `PersistentModel` already uses for "deleted from its context". Kept as a tombstone until the server acknowledges the delete, so a pull cannot bring it back.
    var isLocallyDeleted: Bool
    /// When the server last told this phone about this performance — a pull or an acknowledgement. A pull that began before then is older than what the phone already has.
    var serverUpdatedAt: Date?
    var createdAt: Date

    init(
        localId: UUID = UUID(),
        ownerUserId: Int,
        familyId: Int,
        serverId: Int?,
        eventId: Int,
        entryId: Int,
        snapshot: PerformanceSnapshot,
        serverRevision: Int,
        createdAt: Date = Date()
    ) {
        self.localId = localId
        self.ownerUserId = ownerUserId
        self.familyId = familyId
        self.serverId = serverId
        self.eventId = eventId
        self.entryId = entryId
        self.snapshotData = (try? PerformanceSnapshot.encoder.encode(snapshot)) ?? Data()
        self.serverRevision = serverRevision
        self.localGeneration = 0
        self.acknowledgedGeneration = 0
        self.isLocallyDeleted = false
        self.serverUpdatedAt = nil
        self.createdAt = createdAt
    }

    var hasUnsyncedChanges: Bool {
        localGeneration > acknowledgedGeneration
    }

    /// `nil` only for a row this build cannot read, which is kept rather than shown as an empty sheet.
    var snapshot: PerformanceSnapshot? {
        try? PerformanceSnapshot.decoder.decode(PerformanceSnapshot.self, from: snapshotData)
    }

    func setSnapshot(_ snapshot: PerformanceSnapshot) throws {
        snapshotData = try PerformanceSnapshot.encoder.encode(snapshot)
    }
}

/// A local save or delete waiting to reach the server. Written in the same transaction as the change to its `LocalPerformance`, so there is never a saved change with no way to send it, nor an outbox entry for a change that was rolled back.
@Model
final class ActivityOutboxMutation {
    /// Also the mutation id the server deduplicates on: a retry of this entry, however late, can never apply twice.
    @Attribute(.unique) var id: UUID
    var ownerUserId: Int
    var familyId: Int
    var performanceLocalId: UUID
    /// `ActivityMutationKind`'s raw value.
    var kindRaw: String
    /// For a save, the performance as it was saved (`PerformanceSnapshot`). Never changed once `sentRequest` is set.
    var snapshotData: Data?
    /// The performance's `localGeneration` this entry carries.
    var generation: Int
    /// The revision an edit or delete is made against. `nil` while it depends on an earlier entry not yet acknowledged — a create, say — which supplies it.
    var expectedRevision: Int?
    /// The entry this one must wait for: the previous one for the same performance, so they reach the server in order.
    var dependsOnMutationId: UUID?
    /// `ActivityMutationStatus`'s raw value.
    var statusRaw: String
    /// The exact request body, fixed just before the first attempt and resent byte for byte after that: the server binds the mutation id to it.
    var sentRequest: Data?
    var attemptCount: Int
    var nextAttemptAt: Date?
    /// What the last attempt reported, for the sync status view. Never award text or other family content.
    var lastOutcome: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        ownerUserId: Int,
        familyId: Int,
        performanceLocalId: UUID,
        kind: ActivityMutationKind,
        snapshotData: Data?,
        generation: Int,
        expectedRevision: Int?,
        dependsOnMutationId: UUID?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerUserId = ownerUserId
        self.familyId = familyId
        self.performanceLocalId = performanceLocalId
        self.kindRaw = kind.rawValue
        self.snapshotData = snapshotData
        self.generation = generation
        self.expectedRevision = expectedRevision
        self.dependsOnMutationId = dependsOnMutationId
        self.statusRaw = ActivityMutationStatus.pending.rawValue
        self.sentRequest = nil
        self.attemptCount = 0
        self.nextAttemptAt = nil
        self.lastOutcome = nil
        self.createdAt = createdAt
    }

    var kind: ActivityMutationKind? { ActivityMutationKind(rawValue: kindRaw) }

    var status: ActivityMutationStatus {
        get { ActivityMutationStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// Whether this entry may still have reached the server. Once it might have, its contents are fixed and it cannot simply be dropped.
    var mayHaveBeenSent: Bool {
        sentRequest != nil || attemptCount > 0
    }
}

nonisolated enum ActivityMutationKind: String, Sendable {
    case save
    case delete
}

nonisolated enum ActivityMutationStatus: String, Sendable {
    /// Waiting to be sent, or to be retried.
    case pending
    /// Paused until someone signs in again.
    case needsSignIn
    /// The server's copy changed first; kept until someone reviews it.
    case needsReview
    /// Refused for its contents, or by permission; kept until someone acts on it.
    case failed
}

/// A competition downloaded for result entry without a connection: which reads it needs are on the phone. The reads themselves are in `ActivitySnapshotCache`.
@Model
final class PreparedCompetition {
    /// `"<ownerUserId>:<eventId>"`.
    @Attribute(.unique) var key: String
    var ownerUserId: Int
    var familyId: Int
    var eventId: Int
    var seasonId: Int
    var activityId: Int?
    var hasEventDetail: Bool
    var hasSeasonOverview: Bool
    var hasVocabulary: Bool
    /// Whether this account could add results here when it was downloaded.
    var canContribute: Bool
    var preparedAt: Date?
    var lastAttemptAt: Date

    init(ownerUserId: Int, eventId: Int) {
        self.key = Self.key(ownerUserId: ownerUserId, eventId: eventId)
        self.ownerUserId = ownerUserId
        self.familyId = 0
        self.eventId = eventId
        self.seasonId = 0
        self.activityId = nil
        self.hasEventDetail = false
        self.hasSeasonOverview = false
        self.hasVocabulary = false
        self.canContribute = false
        self.preparedAt = nil
        self.lastAttemptAt = Date()
    }

    static func key(ownerUserId: Int, eventId: Int) -> String {
        "\(ownerUserId):\(eventId)"
    }

    /// Everything result entry needs is on the phone. Short of this the competition is shown as incomplete, never as one with no results.
    var isComplete: Bool {
        hasEventDetail && hasSeasonOverview && hasVocabulary
    }
}

/// A whole performance — everything `SaveAppearance` writes — as stored locally and queued.
nonisolated struct PerformanceSnapshot: Codable, Sendable, Equatable {
    var occurredAt: Date?
    var notes: String
    /// `nil` when no head-to-head was recorded.
    var matchup: MatchupInputDTO?
    var results: [LocalResultRow]
    /// Existing server photo ids, kept as they are: uploading new media offline is later work.
    var photoIds: [Int]

    /// Sorted keys, so the same snapshot always encodes to the same bytes.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    static var decoder: JSONDecoder { JSONDecoder() }
}

/// One result row with an identity that survives edits, so a row being edited is never mistaken for another.
nonisolated struct LocalResultRow: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    /// The server's id for the row this came from, when it came from the server.
    var serverId: Int?
    var input: ResultInputDTO
}
