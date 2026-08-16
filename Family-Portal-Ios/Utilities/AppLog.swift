import Foundation
import OSLog

/// The app's log categories.
///
/// Service-level failures used to go to `print`, which is invisible in a release
/// build and unfilterable in a debug one. `Logger` writes to the unified log, so
/// a failure on a real device can be read back with Console.app or
/// `log stream --predicate 'subsystem == "…"'` without a debugger attached.
///
/// `nonisolated` because the project defaults to main-actor isolation and the
/// loudest callers — `SyncQueue`, `ChatWebSocketService` — are actors of their
/// own.
nonisolated enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.familyrecord.ios"

    /// Pull, push, and the queue executors in `SyncService`.
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// `SyncQueue` persistence and retry accounting.
    static let queue = Logger(subsystem: subsystem, category: "queue")

    /// `ChatService` and the WebSocket transport under it.
    static let chat = Logger(subsystem: subsystem, category: "chat")

    /// The pre-auth version gate.
    static let version = Logger(subsystem: subsystem, category: "version")

    /// Failures a view caught and handed to `ErrorPresenter`.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
