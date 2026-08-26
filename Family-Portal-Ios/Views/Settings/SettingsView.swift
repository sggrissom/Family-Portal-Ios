import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SyncService.self) private var syncService: SyncService?
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(MobileVersionService.self) private var mobileVersionService
    @Environment(ChatService.self) private var chatService: ChatService?
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @State private var showLogoutConfirmation = false
    @State private var path = NavigationPath()

    /// The one destination in this stack a link can name. A route value rather than a `Bool`, so the back stack behaves.
    private struct ChatRoute: Hashable {}

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Account") {
                    if authService.isAuthenticated, let user = authService.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
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

                        // Required of any app that offers account creation (App Store Review Guideline 5.1.1(v)).
                        NavigationLink("Delete Account") {
                            DeleteAccountView()
                        }
                        .foregroundStyle(.red)
                    } else {
                        HStack {
                            Image(systemName: "person.circle")
                                .font(.title)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
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

                    // Survives the next successful sync on purpose: the pending count dropping to zero otherwise reads as "all saved".
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
                    NavigationLink(value: ChatRoute()) {
                        HStack {
                            Label("Family Chat", systemImage: "bubble.left.and.bubble.right")
                            Spacer()
                            if let unreadCount = chatService?.unreadCount, unreadCount > 0 {
                                Text(unreadCount, format: .number)
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.tint, in: Capsule())
                                    .accessibilityLabel("\(unreadCount) unread messages")
                            }
                        }
                    }

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
            .navigationDestination(for: ChatRoute.self) { _ in
                ChatView()
            }
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
        // Chat is reached through Settings rather than a tab of its own, so a `/chat` notification lands here and pushes the rest of the way. `.task` covers the cold launch.
        .task { openPendingLink() }
        .onChange(of: deepLinkRouter.pending) { _, _ in openPendingLink() }
    }

    private func openPendingLink() {
        guard let link = deepLinkRouter.claim(where: { $0 == .chat || $0 == .settings }) else {
            return
        }
        switch link {
        case .chat:
            // Replacing the path rather than appending: a notification asks to be looking at chat, not to be three screens deep with chat on top.
            path = NavigationPath([ChatRoute()])
        case .settings:
            path = NavigationPath()
        default:
            break
        }
    }
}
