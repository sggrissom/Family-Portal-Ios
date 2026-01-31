//
//  Family_Portal_IosApp.swift
//  Family-Portal-Ios
//
//  Created by Grissom on 1/22/26.
//

import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct Family_Portal_IosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    let container: ModelContainer
    @State private var authService = AuthService()
    @State private var networkMonitor: NetworkMonitor
    @State private var syncService: SyncService
    @State private var chatService: ChatService?
    @State private var pushNotificationService = PushNotificationService.shared
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
                .environment(networkMonitor)
                .environment(syncService)
                .environment(chatService)
                .environment(pushNotificationService)
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
                    Task {
                        await pushNotificationService.updateAuthentication(isAuthenticated: isAuthenticated)
                        if isAuthenticated {
                            await syncService.performFullSync()
                            await initializeChatService()
                        } else {
                            chatService = nil
                        }
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

        await authService.restoreSession()
        if authService.isAuthenticated {
            await syncService.performFullSync()
            await initializeChatService()
        }
        await pushNotificationService.updateAuthentication(isAuthenticated: authService.isAuthenticated)
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
