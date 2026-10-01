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
    case story, quotes, artwork, photos, growth, activities

    var id: String { rawValue }

    var label: String {
        switch self {
        case .story: return Copy.person.tabs.story
        case .quotes: return Copy.person.tabs.quotes
        case .artwork: return Copy.person.tabs.artwork
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
    case tags
    case faces
    /// A person by local id, on one of their tabs. `manages` shows the edit affordances, which only the Settings directory offers.
    case person(UUID, tab: PersonTab = .story, manages: Bool = false)
    /// Everyone at one age. `fromRemoteId` 0 lets the server choose the anchor.
    case sameAge(ageMonths: Int?, fromRemoteId: Int)
    /// Photos opened from a day's mosaic.
    case photoSet(ids: [UUID], title: String)
    /// A competition or other event, where its results are entered — what the add sheet's Result rows open.
    case event(id: Int, name: String)

    /// The account menu's screens (Face review is also a Home nudge). They are pushed onto whichever tab is up but belong to none of them, so leaving the tab hands them back.
    var isBorrowed: Bool {
        switch self {
        case .history, .chat, .activities, .settings, .tags, .faces: return true
        default: return false
        }
    }
}

/// Which tab is showing and what each tab's stack holds. App-scoped and in the environment, so the account menu, the add flow and the deep-link router can all push onto whatever tab the user is standing on.
@MainActor
@Observable
final class AppNavigator {
    private(set) var selectedTab: MainTab = .home
    private var paths: [MainTab: NavigationPath] = [:]
    /// How deep each tab's own stack was when a borrowed screen (`AppRoute.isBorrowed`) went on top of it. Leaving the tab pops back to that depth, so coming back to Growth later finds Growth — and whatever was opened from it — not the History opened over it an hour ago.
    private var borrowedFrom: [MainTab: Int] = [:]

    /// History's filters and the Photos tab's, held here — above every navigation stack — so opening a record and coming back finds them as they were.
    var historyFilters = HistoryFilters()
    var photoFilter = PhotoFilter()

    /// "Open in Photos →": the Photos tab, filtered to one person.
    func openPhotos(of personId: UUID) {
        var filter = PhotoFilter()
        filter.personLocalIds = [personId]
        photoFilter = filter
        popToRoot(.photos)
        select(.photos)
    }

    /// Switches tabs, handing back whatever the tab being left had borrowed.
    func select(_ tab: MainTab) {
        guard tab != selectedTab else { return }
        returnBorrowed(on: selectedTab)
        selectedTab = tab
    }

    private func returnBorrowed(on tab: MainTab) {
        guard let depth = borrowedFrom.removeValue(forKey: tab), var path = paths[tab], path.count > depth else { return }
        path.removeLast(path.count - depth)
        paths[tab] = path
    }

    /// Photos with faces to review, from `GetFaceReview`; nil when face tagging is off or the count has not arrived.
    private(set) var faceReviewCount: Int?

    func path(for tab: MainTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { path in
                self.paths[tab] = path
                // Backed out of the borrowed screens by hand: nothing left to hand back.
                if let depth = self.borrowedFrom[tab], path.count <= depth {
                    self.borrowedFrom[tab] = nil
                }
            }
        )
    }

    /// Pushes onto the current tab's stack. History, Chat and Activities are pushed rather than switched to: they are not tabs.
    func push(_ route: AppRoute) {
        let path = paths[selectedTab, default: NavigationPath()]
        if route.isBorrowed, borrowedFrom[selectedTab] == nil {
            borrowedFrom[selectedTab] = path.count
        }
        paths[selectedTab, default: NavigationPath()].append(route)
    }

    /// Opens a photo on the current tab — for screens whose rows hold several buttons, where a `NavigationLink` would swallow the row.
    func push(_ route: PhotoRoute) {
        paths[selectedTab, default: NavigationPath()].append(route)
    }

    /// Replaces the current tab's stack — a link asks to be looking at something, not to be several screens deep with it on top.
    func show(_ routes: [AppRoute], on tab: MainTab? = nil) {
        if let tab { select(tab) }
        var path = NavigationPath()
        for route in routes { path.append(route) }
        paths[selectedTab] = path
        borrowedFrom[selectedTab] = routes.firstIndex(where: \.isBorrowed)
    }

    func popToRoot(_ tab: MainTab) {
        paths[tab] = NavigationPath()
        borrowedFrom[tab] = nil
    }

    /// How many screens deep a tab's stack is.
    func depth(of tab: MainTab) -> Int {
        paths[tab]?.count ?? 0
    }

    /// The Faces screen already holds a fresh review after each change; it hands the counts over rather than asking again.
    func updateFaceReviewCount(enabled: Bool, unknownCount: Int, autoCount: Int) {
        faceReviewCount = enabled ? unknownCount + autoCount : nil
    }

    func refreshFaceReviewCount(apiClient: APIClient = .shared) async {
        do {
            let response: FaceReviewSummaryDTO = try await apiClient.callRPC(.getFaceReview, payload: EmptyRequestDTO())
            updateFaceReviewCount(enabled: response.enabled, unknownCount: response.unknownCount, autoCount: response.autoCount)
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
        case .tags:
            ManageTagsView()
        case .faces:
            FaceReviewView()
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
