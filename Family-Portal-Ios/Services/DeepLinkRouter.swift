import Foundation
import OSLog

/// Holds the destination a tapped notification or a followed link asked for, until the view that owns that screen can show it.
/// A link arrives before the session is restored and before any tab exists, so it is parked rather than acted on. Nothing times it out.
@MainActor
@Observable
final class DeepLinkRouter {

    private(set) var pending: DeepLink?

    func open(_ link: DeepLink) {
        AppLog.ui.info("Deep link received: \(String(describing: link), privacy: .public)")
        pending = link
    }

    /// Records a link, if it names one this build knows. An unrecognized destination is dropped rather than parked, so it cannot hijack the next screen that looks for one.
    func open(url: URL) {
        guard let link = DeepLink.parse(url: url) else { return }
        open(link)
    }

    func open(pushPayload: [AnyHashable: Any]) {
        guard let link = DeepLink.parse(pushPayload: pushPayload) else { return }
        open(link)
    }

    /// Takes the pending link if it is one this caller can show. Claiming rather than reading, so two views cannot both act on one link.
    func claim(where predicate: (DeepLink) -> Bool) -> DeepLink? {
        guard let pending, predicate(pending) else { return nil }
        self.pending = nil
        return pending
    }

    /// Drops the pending link — used when a screen could not honor it, so it does not reappear.
    func clear() {
        pending = nil
    }
}
