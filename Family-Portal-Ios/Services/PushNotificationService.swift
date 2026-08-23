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

    /// Where a tapped notification's destination goes.
    ///
    /// Assigned by the app on launch rather than injected, because this is a
    /// singleton for a reason that has not changed: `AppDelegate` is the only
    /// place a device token arrives, and `UNUserNotificationCenter` is the only
    /// place a tap does. Weak, so the router's owner still decides its lifetime.
    weak var router: DeepLinkRouter?

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
                .registerPushDevice,
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
                .unregisterPushDevice,
                payload: UnregisterPushDeviceRequestDTO(token: token)
            )
        } catch {
            Self.logger.error("Push device unregistration failed: \(error.localizedDescription, privacy: .public)")
        }

        UIApplication.shared.unregisterForRemoteNotifications()
    }

    /// The server stamps `badge: 1` on every push and never sends a corrected
    /// count, so APNs alone can only ever raise the badge. Nothing takes it back
    /// down unless the app does — which is why a single test push left the icon
    /// badged for good.
    func clearBadge() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.setBadgeCount(0)
        } catch {
            Self.logger.error("Clearing badge failed: \(error.localizedDescription, privacy: .public)")
        }
        // Delivered notifications outlive the badge otherwise, leaving the same
        // stale test push sitting in Notification Center.
        center.removeAllDeliveredNotifications()
    }
}

extension PushNotificationService: UNUserNotificationCenterDelegate {
    /// Without this, a message that arrives while the app is open is delivered
    /// silently — which reads as a dropped notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // `.badge` is deliberately absent: the user is already looking at the
        // app, and a badge applied now would survive until the next foreground
        // transition — which never comes, because the app is foreground.
        await clearBadge()
        return [.banner, .sound]
    }

    /// Tapping a notification is the user acknowledging it, so the badge goes
    /// even if the app was launched straight into this handler.
    ///
    /// It is also the only moment the payload's routing half is worth anything.
    /// Every push carries a `data.destination` that matches the web route for
    /// the same content; until this read it, tapping a chat notification opened
    /// whatever screen the app happened to be on.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await clearBadge()
        await MainActor.run {
            router?.open(pushPayload: response.notification.request.content.userInfo)
        }
    }
}
