import Foundation
import OSLog

/// The app's log categories. `Logger` writes to the unified log, so a failure on a real device can be read back with Console.app without a debugger attached.
/// `nonisolated` because the project defaults to main-actor isolation and the loudest callers are actors of their own.
nonisolated enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.familyrecord.ios"

    static let sync = Logger(subsystem: subsystem, category: "sync")

    static let queue = Logger(subsystem: subsystem, category: "queue")

    static let chat = Logger(subsystem: subsystem, category: "chat")

    static let version = Logger(subsystem: subsystem, category: "version")

    static let activities = Logger(subsystem: subsystem, category: "activities")

    static let auth = Logger(subsystem: subsystem, category: "auth")

    static let ui = Logger(subsystem: subsystem, category: "ui")
}
