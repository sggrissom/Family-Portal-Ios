import OSLog
import SwiftUI

/// The tab bar's identities — the web's phone bar without Chat. A raw value rather than an index, so a tab inserted later cannot silently change what a deep link selects.
/// `.add` is not a destination: selecting it presents the add sheet and leaves the previous tab selected.
enum MainTab: String, Hashable, CaseIterable {
    case home, photos, add, growth
}

/// Somewhere a tab's stack can be pushed to. One enum for the whole app, so History, Chat and Activities — reached from the account menu on *any* tab — are registered once at every tab root instead of once per screen that might link to them.
enum AppRoute: Hashable {
    case history
    case chat
    case activities
    case settings
    /// A person by local id. `manages` shows the edit affordances, which only the Settings directory offers.
    case person(UUID, manages: Bool = false)
    /// A person's season, addressed by the server id `GetPersonSeason` takes; the name rides along so the screen need not look it up.
    case personSeason(remoteId: Int, name: String)
}

/// Which tab is showing and what each tab's stack holds. App-scoped and in the environment, so the account menu, the add flow and the deep-link router can all push onto whatever tab the user is standing on.
@MainActor
@Observable
final class AppNavigator {
    var selectedTab: MainTab = .home
    private var paths: [MainTab: NavigationPath] = [:]

    /// Photos with faces to review, from `GetFaceReview`; nil when face tagging is off or the count has not arrived.
    private(set) var faceReviewCount: Int?

    func path(for tab: MainTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { self.paths[tab] = $0 }
        )
    }

    /// Pushes onto the current tab's stack. History, Chat and Activities are pushed rather than switched to: they are not tabs.
    func push(_ route: AppRoute) {
        paths[selectedTab, default: NavigationPath()].append(route)
    }

    /// Replaces the current tab's stack — a link asks to be looking at something, not to be several screens deep with it on top.
    func show(_ routes: [AppRoute], on tab: MainTab? = nil) {
        if let tab { selectedTab = tab }
        var path = NavigationPath()
        for route in routes { path.append(route) }
        paths[selectedTab] = path
    }

    func popToRoot(_ tab: MainTab) {
        paths[tab] = NavigationPath()
    }

    func refreshFaceReviewCount(apiClient: APIClient = .shared) async {
        do {
            let response: FaceReviewSummaryDTO = try await apiClient.callRPC(.getFaceReview, payload: EmptyRequestDTO())
            faceReviewCount = response.enabled ? response.unknownCount + response.autoCount : nil
        } catch {
            // A badge is not worth an alert. The last count stays.
            AppLog.ui.info("Face review count unavailable: \(String(describing: error), privacy: .public)")
        }
    }
}

extension View {
    /// Registers every `AppRoute` and `PhotoRoute` destination. Applied once at each tab root: SwiftUI uses the registration nearest the root, so a second one further up the stack would only ever be ignored.
    func appDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            AppRouteDestination(route: route)
        }
        .navigationDestination(for: PhotoRoute.self) { route in
            PhotoDetailView(photoId: route.id)
        }
    }
}

private struct AppRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .history:
            TimelineView()
        case .chat:
            ChatView()
        case .activities:
            ActivitiesRootView()
        case .settings:
            SettingsView()
        case .person(let id, let manages):
            PersonDetailView(personId: id, allowsManagementActions: manages)
        case .personSeason(let remoteId, let name):
            PersonSeasonView(personId: remoteId, personName: name)
        }
    }
}
