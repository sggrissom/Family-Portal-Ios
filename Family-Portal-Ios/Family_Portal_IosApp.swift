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
    @State private var errorPresenter = ErrorPresenter()
    @State private var activityService = ActivityService()
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
                // Ordered before `.environment(errorPresenter)` on purpose: the
                // modifier reads the presenter from its own environment, and a
                // value injected later in the chain wraps everything earlier.
                .appErrorAlert()
                .environment(errorPresenter)
                .environment(authService)
                .environment(mobileVersionService)
                .environment(networkMonitor)
                .environment(syncService)
                .environment(activityService)
                .environment(chatService)
                .task {
                    await setupServices()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            // Ahead of the auth guard: opening the app is what
                            // retires the badge, whether or not the session
                            // survived.
                            await PushNotificationService.shared.clearBadge()
                            guard authService.isAuthenticated else { return }
                            await APIClient.shared.ensureFreshAccessToken()
                            guard authService.isAuthenticated else { return }
                            await syncService.performFullSync()
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
        // A cold launch from a tapped notification never crosses a scenePhase
        // change, so the .active handler alone would leave the badge standing.
        await PushNotificationService.shared.clearBadge()

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

        // A second account signing in on this device would otherwise inherit the
        // first one's store. The chat service is dropped first because it holds
        // the messages about to be deleted.
        authService.onUnownedLocalData = { scope in
            self.chatService = nil
            await LocalDataReset.erase(
                scope,
                context: self.container.mainContext,
                syncQueue: self.syncService.syncQueue
            )
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
        let service = await ChatService(
            modelContext: container.mainContext,
            apiClient: APIClient.shared,
            currentUserId: user.id,
            currentUserName: user.name
        )
        chatService = service
        // Chat is deliberately no longer a main tab. Keep its lightweight
        // socket alive so an incoming message can make the tucked-away entry
        // visible with an unread badge.
        await service.connect()
        await service.loadMessages()
    }
}
