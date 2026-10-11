import Foundation
import OSLog
import SwiftData
import WidgetKit

/// When the widgets' snapshot is rebuilt, and when it is thrown away. One run at a time: a request made during a run sets `rerunRequested` and the run goes round again, the way `SyncService.processQueue` does.
///
/// A sign-out bumps `generation`, cancels the run and deletes the store; a run that started under an older generation then refuses to write, so the old account's snapshot cannot land after the erase.
@MainActor
final class WidgetPublisher {

    static let shared = WidgetPublisher()

    /// How old a snapshot may be before backgrounding the app rebuilds it.
    static let backgroundRefreshAge: TimeInterval = 6 * 60 * 60

    private let makeStore: () -> WidgetStore?
    private let images: any WidgetImageSource
    private let reloadTimelines: () -> Void
    private let defaults: UserDefaults

    private var running: Task<Void, Never>?
    private var rerunRequested = false
    private var generation = 0

    private static let lastPublishedKey = "com.familyrecord.widgetSnapshotPublishedAt"

    init(
        makeStore: @escaping () -> WidgetStore? = { WidgetStore.shared() },
        images: (any WidgetImageSource)? = nil,
        defaults: UserDefaults = .standard,
        reloadTimelines: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.makeStore = makeStore
        self.images = images ?? CachedWidgetImageSource()
        self.defaults = defaults
        self.reloadTimelines = reloadTimelines
    }

    var lastPublished: Date? {
        defaults.object(forKey: Self.lastPublishedKey) as? Date
    }

    /// Rebuilds the snapshot in the background of whatever asked. Returns once this request's run — or the run that absorbed it — is done.
    func publish(context: ModelContext, ownerUserId: Int) async {
        if let running {
            rerunRequested = true
            await running.value
            return
        }

        let generation = self.generation
        let task = Task { [self] in
            repeat {
                rerunRequested = false
                await runOnce(context: context, ownerUserId: ownerUserId, generation: generation)
            } while rerunRequested && generation == self.generation && !Task.isCancelled
        }
        running = task
        await task.value
        if self.generation == generation {
            running = nil
        }
    }

    /// The cheap refresh for leaving the app: only when the last snapshot is older than `backgroundRefreshAge`.
    func publishIfStale(context: ModelContext, ownerUserId: Int, now: Date = Date()) async {
        if let lastPublished, now.timeIntervalSince(lastPublished) < Self.backgroundRefreshAge { return }
        await publish(context: context, ownerUserId: ownerUserId)
    }

    /// Signs the widgets out: whatever is running is abandoned, the directory goes, and every widget redraws as signed out.
    func clear() {
        generation += 1
        running?.cancel()
        running = nil
        rerunRequested = false
        makeStore()?.removeAll()
        defaults.removeObject(forKey: Self.lastPublishedKey)
        reloadTimelines()
    }

    private func runOnce(context: ModelContext, ownerUserId: Int, generation: Int) async {
        guard let store = makeStore() else { return }
        let builder = WidgetSnapshotBuilder(context: context, store: store, images: images)
        let snapshot = await builder.publish(ownerUserId: ownerUserId) { [self] in
            generation == self.generation
        }
        guard snapshot != nil, generation == self.generation else { return }
        defaults.set(Date(), forKey: Self.lastPublishedKey)
        reloadTimelines()
        AppLog.widgets.info("Published widget snapshot")
    }
}
