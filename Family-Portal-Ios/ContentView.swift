import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @Environment(MobileVersionService.self) private var mobileVersionService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @Environment(AppNavigator.self) private var navigator
    @Environment(AddFlow.self) private var addFlow

    @Query private var people: [Person]

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

    /// Home · Photos · **+** · Growth — the web's phone bar without Chat, which lives in the account menu.
    /// **+** is a tab only so it sits in the bar: selecting it presents the add sheet and leaves the previous tab selected, because the binding never lets the selection become `.add`.
    private var mainTabs: some View {
        let selection = Binding<MainTab>(
            get: { navigator.selectedTab },
            set: { tab in
                if tab == .add {
                    addFlow.present()
                } else if tab == navigator.selectedTab {
                    // A second tap on the current tab goes back to its root, as tab bars do.
                    navigator.popToRoot(tab)
                } else {
                    navigator.selectedTab = tab
                }
            }
        )

        return TabView(selection: selection) {
            TabRoot(tab: .home) { HomeView() }
                .tabItem { Label(Copy.nav.home, systemImage: "house") }
                .tag(MainTab.home)

            TabRoot(tab: .photos) { PhotoGalleryView() }
                .tabItem { Label(Copy.nav.photos, systemImage: "photo.on.rectangle") }
                .tag(MainTab.photos)

            Color.clear
                .tabItem { Label(Copy.nav.add, systemImage: "plus.circle.fill") }
                .tag(MainTab.add)

            TabRoot(tab: .growth) { GrowthRootView() }
                .tabItem { Label(Copy.nav.growth, systemImage: "chart.line.uptrend.xyaxis") }
                .tag(MainTab.growth)
        }
        .addFlowPresentation(addFlow)
        // Both, because a link can arrive before the tabs exist — a cold launch from a tapped notification — or while they are already on screen.
        .task {
            // A Result row in the add sheet opens its event on whichever tab is up.
            addFlow.openEvent = { [navigator] open in
                navigator.push(.event(id: open.event.id, name: open.event.name))
            }
            openPendingLink()
            await navigator.refreshFaceReviewCount()
        }
        .onChange(of: deepLinkRouter.pending) { _, _ in openPendingLink() }
        // A person link names a server id; one this device has not seen yet stays pending until the sync after a cold launch brings it.
        .onChange(of: people.count) { _, _ in openPendingLink() }
    }

    /// Every link is routed here, in one place. Tab roots are selected; History, Chat and Settings are pushed onto the current tab, as the account menu pushes them.
    private func openPendingLink() {
        guard let link = deepLinkRouter.pending else { return }

        switch link {
        case .home:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([], on: .home)
        case .photos:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([], on: .photos)
        case .history:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.history])
        case .chat:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.chat])
        case .settings:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.settings])
        case .person(let remoteId, let tab):
            guard let person = people.first(where: { $0.remoteId.flatMap(Int.init) == remoteId }) else { return }
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.person(person.id, tab: tab ?? .story)], on: .home)
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .environment(MobileVersionService())
        .environment(ActivityService())
        .environment(DeepLinkRouter())
        .environment(AppNavigator())
        .environment(AddFlow())
        .modelContainer(for: Person.self, inMemory: true)
}
