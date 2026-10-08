import Foundation

/// A destination named by a site-relative path, the same string a push payload routes on and a universal link carries.
/// **This list and the one in `backend/universal_links.go` are the same list.** A path the association claims but this cannot parse opens the app and does nothing.
nonisolated enum DeepLink: Equatable, Sendable {
    case chat
    case settings
    case photos
    /// `/dashboard`, the Home tab.
    case home
    /// `/history`, and the legacy `/family-timeline` it replaced.
    case history
    /// `/growth`, and the legacy `/family-chart`.
    case growth
    /// `/same-age?age=40m&from=7&view=details`, and the legacy `/compare`. `ageMonths` nil is the anchor's current age; `from` 0 lets the server choose; `view` absent is Portraits.
    case sameAge(ageMonths: Int?, from: Int, view: SameAgeMode = .portraits)
    /// `/profile/<serverId>?tab=` — the id the server knows them by, not the local `UUID`; resolving one to the other is the router's job and can fail. `tab` nil is the person's Story.
    case person(remoteId: Int, tab: PersonTab? = nil)

    /// Parses a site-relative path. The fragment is ignored, and the query only where a destination reads one (`/profile`'s `tab`, `/same-age`'s `age`, `from` and `view`).
    static func parse(path rawPath: String) -> DeepLink? {
        let withoutFragment = rawPath.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let halves = withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = halves[0]
        let query = halves.count > 1 ? String(halves[1]) : ""

        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        switch segments.first {
        case "chat" where segments.count == 1:
            return .chat
        case "settings" where segments.count == 1:
            return .settings
        case "photos" where segments.count == 1:
            return .photos
        case "dashboard" where segments.count == 1:
            return .home
        case "history" where segments.count == 1:
            return .history
        // Legacy paths map to their replacements, as `appNav.legacyRedirect` does on the web.
        case "family-timeline" where segments.count == 1:
            return .history
        case "growth" where segments.count == 1, "family-chart" where segments.count == 1:
            return .growth
        case "same-age" where segments.count == 1, "compare" where segments.count == 1:
            return .sameAge(
                ageMonths: AgeSteps.parseAgeParam(queryValue("age", in: query)),
                from: queryValue("from", in: query).flatMap(Int.init) ?? 0,
                view: SameAgeMode(param: queryValue("view", in: query))
            )
        case "profile" where segments.count == 2:
            return Int(segments[1]).map { DeepLink.person(remoteId: $0, tab: queryValue("tab", in: query).flatMap(PersonTab.init(rawValue:))) }
        case "person-activities" where segments.count == 2:
            return Int(segments[1]).map { DeepLink.person(remoteId: $0, tab: .activities) }
        default:
            return nil
        }
    }

    private static func queryValue(_ name: String, in query: String) -> String? {
        URLComponents(string: "?" + query)?.queryItems?.first { $0.name == name }?.value
    }

    /// Parses a universal link. The host is checked because `onOpenURL` also receives the Google sign-in callback and anything else the app is registered for.
    static func parse(url: URL) -> DeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              let host = components.host,
              host.caseInsensitiveCompare(Self.siteHost) == .orderedSame
        else {
            return nil
        }
        let query = components.percentEncodedQuery.map { "?" + $0 } ?? ""
        return parse(path: components.path + query)
    }

    /// Reads the routing half of a push payload. `data.type` and `data.record_id` are deliberately not consulted — the server picks the destination from one spec table.
    static func parse(pushPayload: [AnyHashable: Any]) -> DeepLink? {
        guard let data = pushPayload["data"] as? [AnyHashable: Any],
              let destination = data["destination"] as? String
        else {
            return nil
        }
        return parse(path: destination)
    }

    /// The host whose links this app answers for, derived from the configured server so the two cannot disagree.
    static var siteHost: String {
        URL(string: AppConstants.defaultServerURL)?.host ?? "familyrecord.app"
    }
}
