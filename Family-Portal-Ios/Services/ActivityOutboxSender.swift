import Foundation
import OSLog
import SwiftData

/// Whether the server takes queued results (`GetActivitySyncSupport`), remembered across launches so a phone that went offline after checking still knows. Result entry saves locally only for a server known to support it; for any other, it stays online-only and says so.
@Observable
@MainActor
final class ActivitySyncCapability {
    private static let storageKey = "com.familyrecord.activitySyncVersion"

    private let defaults: UserDefaults
    private var version: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        version = defaults.integer(forKey: Self.storageKey)
    }

    var isSupported: Bool {
        version == ActivityMutationContract.version
    }

    func record(version: Int) {
        self.version = version
        defaults.set(version, forKey: Self.storageKey)
    }
}

/// Sends the activity outbox (`ActivityLocalStore`) to the server, oldest first and one performance's changes in order, and applies what comes back. Driven by `SyncService.processQueue`, so it shares that loop's triggers — after a local save, on foreground, on reconnect, on pull to refresh — and never runs beside another pass of itself.
///
/// Nothing here throws work away. A dropped connection stops the pass with everything still queued; a transient server failure backs off; a conflict, a refusal, or a deleted target is kept as an entry needing someone's attention; an authentication failure pauses the queue until sign-in. Each request is fixed before its first attempt and resent unchanged, so a retry after a lost response is answered from the server's receipt instead of writing twice.
@MainActor
final class ActivityOutboxSender {

    static let shared = ActivityOutboxSender(store: .shared, apiClient: .shared)

    let store: ActivityLocalStore
    let apiClient: APIClient
    let capability: ActivitySyncCapability
    var now: () -> Date = Date.init
    /// Multiplies each backoff, so phones that failed together do not retry together.
    var jitter: () -> Double = { Double.random(in: 0.8...1.2) }

    static let baseBackoff: TimeInterval = 5
    static let maximumBackoff: TimeInterval = 60 * 60

    private var isDraining = false
    private var drainRequested = false
    /// Asked once per launch: a server does not lose support mid-session, and one that turns out not to have the procs after all is caught when a send reports them missing.
    private var supportConfirmed = false

    init(store: ActivityLocalStore, apiClient: APIClient, capability: ActivitySyncCapability? = nil) {
        self.store = store
        self.apiClient = apiClient
        self.capability = capability ?? ActivitySyncCapability()
    }

    nonisolated enum StopReason: Equatable, Sendable {
        case offline
        case unsupported
        case signedOut
        case storeUnavailable
    }

    /// Sends what is ready for `userId`. A drain asked for while one is running runs again after it rather than beside it.
    /// - Returns: why the pass stopped early, if it did.
    @discardableResult
    func drain(userId: Int, username: String) async -> StopReason? {
        if isDraining {
            drainRequested = true
            return nil
        }
        isDraining = true
        defer { isDraining = false }

        var stop: StopReason?
        repeat {
            drainRequested = false
            stop = await drainOnce(userId: userId, username: username)
        } while drainRequested && stop == nil
        return stop
    }

    private func drainOnce(userId: Int, username: String) async -> StopReason? {
        guard store.isDurable else { return .storeUnavailable }
        guard !store.mutations(userId: userId).isEmpty else { return nil }

        // Draining at all means someone is signed in.
        try? store.resumeAfterSignIn(userId: userId)

        if let stop = await checkSupport(username: username) {
            return stop
        }

        var sentSomething = true
        while sentSomething {
            sentSomething = false
            for mutation in store.mutations(userId: userId) where isReady(mutation) {
                switch await send(mutation, username: username) {
                case .stop(let reason):
                    return reason
                case .done:
                    sentSomething = true
                case .parked:
                    continue
                }
            }
        }
        return nil
    }

    // MARK: - Capability

