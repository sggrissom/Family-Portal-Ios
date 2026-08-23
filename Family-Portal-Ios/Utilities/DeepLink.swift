import Foundation

/// A destination named by a site-relative path.
///
/// The server has spoken in these terms since the push payload was versioned:
/// every `pushEventSpecs` entry carries a `destination` that matches the web
/// route for the same content, so the same string works both as the routing
/// field in a notification and as a universal link followed from Safari.
///
/// **This list and the one in `backend/universal_links.go` are the same list.**
/// A path the association claims but this cannot parse is a link that opens the
/// app and then does nothing — worse than the browser it was taken from. A path
/// this parses but the association does not claim simply never arrives.
nonisolated enum DeepLink: Equatable, Sendable {
    case chat
    case settings
    case photos
    case timeline
    /// `/profile/<serverId>` — a person, by the id the server knows them by, not
    /// the local `UUID`. Resolving one to the other is the router's job, and it
    /// can fail: a link can name someone this device has not pulled yet.
    case person(remoteId: Int)
    /// `/person-activities/<serverId>`
    case personActivities(remoteId: Int)

    /// Parses a site-relative path. Query and fragment are ignored — nothing in
    /// the set below carries state in either, and a link with an unexpected
    /// query is still the link.
    static func parse(path rawPath: String) -> DeepLink? {
        let path = rawPath
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]

        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        switch segments.first {
        case "chat" where segments.count == 1:
            return .chat
        case "settings" where segments.count == 1:
            return .settings
        case "photos" where segments.count == 1:
            return .photos
        case "family-timeline" where segments.count == 1:
            return .timeline
        case "profile" where segments.count == 2:
            return Int(segments[1]).map(DeepLink.person)
        case "person-activities" where segments.count == 2:
            return Int(segments[1]).map(DeepLink.personActivities)
        default:
            return nil
        }
    }

    /// Parses a universal link.
    ///
    /// The host is checked even though iOS only hands over URLs matching the
    /// entitlement: `onOpenURL` also receives the Google sign-in callback and
    /// anything else the app is registered for, and a link to somebody else's
    /// site must not be read as a route into this one.
    static func parse(url: URL) -> DeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              let host = components.host,
              host.caseInsensitiveCompare(Self.siteHost) == .orderedSame
        else {
            return nil
        }
        return parse(path: components.path)
    }

    /// Reads the routing half of a push payload.
    ///
    /// `data.destination` is the field to route on. `data.type` and
    /// `data.record_id` are deliberately not consulted: the server picks the
    /// destination from one spec table so that adding an event does not mean
    /// adding a branch here, and an event this build has never heard of still
    /// lands somewhere sensible.
    static func parse(pushPayload: [AnyHashable: Any]) -> DeepLink? {
        guard let data = pushPayload["data"] as? [AnyHashable: Any],
              let destination = data["destination"] as? String
        else {
            return nil
        }
        return parse(path: destination)
    }

    /// The host whose links this app answers for. Derived from the configured
    /// server so the two cannot disagree.
    static var siteHost: String {
        URL(string: AppConstants.defaultServerURL)?.host ?? "familyrecord.app"
    }
}
