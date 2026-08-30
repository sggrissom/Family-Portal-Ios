import Foundation
import OSLog
import SwiftData

/// Which account the records in the local store belong to. SwiftData outlives a sign-out, and chat is merged rather than reconciled, so nothing heals it but a deliberate erase.
struct LocalAccountOwner {
    private static let storageKey = "com.familyrecord.localDataOwnerUserId"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasRecordedOwner: Bool {
        defaults.object(forKey: Self.storageKey) != nil
    }

    /// Whether what is in the store was put there by a different account. `object(forKey:)` because `integer(forKey:)` reads a missing key as 0.
    func holdsDataForAnotherAccount(than userId: Int) -> Bool {
        guard let owner = defaults.object(forKey: Self.storageKey) as? Int else { return false }
        return owner != userId
    }

    /// Records `userId` as the owner. Called after the erase, so an interrupted erase is retried on the next sign-in.
    func record(userId: Int) {
        defaults.set(userId, forKey: Self.storageKey)
    }
}

enum LocalDataResetScope {
    case everything

    /// The store predates any record of who owns it. Only chat is dropped: every other record is reconciled by the next pull, and what goes comes back from the server.
    case chatOnly
}

enum LocalDataReset {

    /// Deletes local records and, for a full erase, drops whatever the previous account had queued for upload — a pending operation carries no identity and would push under the new session.
    ///
    /// `activityCache` and `photoCache` are injectable for the same reason `syncQueue` is: a test must be able to prove the sweep happens without erasing the real app's cache directories. `photoCache` carries no default because `PhotoImageCache.shared` is main-actor isolated, and a default value expression is evaluated outside the function's isolation.
    @MainActor static func erase(
        _ scope: LocalDataResetScope,
        context: ModelContext,
        syncQueue: SyncQueue,
        activityCache: ActivitySnapshotCache = .shared,
        photoCache: PhotoImageCache
    ) async {
        delete(ChatMessage.self, from: context)

        if scope == .everything {
            await syncQueue.clearAll()

            // Activities live on disk as cached response bodies, and no pull reconciles them.
            await activityCache.removeAll()

            // Cached photo bytes are keyed by photo id, and photo ids are global, so without this the cache could still answer for the old account.
            photoCache.removeAll()

            // Every type is swept explicitly rather than leaning on `Family`'s cascade: the pull creates records without attaching a `Family`.
            delete(Family.self, from: context)
            delete(Person.self, from: context)
            delete(PersonRelation.self, from: context)
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

