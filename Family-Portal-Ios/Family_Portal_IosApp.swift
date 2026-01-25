//
//  Family_Portal_IosApp.swift
//  Family-Portal-Ios
//
//  Created by Grissom on 1/22/26.
//

import SwiftUI
import SwiftData

@main
struct Family_Portal_IosApp: App {
    let container: ModelContainer
    @State private var authService = AuthService()
    @State private var networkMonitor: NetworkMonitor
    @State private var syncService: SyncService
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
                        }
                    }
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
        }
    }
}
