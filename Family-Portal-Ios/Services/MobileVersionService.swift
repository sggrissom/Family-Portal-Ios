import Foundation
import OSLog

enum MobileVersionStatus: Sendable, Equatable {
    /// The check hasn't completed yet, or it failed. Treated as "let them in":
    /// a version endpoint that is down must never lock users out of the app.
    case unknown
    case ok
    case updateAvailable
    case updateRequired

    init(wireValue: String) {
        switch wireValue {
        case "ok": self = .ok
        case "update_available": self = .updateAvailable
        case "update_required": self = .updateRequired
        default: self = .unknown
        }
    }
}

/// Wraps `GET /api/mobile-version` (backend/mobile_version.go). The endpoint is
/// pre-auth by design, so this runs before the sign-in gate.
@Observable
@MainActor
final class MobileVersionService {
    private(set) var status: MobileVersionStatus = .unknown
    private(set) var updateMessage: String = ""
    private(set) var updateURL: URL?
    private(set) var latestVersion: String = ""

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// The App Store link the operator configured, falling back to nothing —
    /// the blocking screen hides its button rather than opening a bad URL.
    var canOpenUpdateURL: Bool { updateURL != nil }

    func check() async {
        let appVersion = AppConstants.marketingVersion

        do {
            let policy = try await apiClient.checkMobileVersion(appVersion: appVersion)
            status = MobileVersionStatus(wireValue: policy.status)
            updateMessage = policy.updateMessage
            latestVersion = policy.latestVersion
            updateURL = policy.updateUrl.isEmpty ? nil : URL(string: policy.updateUrl)
        } catch {
            // Network failure, a 400 from a malformed MARKETING_VERSION, or an
            // operator who hasn't configured a policy yet — none of those are
            // reasons to block someone from their own family's data.
            status = .unknown
            AppLog.version.error("Version check failed: \(String(describing: error), privacy: .public)")
        }
    }
}
