import Foundation
import UIKit
import UserNotifications
import os

/// APNs registration, wired to `RegisterPushDevice` / `UnregisterPushDevice`
/// in backend/push_notifications.go. `backend/chat.go` already queues a push for
/// every new chat message, so that whole server path stayed dark until the app
/// started handing over a device token.
///
/// A singleton because `AppDelegate` — which SwiftUI instantiates itself — is
/// the only place the token arrives.
@MainActor
@Observable
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    /// The backend refuses any registration whose environment doesn't match its
    /// own `APNS_ENVIRONMENT`. Xcode rewrites the entitlement to "production"
    /// when exporting for TestFlight or the App Store, so the build
    /// configuration is what distinguishes the two.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.familyrecord.ios",
        category: "push"
    )

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The token last accepted by the server, kept so logout can retire exactly
    /// what was registered.
    private(set) var registeredToken: String?

    private var isRegistering = false

    private override init() {
        super.init()
    }

    /// Call once the user is signed in: asks for permission the first time, and
    /// on every later launch re-registers so a rotated token reaches the server.
    ///
    /// Silent about failures on purpose — a user who declines notifications, or
    /// a server without APNs configured, must not see an error for something
    /// they didn't ask for.
    func registerForPushNotifications() async {
        guard !isRegistering else { return }
        isRegistering = true
        defer { isRegistering = false }

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                authorizationStatus = granted ? .authorized : .denied
                guard granted else { return }
            } catch {
                Self.logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        case .denied:
            return
        default:
            break
        }

        // The token comes back through AppDelegate, not from this call.
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called from `AppDelegate` with the raw APNs token.
    func handleDeviceToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard let bundleId = Bundle.main.bundleIdentifier else { return }

        do {
            let response: RegisterPushDeviceResponseDTO = try await APIClient.shared.callRPC(
                "RegisterPushDevice",
                payload: RegisterPushDeviceRequestDTO(
                    token: token,
                    platform: "ios",
                    environment: Self.environment,
                    bundleId: bundleId
                )
            )

            if response.success {
                registeredToken = token
            } else {
                Self.logger.error("Server rejected push device registration")
            }
        } catch {
            Self.logger.error("Push device registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        // Expected on a simulator without a paired push environment.
        Self.logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Retires this device's token. Must run while the session is still valid,
    /// so it hangs off `AuthService.onWillLogout` rather than the sign-out
    /// button.
    func unregisterForPushNotifications() async {
        guard let token = registeredToken else { return }
        registeredToken = nil

        do {
            let _: UnregisterPushDeviceResponseDTO = try await APIClient.shared.callRPC(
                "UnregisterPushDevice",
                payload: UnregisterPushDeviceRequestDTO(token: token)
            )
        } catch {
            Self.logger.error("Push device unregistration failed: \(error.localizedDescription, privacy: .public)")
        }

        UIApplication.shared.unregisterForRemoteNotifications()
    }
}

extension PushNotificationService: UNUserNotificationCenterDelegate {
    /// Without this, a message that arrives while the app is open is delivered
    /// silently — which reads as a dropped notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
