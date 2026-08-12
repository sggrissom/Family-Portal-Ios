//
//  Family_Portal_IosApp.swift
//  Family-Portal-Ios
//
//  Created by Grissom on 1/22/26.
//

import SwiftUI
import SwiftData
import UIKit
import GoogleSignIn

/// SwiftUI has no hook for the APNs token, so registration results still have
/// to arrive through a UIApplicationDelegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await PushNotificationService.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleRegistrationFailure(error)
        }
    }
}

@main
struct Family_Portal_IosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer
    @State private var authService = AuthService()
    @State private var mobileVersionService = MobileVersionService()
    @State private var networkMonitor: NetworkMonitor
    @State private var syncService: SyncService
    @State private var chatService: ChatService?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        container = DataStore.shared.container
        let monitor = NetworkMonitor()
        _networkMonitor = State(initialValue: monitor)
        _syncService = State(initialValue: SyncService(
            modelContext: container.mainContext,
            apiClient: APIClient.shared,
            networkMonitor: monitor
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(mobileVersionService)
                .environment(networkMonitor)
                .environment(syncService)
                .environment(chatService)
                .task {
                    await setupServices()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            if authService.isAuthenticated {
                                await syncService.performFullSync()
                            }
                        }
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        Task {
                            await syncService.performFullSync()
                            await initializeChatService()
                            await PushNotificationService.shared.registerForPushNotifications()
                        }
                    } else {
                        chatService = nil
                    }
                }
                .onOpenURL { url in
                    _ = authService.handleGoogleSignInURL(url)
                }
        }
        .modelContainer(container)
    }

    @MainActor
    private func setupServices() async {
        networkMonitor.onConnectivityRestored = { [weak syncService] in
            Task { @MainActor in
                if self.authService.isAuthenticated {
                    await syncService?.performFullSync()
                }
            }
        }

        // Retiring the device token needs a valid session, so it has to happen
        // before logout clears it — wherever logout is triggered from.
        authService.onWillLogout = {
            await PushNotificationService.shared.unregisterForPushNotifications()
        }

        // Runs alongside session restore rather than before it: the check must
        // never delay a signed-in user, and an unsupported build is gated by
        // ContentView regardless of how the restore turns out.
        async let versionCheck: Void = mobileVersionService.check()

        await authService.restoreSession()
        await versionCheck
        if authService.isAuthenticated {
            await syncService.performFullSync()
            await initializeChatService()
            // Re-registering every launch is how a rotated APNs token reaches
            // the server; RegisterPushDevice upserts, so a repeat is cheap.
            await PushNotificationService.shared.registerForPushNotifications()
        }
    }

    @MainActor
    private func initializeChatService() async {
        guard let user = authService.currentUser else { return }
        chatService = await ChatService(
            modelContext: container.mainContext,
            apiClient: APIClient.shared,
            currentUserId: user.id,
            currentUserName: user.name
        )
    }
}
