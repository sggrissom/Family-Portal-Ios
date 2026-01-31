import Foundation
import UIKit
import UserNotifications

@MainActor
@Observable
final class PushNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationService()

    private struct TokenStore {
        private let defaults: UserDefaults
        private let deviceTokenKey = "push.deviceToken"
        private let registeredTokenKey = "push.registeredToken"

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        var deviceToken: String? {
            get { defaults.string(forKey: deviceTokenKey) }
            set {
                if let newValue {
                    defaults.set(newValue, forKey: deviceTokenKey)
                } else {
                    defaults.removeObject(forKey: deviceTokenKey)
                }
            }
        }

        var registeredToken: String? {
            get { defaults.string(forKey: registeredTokenKey) }
            set {
                if let newValue {
                    defaults.set(newValue, forKey: registeredTokenKey)
                } else {
                    defaults.removeObject(forKey: registeredTokenKey)
                }
            }
        }
    }

    private let apiClient: APIClient
    private let tokenStore: TokenStore

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var deviceToken: String?
    private(set) var lastRegistrationError: String?

    private var isAuthenticated = false

    private let environment: String = {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }()

    private override init() {
        apiClient = .shared
        tokenStore = TokenStore()
        deviceToken = tokenStore.deviceToken
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func updateAuthentication(isAuthenticated: Bool) async {
        self.isAuthenticated = isAuthenticated

        if isAuthenticated {
            let authorized = await requestAuthorizationIfNeeded()
            if authorized {
                registerForRemoteNotifications()
            }
            await registerTokenIfNeeded()
        } else {
            await unregisterTokenIfNeeded()
        }
    }

    func didRegisterForRemoteNotifications(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        tokenStore.deviceToken = token
        Task {
            await registerTokenIfNeeded()
        }
    }

    func didFailToRegisterForRemoteNotifications(_ error: Error) {
        lastRegistrationError = error.localizedDescription
    }

    func refreshAuthorizationStatus() async {
        let settings = await fetchNotificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await fetchNotificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
                await refreshAuthorizationStatus()
                return granted
            } catch {
                lastRegistrationError = error.localizedDescription
                return false
            }
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func registerTokenIfNeeded() async {
        guard isAuthenticated else { return }
        guard let deviceToken else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
            return
        }
        if tokenStore.registeredToken == deviceToken {
            return
        }

        do {
            let success = try await apiClient.registerPushToken(token: deviceToken, environment: environment)
            if success {
                tokenStore.registeredToken = deviceToken
            }
        } catch {
            lastRegistrationError = error.localizedDescription
        }
    }

    private func unregisterTokenIfNeeded() async {
        guard let registeredToken = tokenStore.registeredToken else { return }

        do {
            let success = try await apiClient.unregisterPushToken(token: registeredToken, environment: environment)
            if success {
                tokenStore.registeredToken = nil
            }
        } catch {
            lastRegistrationError = error.localizedDescription
        }
    }

    private func fetchNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }
}