    /// Probe after a live competition read, including on an install with an empty outbox.
    func checkSupport(username: String) async -> StopReason? {
        if supportConfirmed { return nil }
        do {
            let data = try await apiClient.callRPCData(
                .getActivitySyncSupport, payload: EmptyRequestDTO(), requiringUsername: username
            )
            let response = try APIClient.decodeResponse(ActivitySyncSupportResponseDTO.self, from: data)
            capability.record(version: response.mutationVersion)
            supportConfirmed = response.mutationVersion == ActivityMutationContract.version
            return supportConfirmed ? nil : .unsupported
        } catch {
            switch Self.classify(error) {
            case .offline:
                return .offline
            case .signedOut:
                return .signedOut
            case .procedureMissing:
                // An older server, or one rolled back: keep the queue and wait for it, never fall back to `SaveAppearance`.
                capability.record(version: 0)
                return .unsupported
            case .rejected, .transient:
                return .unsupported
            }
        }
    }

    // MARK: - Sending one entry

    private enum SendResult {
        case done
        case parked
        case stop(StopReason)
    }

    private func isReady(_ mutation: ActivityOutboxMutation) -> Bool {
        guard mutation.status == .pending else { return false }
        if let next = mutation.nextAttemptAt, next > now() { return false }
        if let dependency = mutation.dependsOnMutationId, store.mutation(dependency) != nil { return false }
        return true
    }

    private func send(_ mutation: ActivityOutboxMutation, username: String) async -> SendResult {
        guard let performance = store.performance(mutation.performanceLocalId), let kind = mutation.kind else {
            try? store.commit { store.context.delete(mutation) }
            return .done
        }

        // Fixed, and recorded as possibly sent, before it leaves the phone: from here on this entry can only be retried as is.
        let body: Data
        do {
            body = try mutation.sentRequest ?? makeRequest(for: mutation, kind: kind, performance: performance)
            try store.commit {
                mutation.sentRequest = body
                mutation.attemptCount += 1
            }
        } catch ActivityStoreError.unavailable {
            return .stop(.storeUnavailable)
        } catch {
            AppLog.activities.error("An outbox entry could not be prepared: \(String(describing: error), privacy: .public)")
            return mark(mutation, .failed, outcome: "unsendable")
        }

        let responseData: Data
        do {
            switch kind {
            case .save:
                let request = try JSONDecoder().decode(SyncSaveAppearanceRequestDTO.self, from: body)
                responseData = try await apiClient.callRPCData(.syncSaveAppearance, payload: request, requiringUsername: username)
            case .delete:
                let request = try JSONDecoder().decode(SyncDeleteAppearanceRequestDTO.self, from: body)
                responseData = try await apiClient.callRPCData(.syncDeleteAppearance, payload: request, requiringUsername: username)
            }
        } catch {
            return handle(error, for: mutation)
        }

        let response: AppearanceMutationResponseDTO
        do {
            response = try APIClient.decodeResponse(AppearanceMutationResponseDTO.self, from: responseData)
        } catch {
            return backOff(mutation, outcome: "unreadable response")
        }
        AppLog.activities.info(
            "Outbox \(mutation.id.uuidString, privacy: .public) gen \(mutation.generation, privacy: .public): \(response.status, privacy: .public)"
        )
        return apply(response, data: responseData, to: mutation, kind: kind)
    }

