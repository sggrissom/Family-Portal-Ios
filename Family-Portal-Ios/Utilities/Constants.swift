import Foundation

/// `nonisolated` so actors can read these without hopping to the main actor.
nonisolated enum AppConstants {
    static let appName = "Family Record"
    static let defaultServerURL = "https://familyrecord.app"

    static let privacyPolicyURL = URL(string: "https://familyrecord.app/privacy")!

    /// Read from the bundle rather than hardcoded, so the displayed version cannot drift from `MARKETING_VERSION`. `/api/mobile-version` rejects anything that isn't strict major.minor.patch.
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

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
