import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @Environment(MobileVersionService.self) private var mobileVersionService
    @Environment(ChatService.self) private var chatService: ChatService?
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @State private var selectedTab: MainTab = .family

    /// The tab bar's identities. A raw value rather than an index, so a tab inserted later cannot silently change what a deep link selects.
    private enum MainTab: String, Hashable {
        case family, timeline, photos, activities, settings
    }

    var body: some View {
        // The version gate sits outside the auth gate on purpose: the policy endpoint is pre-auth, so an unsupported build never reaches login.
        if mobileVersionService.status == .updateRequired {
            UpdateRequiredView(
                message: mobileVersionService.updateMessage,
                updateURL: mobileVersionService.updateURL
            )
        } else if authService.isAuthenticated {
            mainTabs
        } else if authService.hasCheckedStoredSession {
            LoginView()
        } else {
            launchPlaceholder
        }
    }

    private var launchPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            ProgressView()
        }
        .accessibilityLabel("Restoring your session")
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            FamilyMembersView()
                .tabItem {
                    Label("Family", systemImage: "person.3")
                }
                .tag(MainTab.family)

            TimelineView()
                .tabItem {
                    Label("Timeline", systemImage: "clock.fill")
                }
                .tag(MainTab.timeline)

            PhotoGalleryView()
                .tabItem {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .tag(MainTab.photos)

            ActivitiesRootView()
                .tabItem {
                    Label("Activities", systemImage: "trophy")
                }
                .tag(MainTab.activities)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .badge(chatService?.unreadCount ?? 0)
                .tag(MainTab.settings)
        }
        // Both, because a link can arrive before the tabs exist — a cold launch from a tapped notification — or while they are already on screen.
        .task { selectTabForPendingLink() }
        .onChange(of: deepLinkRouter.pending) { _, _ in selectTabForPendingLink() }
    }

    /// Moves to the tab that owns the pending destination and leaves the link in place for the screen under it. `/photos` and `/family-timeline` are tab roots, so those are claimed here.
    private func selectTabForPendingLink() {
        guard let link = deepLinkRouter.pending else { return }

        switch link {
        case .photos:
            selectedTab = .photos
            _ = deepLinkRouter.claim { $0 == .photos }
        case .timeline:
            selectedTab = .timeline
            _ = deepLinkRouter.claim { $0 == .timeline }
        case .chat, .settings:
            selectedTab = .settings
        case .person, .personActivities:
            selectedTab = .family
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .environment(MobileVersionService())
        .environment(ActivityService())
        .environment(DeepLinkRouter())
        .modelContainer(for: Person.self, inMemory: true)
}