    private func makeRequest(for mutation: ActivityOutboxMutation, kind: ActivityMutationKind, performance: LocalPerformance) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        switch kind {
        case .save:
            guard let data = mutation.snapshotData else { throw ActivityStoreError.notFound }
            let snapshot = try PerformanceSnapshot.decoder.decode(PerformanceSnapshot.self, from: data)
            let serverId = performance.serverId
            let expected = serverId == nil ? nil : (mutation.expectedRevision ?? performance.serverRevision)
            mutation.expectedRevision = expected
            return try encoder.encode(SyncSaveAppearanceRequestDTO(
                mutationId: mutation.id.uuidString,
                expectedRevision: expected,
                appearance: SaveAppearanceRequestDTO(
                    id: serverId ?? 0,
                    eventId: performance.eventId,
                    entryId: performance.entryId,
                    occurredAt: ServerDateFormat.requestString(snapshot.occurredAt),
                    notes: ActivityFieldLimit.notes.clamp(snapshot.notes),
                    // An edit always sends its matchup, so clearing one clears it; a create leaves an empty one out.
                    matchup: snapshot.matchup ?? (serverId == nil ? nil : Matchup().input),
                    results: snapshot.results.map(\.input),
                    photoIds: snapshot.photoIds
                )
            ))
        case .delete:
            guard let serverId = performance.serverId else { throw ActivityStoreError.notFound }
            let expected = mutation.expectedRevision ?? performance.serverRevision
            mutation.expectedRevision = expected
            return try encoder.encode(SyncDeleteAppearanceRequestDTO(
                mutationId: mutation.id.uuidString,
                id: serverId,
                expectedRevision: expected
            ))
        }
    }

    private func apply(
        _ response: AppearanceMutationResponseDTO,
        data: Data,
        to mutation: ActivityOutboxMutation,
        kind: ActivityMutationKind
    ) -> SendResult {
        switch AppearanceMutationStatus(rawValue: response.status) {
        case .applied, .replayed:
            return acknowledge(mutation, response)
        case .deleted where kind == .delete:
            // Someone else deleted it first: what this entry asked for is done.
            return acknowledge(mutation, response)
        case .deleted:
            return mark(mutation, .needsReview, outcome: "deleted", response: data)
        case .conflict:
            return mark(mutation, .needsReview, outcome: "conflict", response: data)
        case .notFound, .forbidden:
            return mark(mutation, .failed, outcome: response.status, response: data)
        case .invalid:
            return mark(mutation, .failed, outcome: "invalid:\(response.code)", response: data)
        case nil:
            return backOff(mutation, outcome: "unknown status")
        }
    }

    private func acknowledge(_ mutation: ActivityOutboxMutation, _ response: AppearanceMutationResponseDTO) -> SendResult {
        do {
            try store.acknowledge(
                mutation,
                serverId: response.appearanceId,
                revision: response.revision,
                serverCopy: response.appearance,
                at: now()
            )
            return .done
        } catch {
            return .stop(.storeUnavailable)
        }
    }

    private func mark(
        _ mutation: ActivityOutboxMutation,
        _ status: ActivityMutationStatus,
        outcome: String,
        response: Data? = nil
    ) -> SendResult {
        do {
            try store.commit {
                mutation.status = status
                mutation.lastOutcome = outcome
                if let response { mutation.serverResponseData = response }
            }
            return .parked
        } catch {
            return .stop(.storeUnavailable)
        }
    }

    private func backOff(_ mutation: ActivityOutboxMutation, outcome: String) -> SendResult {
        do {
            try store.commit {
                mutation.failureCount += 1
                mutation.lastOutcome = outcome
                mutation.nextAttemptAt = now().addingTimeInterval(Self.backoff(failures: mutation.failureCount) * jitter())
            }
            return .parked
        } catch {
            return .stop(.storeUnavailable)
        }
    }

    /// 5 s, 10 s, 20 s… up to an hour. The entry is kept whatever the count: there is no retry budget to run out of.
    static func backoff(failures: Int) -> TimeInterval {
        min(baseBackoff * pow(2, Double(max(0, failures - 1))), maximumBackoff)
    }

    private func handle(_ error: Error, for mutation: ActivityOutboxMutation) -> SendResult {
        switch Self.classify(error) {
        case .offline:
            return .stop(.offline)
        case .signedOut:
            _ = mark(mutation, .needsSignIn, outcome: "signed out")
            return .stop(.signedOut)
        case .procedureMissing:
            capability.record(version: 0)
            supportConfirmed = false
            return .stop(.unsupported)
        case .rejected:
            // A request the server will never take as it stands, such as a mutation id reused for different contents. Kept for someone to look at.
            AppLog.activities.error("Outbox \(mutation.id.uuidString, privacy: .public) was rejected: \(String(describing: error), privacy: .public)")
            return mark(mutation, .failed, outcome: "rejected")
        case .transient:
            return backOff(mutation, outcome: "server error")
        }
    }

    // MARK: - Errors

    private enum ErrorKind {
        case offline, signedOut, procedureMissing, rejected, transient
    }

    private static func classify(_ error: Error) -> ErrorKind {
        guard let error = error as? APIError else { return .transient }
        switch error {
        case .network:
            return .offline
        case .unauthorized, .missingRefreshToken, .refreshFailed:
            return .signedOut
        case .server(let status, let message):
            let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text == "AuthFailure" { return .signedOut }
            if text == "Procedure Not Found" { return .procedureMissing }
            return (400..<500).contains(status) ? .rejected : .transient
        case .invalidURL, .invalidResponse, .decoding:
            return .transient
        }
    }
}
