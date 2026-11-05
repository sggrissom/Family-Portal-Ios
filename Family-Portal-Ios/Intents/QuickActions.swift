import UIKit

/// The Home Screen quick actions — long-press the icon — routed through `DeepLinkRouter` like a link. Set in code rather than in Info.plist so they're offered only while someone is signed in, and in `Copy`'s words.
@MainActor
enum QuickActions {

    private static let addPhotos = "com.familyrecord.ios.add-photos"
    private static let addQuote = "com.familyrecord.ios.add-quote"
    private static let search = "com.familyrecord.ios.search"

    static func update(signedIn: Bool) {
        UIApplication.shared.shortcutItems = signedIn ? [
            UIApplicationShortcutItem(type: addPhotos, localizedTitle: Copy.quickActions.addPhotos, localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "photo.on.rectangle"), userInfo: nil),
            UIApplicationShortcutItem(type: addQuote, localizedTitle: Copy.quickActions.addQuote, localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "quote.bubble"), userInfo: nil),
            UIApplicationShortcutItem(type: search, localizedTitle: Copy.quickActions.search, localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "magnifyingglass"), userInfo: nil),
        ] : []
    }

    /// The destination a quick action names, or nil for one this build doesn't know.
    static func link(for type: String) -> DeepLink? {
        switch type {
        case addPhotos: .addPhotos
        case addQuote: .addQuote(personRemoteId: nil)
        case search: .search(query: nil)
        default: nil
        }
    }

    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard let link = link(for: item.type) else { return false }
        DeepLinkRouter.shared.open(link)
        return true
    }
}

/// Hears a quick action chosen while the app is already running. A cold launch's arrives in `AppDelegate`'s scene configuration instead.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(QuickActions.handle(shortcutItem))
    }
}
