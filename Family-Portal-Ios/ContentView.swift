import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AuthService.self) private var authService
    @Environment(MobileVersionService.self) private var mobileVersionService
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @Environment(AppNavigator.self) private var navigator
    @Environment(AddFlow.self) private var addFlow
    @Environment(ChatService.self) private var chatService: ChatService?
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext

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

    /// Home · Photos · **+** · Growth · More — the web's phone bar. More holds History, Books, Same age, Activities and Chat; the account menu keeps only the account's own controls.
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
                    navigator.select(tab)
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

            // A view-only member has nothing to add, so the bar drops the **+** rather than offering a sheet whose every choice would be refused.
            if authService.access.canContributeAnywhere {
                Color.clear
                    .tabItem { Label(Copy.nav.add, systemImage: "plus.circle.fill") }
                    .tag(MainTab.add)
            }

            TabRoot(tab: .growth) { GrowthRootView() }
                .tabItem { Label(Copy.nav.growth, systemImage: "chart.line.uptrend.xyaxis") }
                .tag(MainTab.growth)

            // Unread chat badges the tab that holds Chat, so a new message is visible from anywhere.
            TabRoot(tab: .more) { MoreView() }
                .tabItem { Label(Copy.nav.more, systemImage: "ellipsis") }
                .badge(chatService?.unreadCount ?? 0)
                .tag(MainTab.more)
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
        // Likewise a milestone, which nothing above is counting.
        .onChange(of: syncService.lastSyncDate) { _, _ in openPendingLink() }
    }

    /// Every link is routed here, in one place. Tab roots are selected; History, Chat and Same age open on More, where they live; Settings is pushed onto the current tab, as the account menu pushes it.
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
            navigator.show([.history], on: .more)
        case .growth:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([], on: .growth)
        case .sameAge(let ageMonths, let from, let view):
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.sameAge(ageMonths: ageMonths, fromRemoteId: from, view: view)], on: .more)
        case .chat:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.chat], on: .more)
        case .settings:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.settings])
        case .person(let remoteId, let tab):
            guard let person = people.first(where: { $0.serverId == remoteId }) else { return }
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.person(person.id, tab: tab ?? .story)], on: .home)
        case .photo(let remoteId):
            _ = deepLinkRouter.claim { $0 == link }
            // A photo can always be shown: from the store when it is here, from the server when it is not yet.
            if let photo = fetchPhoto(remoteId: remoteId) {
                navigator.show(PhotoRoute(id: photo.id), on: .photos)
            } else {
                navigator.show([.remotePhoto(id: remoteId)], on: .photos)
            }
        case .milestone(let remoteId):
            guard let milestone = fetchMilestone(remoteId: remoteId) else { return }
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.milestone(milestone.id)], on: .home)
        case .interview(let id, let ask):
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([ask ? .interviewAsk(id: id) : .interview(id: id)], on: .home)
        case .interviews:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.interviews], on: .more)
        case .interviewQuestions:
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.interviews, .interviewQuestions], on: .more)
        case .interviewCompare(let questionId):
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.interviews, .interviewCompare(questionId: questionId)], on: .more)
        case .interviewPast(let personId):
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.interviewPast(personId: personId)], on: .home)
        case .interviewSetup(let personId):
            _ = deepLinkRouter.claim { $0 == link }
            navigator.show([.interviewSetup(personId: personId)], on: .home)
        }
    }
}

private extension ContentView {
    // Fetched rather than queried: links are rare, and a `@Query` over every photo would redraw the shell on each change.

    func fetchPhoto(remoteId: Int) -> Photo? {
        let id = String(remoteId)
        var descriptor = FetchDescriptor<Photo>(predicate: #Predicate { $0.remoteId == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func fetchMilestone(remoteId: Int) -> Milestone? {
        let id = String(remoteId)
        var descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.remoteId == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
        .environment(MobileVersionService())
        .environment(ActivityService())
        .environment(BookService())
        .environment(InterviewService())
        .environment(DeepLinkRouter())
        .environment(AppNavigator())
        .environment(AddFlow())
        .modelContainer(for: Person.self, inMemory: true)
}
