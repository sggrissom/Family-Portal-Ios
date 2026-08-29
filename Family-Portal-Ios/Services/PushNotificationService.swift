import Foundation
import UIKit
import UserNotifications
import os

@MainActor
@Observable
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    /// The backend refuses a registration whose environment doesn't match its own `APNS_ENVIRONMENT`, and Xcode rewrites the entitlement to "production" for TestFlight.
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

    private(set) var registeredToken: String?

    private var isRegistering = false

    weak var router: DeepLinkRouter?

    private override init() {
        super.init()
    }

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

        UIApplication.shared.registerForRemoteNotifications()
    }

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
        Self.logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Retires this device's token. Must run while the session is still valid, so it hangs off `AuthService.onWillLogout`.
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

    /// The server stamps `badge: 1` on every push and never sends a corrected count, so nothing takes the badge back down unless the app does.
    func clearBadge() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.setBadgeCount(0)
        } catch {
            Self.logger.error("Clearing badge failed: \(error.localizedDescription, privacy: .public)")
        }
        center.removeAllDeliveredNotifications()
    }
}

extension PushNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // `.badge` is deliberately absent: a badge applied while the app is foreground would survive until a foreground transition that never comes.
        await clearBadge()
        return [.banner, .sound]
    }

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
