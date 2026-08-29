import Foundation
import OSLog
import SwiftData

/// Which account the records in the local store belong to.
///
/// Signing in is not by itself enough to make the store the new account's.
/// SwiftData outlives a sign-out, so whoever used the device last leaves their
/// people, photos, milestones and chat behind for the next person to sign in.
/// The pull heals part of that — `SyncService.removeOrphans` drops every record
/// the server no longer lists — but nothing heals chat, which is fetched a page
/// at a time and merged, never reconciled. So a device that changes hands shows
/// the previous account's conversation until it is erased deliberately, which is
/// what this bookkeeping is for.
struct LocalAccountOwner {
    private static let storageKey = "com.familyrecord.localDataOwnerUserId"

    private let defaults: UserDefaults

    /// `defaults` is injectable so tests never write to the app's real record.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether an owner has ever been recorded. False on a fresh install and on
    /// the first sign-in after a build that predates this bookkeeping — which is
    /// also a store nothing can vouch for, since it may already hold what an
    /// earlier account left behind.
    var hasRecordedOwner: Bool {
        defaults.object(forKey: Self.storageKey) != nil
    }

    /// Whether what is in the store was put there by a different account.
    ///
    /// `object(forKey:)` rather than `integer(forKey:)` because the latter reads
    /// a missing key as 0, which is indistinguishable from a recorded id.
    func holdsDataForAnotherAccount(than userId: Int) -> Bool {
        guard let owner = defaults.object(forKey: Self.storageKey) as? Int else { return false }
        return owner != userId
    }

    /// Records `userId` as the owner. Called after the erase, so an erase
    /// interrupted partway leaves the store still marked as the old account's
    /// and the next sign-in tries again.
    func record(userId: Int) {
        defaults.set(userId, forKey: Self.storageKey)
    }
}

/// How much of the local store to erase.
enum LocalDataResetScope {
    /// A different account is signing in. Nothing on the device is theirs.
    case everything

    /// The store predates any record of who owns it, so it may already hold
    /// another account's chat. Only chat is dropped: every other record is
    /// reconciled against the server by the next pull — `removeOrphans` deletes
    /// what the server does not list — while chat is merged page by page and
    /// never reconciled, so it is the one thing a sync cannot heal. What is
    /// deleted comes back from the server on the next fetch.
    case chatOnly
}

/// Erases what one account leaves on this device.
enum LocalDataReset {

    /// Deletes local records and, for a full erase, drops whatever the previous
    /// account had queued for upload.
    ///
    /// The queue matters as much as the store does: a pending operation carries
    /// no identity of its own, so an unsent photo left over from the last
    /// account would be pushed under the new account's session, into the new
    /// account's family.
    /// `activityCache` and `photoCache` are injectable for the same reason
    /// `syncQueue` is: a test must be able to prove the sweep happens without
    /// erasing the real app's cache directories.
    @MainActor static func erase(
        _ scope: LocalDataResetScope,
        context: ModelContext,
        syncQueue: SyncQueue,
        activityCache: ActivitySnapshotCache = .shared,
        photoCache: PhotoImageCache = .shared
    ) async {
        delete(ChatMessage.self, from: context)

        if scope == .everything {
            await syncQueue.clearAll()

            // Activities live on disk as cached response bodies rather than in
            // SwiftData, so none of the deletes below reach them and no pull
            // reconciles them — `GetFamilyTimeline` does not carry activities.
            // Without this sweep a device that changes hands shows the previous
            // account's season.
            await activityCache.removeAll()

            // Cached photo bytes are keyed by photo id, and photo ids are
            // global. The new account cannot reach the old account's photos on
            // the server, but this cache does not know that, so without the
            // sweep it could still answer for the five minutes the server
            // allowed.
            photoCache.removeAll()

            // Every type is swept explicitly rather than leaning on `Family`'s
            // cascade: the pull creates people, photos and tags without ever
            // attaching a `Family`, so a cascade alone would clear almost
            // nothing.
            delete(Family.self, from: context)
            delete(Person.self, from: context)
            delete(GrowthData.self, from: context)
            delete(Milestone.self, from: context)
            delete(Photo.self, from: context)
            delete(FamilyTag.self, from: context)
            delete(User.self, from: context)
        }

        do {
            try context.save()
        } catch {
            AppLog.sync.error("Local data reset failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func delete<T: PersistentModel>(_ type: T.Type, from context: ModelContext) {
        guard let models = try? context.fetch(FetchDescriptor<T>()) else { return }
        for model in models {
            context.delete(model)
        }
    }
}

