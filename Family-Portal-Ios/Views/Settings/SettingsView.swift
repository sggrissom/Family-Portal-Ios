import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(NetworkMonitor.self) private var networkMonitor
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if authService.isAuthenticated, let user = authService.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button("Sign Out", role: .destructive) {
                            showLogoutConfirmation = true
                        }
                    } else {
                        HStack {
                            Image(systemName: "person.circle")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("Not signed in")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

                        NavigationLink("Sign In") {
                            LoginView()
                        }
                    }
                }

                Section("Sync") {
                    SyncStatusView(
                        isConnected: networkMonitor.isConnected,
                        isSyncing: syncService?.isSyncing ?? false,
                        syncError: syncService?.syncError,
                        pendingCount: syncService?.pendingOperationCount ?? 0,
                        lastSyncDate: syncService?.lastSyncDate
                    )

                    Button {
                        Task {
                            await syncService?.performFullSync()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Now")
                        }
                    }
                    .disabled(syncService?.isSyncing ?? true || !networkMonitor.isConnected)
                }

                Section("Server") {
                    HStack {
                        Text("URL")
                        Spacer()
                        Text(AppConstants.defaultServerURL)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        if authService.isAuthenticated {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                        } else {
                            Label("Disconnected", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign Out", isPresented: $showLogoutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await authService.logout()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
}
