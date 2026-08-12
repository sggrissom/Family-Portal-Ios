import Foundation

/// `nonisolated` so actors (APIClient, SyncQueue) can read these without
/// hopping to the main actor.
nonisolated enum AppConstants {
    static let appName = "Family Record"
    static let defaultServerURL = "https://familyrecord.app"

    /// Required by the App Store listing and linked from Settings.
    static let privacyPolicyURL = URL(string: "https://familyrecord.app/privacy")!

    /// Read from the bundle rather than hardcoded, so the displayed version can
    /// never drift from `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
    /// `/api/mobile-version` rejects anything that isn't strict major.minor.patch.
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// e.g. "1.0.0 (12)"
    static var displayVersion: String {
        "\(marketingVersion) (\(buildNumber))"
    }

    nonisolated enum Keychain {
        static let accessToken = "com.familyrecord.accessToken"
        static let refreshToken = "com.familyrecord.refreshToken"
    }

    nonisolated enum TokenExpiry {
        static let accessToken: TimeInterval = 24 * 60 * 60       // 24 hours
        static let refreshToken: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    }
}
