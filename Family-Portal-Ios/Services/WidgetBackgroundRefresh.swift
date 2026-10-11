import BackgroundTasks
import Foundation
import OSLog
import SwiftData

/// A `BGAppRefreshTask` shortly after local midnight, so the widgets' fourteen-day horizon moves forward even when nobody opens the app. iOS runs these when it sees fit, which is why the horizon exists at all.
///
/// It publishes from the store alone, without pulling: a background launch has restored no session, and only an account whose widgets are live (`WidgetPublisher.liveOwner`) is republished, so a signed-out widget stays signed out.
@MainActor
enum WidgetBackgroundRefresh {

    static let identifier = "com.familyrecord.ios.widget-refresh"

    /// Must run before launch finishes, so it is called from `application(_:didFinishLaunchingWithOptions:)`.
    static func register(publisher: WidgetPublisher = .shared) {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                handle(task, publisher: publisher)
            }
        }
        if !registered {
            AppLog.widgets.error("Widget refresh task was not registered")
        }
        publisher.onPublished = { schedule() }
    }

    private static func handle(_ task: BGAppRefreshTask, publisher: WidgetPublisher) {
        // The next one is asked for first: a run cut short by its expiration still leaves one booked.
        schedule()

        guard let owner = publisher.liveOwner else {
            task.setTaskCompleted(success: true)
            return
        }
        let work = Task {
            await publisher.publish(context: DataStore.shared.container.mainContext, ownerUserId: owner)
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    static func schedule(now: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = nextRun(after: now)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The simulator refuses every request; on a device this means background refresh is off.
            AppLog.widgets.info("Widget refresh not scheduled: \(String(describing: error), privacy: .public)")
        }
    }

    /// A few minutes into the next local day, once "today" has moved.
    nonisolated static func nextRun(after now: Date, calendar: Calendar = .current) -> Date {
        WidgetDay.nextMidnight(after: now, calendar: calendar).addingTimeInterval(10 * 60)
    }
}
