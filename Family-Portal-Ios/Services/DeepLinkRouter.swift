import Foundation
import OSLog

/// Holds the destination a tapped notification or a followed link asked for,
/// until the view that owns that screen is in a position to show it.
///
/// A link arrives at the worst possible moment by construction: on a cold launch
/// it is delivered before the session has been restored, before the first sync,
/// and before any tab exists. So it is parked rather than acted on, and the
/// pieces of the UI that can honor it take it when they are ready. Nothing
/// times it out — a link the user asked for is worth honoring a second later.
@MainActor
@Observable
final class DeepLinkRouter {

    /// What has been asked for and not yet shown.
    private(set) var pending: DeepLink?

    func open(_ link: DeepLink) {
        AppLog.ui.info("Deep link received: \(String(describing: link), privacy: .public)")
        pending = link
    }

    /// Records a link from a URL or a push payload, if it names one this build
    /// knows. An unrecognized destination is dropped rather than parked: the
    /// alternative is a link that sits there and hijacks the next screen that
    /// looks for one.
    func open(url: URL) {
        guard let link = DeepLink.parse(url: url) else { return }
        open(link)
    }

    func open(pushPayload: [AnyHashable: Any]) {
        guard let link = DeepLink.parse(pushPayload: pushPayload) else { return }
        open(link)
    }

    /// Takes the pending link if it is one this caller can show.
    ///
    /// Claiming rather than reading, so two views cannot both act on one link —
    /// and so a link nobody claims stays put instead of being consumed by the
    /// first view to look at it.
    func claim(where predicate: (DeepLink) -> Bool) -> DeepLink? {
        guard let pending, predicate(pending) else { return nil }
        self.pending = nil
        return pending
    }

    /// Drops the pending link. Used when a screen could not honor it — a person
    /// this device has never pulled — so it does not reappear on the next
    /// appearance of the same view.
    func clear() {
        pending = nil
    }
}
