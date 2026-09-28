import OSLog
import SwiftUI

/// The tab bar's identities — the web's phone bar without Chat. A raw value rather than an index, so a tab inserted later cannot silently change what a deep link selects.
/// `.add` is not a destination: selecting it presents the add sheet and leaves the previous tab selected.
enum MainTab: String, Hashable, CaseIterable {
    case home, photos, add, growth
}

/// The person page's tabs. The raw value is the `?tab=` a link carries, so it matches the web's.
/// `nonisolated` because `DeepLink`, which is, carries one.
nonisolated enum PersonTab: String, Hashable, CaseIterable, Identifiable, Sendable {
    case story, photos, growth, activities

    var id: String { rawValue }

    var label: String {
        switch self {
        case .story: return Copy.person.tabs.story
        case .photos: return Copy.person.tabs.photos
        case .growth: return Copy.person.tabs.growth
        case .activities: return Copy.person.tabs.activities
        }
    }
}

/// Somewhere a tab's stack can be pushed to. One enum for the whole app, so History, Chat and Activities — reached from the account menu on *any* tab — are registered once at every tab root instead of once per screen that might link to them.
enum AppRoute: Hashable {
    case history
    case chat
    case activities
    case settings
    /// A person by local id, on one of their tabs. `manages` shows the edit affordances, which only the Settings directory offers.
    case person(UUID, tab: PersonTab = .story, manages: Bool = false)
    /// Everyone at one age. `fromRemoteId` 0 lets the server choose the anchor.
    case sameAge(ageMonths: Int?, fromRemoteId: Int)
    /// Photos opened from a day's mosaic.
    case photoSet(ids: [UUID], title: String)
    /// A competition or other event, where its results are entered — what the add sheet's Result rows open.
    case event(id: Int, name: String)
}

/// Which tab is showing and what each tab's stack holds. App-scoped and in the environment, so the account menu, the add flow and the deep-link router can all push onto whatever tab the user is standing on.
@MainActor
@Observable
final class AppNavigator {
    var selectedTab: MainTab = .home
    private var paths: [MainTab: NavigationPath] = [:]

    /// History's filters and the Photos tab's, held here — above every navigation stack — so opening a record and coming back finds them as they were.
    var historyFilters = HistoryFilters()
    var photoFilter = PhotoFilter()

    /// "Open in Photos →": the Photos tab, filtered to one person.
    func openPhotos(of personId: UUID) {
        var filter = PhotoFilter()
        filter.personLocalIds = [personId]
        photoFilter = filter
        paths[.photos] = NavigationPath()
        selectedTab = .photos
    }

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
            PhotoDetailView(photoId: route.id, openedFrom: route.openedFrom)
        }
    }
}

private struct AppRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .history:
            HistoryView()
        case .chat:
            ChatView()
        case .activities:
            ActivitiesRootView()
        case .settings:
            SettingsView()
        case .person(let id, let tab, let manages):
            PersonDetailView(personId: id, tab: tab, allowsManagementActions: manages)
        case .sameAge(let ageMonths, let fromRemoteId):
            SameAgeView(ageMonths: ageMonths, fromRemoteId: fromRemoteId)
        case .photoSet(let ids, let title):
            PhotoSetView(ids: ids, title: title)
        case .event(let id, let name):
            CompetitionView(eventId: id, eventName: name)
        }
    }
}
