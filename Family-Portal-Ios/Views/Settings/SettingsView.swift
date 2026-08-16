import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(MobileVersionService.self) private var mobileVersionService
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
                    HStack {
                        Text("Connection")
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

                    SyncStatusView(
                        isConnected: networkMonitor.isConnected,
                        isSyncing: syncService?.isSyncing ?? false,
                        syncError: syncService?.syncError,
                        pendingCount: syncService?.pendingOperationCount ?? 0,
                        lastSyncDate: syncService?.lastSyncDate
                    )

                    // Survives the next successful sync on purpose: the pending
                    // count dropping back to zero otherwise reads as "all saved"
                    // when an operation was in fact thrown away.
                    if let syncService, let warning = syncService.discardedChangeWarning {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)

                            Button("Dismiss") {
                                syncService.acknowledgeDiscardedChanges()
                            }
                            .font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }

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

                Section("Family") {
                    NavigationLink("Manage Family") {
                        FamilyManagementView()
                    }

                    NavigationLink("Families & Invite Codes") {
                        FamilyInfoView()
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(AppConstants.displayVersion)
                            .foregroundStyle(.secondary)
                    }

                    // update_required blocks the whole app in ContentView;
                    // update_available is only worth a nudge.
                    if mobileVersionService.status == .updateAvailable,
                       let updateURL = mobileVersionService.updateURL {
                        Link(destination: updateURL) {
                            Label(
                                mobileVersionService.latestVersion.isEmpty
                                    ? "Update available"
                                    : "Update available (\(mobileVersionService.latestVersion))",
                                systemImage: "arrow.down.circle"
                            )
                        }
                    }

                    Link(destination: AppConstants.privacyPolicyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
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
