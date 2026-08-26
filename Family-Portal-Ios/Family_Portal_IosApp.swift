import SwiftUI
import SwiftData
import UIKit
import GoogleSignIn

/// SwiftUI has no hook for the APNs token, so registration results still arrive through a UIApplicationDelegate.
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
    @State private var deepLinkRouter = DeepLinkRouter()
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
                // Ordered before `.environment(errorPresenter)`: the modifier reads the presenter from its own environment, and a value injected later wraps everything earlier.
                .appErrorAlert()
                .environment(errorPresenter)
                .environment(authService)
                .environment(mobileVersionService)
                .environment(networkMonitor)
                .environment(syncService)
                .environment(activityService)
                .environment(deepLinkRouter)
                .environment(chatService)
                .task {
                    await setupServices()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
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
                    if authService.handleGoogleSignInURL(url) { return }
                    deepLinkRouter.open(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    deepLinkRouter.open(url: url)
                }
        }
        .modelContainer(container)
    }

    @MainActor
    private func setupServices() async {
        PushNotificationService.shared.router = deepLinkRouter

        // A cold launch from a tapped notification never crosses a scenePhase change, so the .active handler alone would leave the badge standing.
        await PushNotificationService.shared.clearBadge()

        networkMonitor.onConnectivityRestored = { [weak syncService] in
            Task { @MainActor in
                if self.authService.isAuthenticated {
                    await syncService?.performFullSync()
                }
            }
        }

        // Retiring the device token needs a valid session, so it has to happen before logout clears it.
        authService.onWillLogout = {
            await PushNotificationService.shared.unregisterForPushNotifications()
        }

        authService.onUnownedLocalData = { scope in
            await self.eraseLocalData(scope)
        }

        authService.onAccountDeleted = {
            await self.eraseLocalData(.everything)
        }

        // Runs alongside session restore rather than before it: the check must never delay a signed-in user.
        async let versionCheck: Void = mobileVersionService.check()

        await authService.restoreSession()
        await versionCheck
        if authService.isAuthenticated {
            await syncService.performFullSync()
            await initializeChatService()
            await PushNotificationService.shared.registerForPushNotifications()
        }
    }

    @MainActor
    private func eraseLocalData(_ scope: LocalDataResetScope) async {
        chatService = nil
        await LocalDataReset.erase(
            scope,
            context: container.mainContext,
            syncQueue: syncService.syncQueue
        )
        deepLinkRouter.clear()
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
        await service.connect()
        await service.loadMessages()
    }
}
