import Foundation

enum AppConstants {
    static let appName = "Family Portal"
    static let defaultServerURL = "https://grissom.zone"

    enum Keychain {
        static let accessToken = "com.familyportal.accessToken"
        static let refreshToken = "com.familyportal.refreshToken"
        static let serverURL = "com.familyportal.serverURL"
    }

    enum TokenExpiry {
        static let accessToken: TimeInterval = 24 * 60 * 60       // 24 hours
        static let refreshToken: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    }
}
