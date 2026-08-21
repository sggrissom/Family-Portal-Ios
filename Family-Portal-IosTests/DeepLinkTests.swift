import Foundation
import Testing
@testable import Family_Portal_Ios

/// The push payload has carried a `destination` since it was versioned, and the
/// server publishes an app-site association claiming exactly the paths the app
/// has a screen for. This is the piece in the middle: turning one of those
/// strings into somewhere to go.
///
/// The cases below are written against the server's own list — `pushEventSpecs`
/// in `backend/push_worker.go` and `universalLinkPaths` in
/// `backend/universal_links.go`. A path claimed there and unparsed here is a
/// link that opens the app and then does nothing.
@Suite("Deep links")
struct DeepLinkTests {

    // MARK: - Paths

    @Test("Every destination the server can send is understood", arguments: [
        // The two `pushEventSpecs` destinations, which are the only ones a
        // notification carries today.
        ("/chat", DeepLink.chat),
        ("/settings", DeepLink.settings),
        // The rest of the association's path list.
        ("/photos", DeepLink.photos),
        ("/family-timeline", DeepLink.timeline),
        ("/profile/7", DeepLink.person(remoteId: 7)),
        ("/person-activities/7", DeepLink.personActivities(remoteId: 7)),
    ])
    func knownPaths(path: String, expected: DeepLink) {
        #expect(DeepLink.parse(path: path) == expected)
    }

    @Test("A query or fragment does not change where a link goes")
    func queryAndFragmentAreIgnored() {
        #expect(DeepLink.parse(path: "/chat?from=push") == .chat)
        #expect(DeepLink.parse(path: "/profile/7#growth") == .person(remoteId: 7))
    }

    @Test("Paths the app has no screen for are refused", arguments: [
        "/",
        "/privacy",
        "/admin/users",
        "/import",
        // Claiming this would open the app on a reset token it cannot spend.
        "/reset-password",
        // A person id has to be a number; the local store is keyed by UUID and
        // nothing resolves a name.
        "/profile/ada",
        // Trailing segments are not a prefix match: /profile/7/edit is an
        // editor the app does not have.
        "/profile/7/edit",
        "/chat/12",
    ])
    func unknownPathsAreRefused(path: String) {
        #expect(DeepLink.parse(path: path) == nil)
    }

    // MARK: - URLs

    @Test("A link to this site routes")
    func siteURLRoutes() throws {
        let url = try #require(URL(string: "https://familyrecord.app/chat"))
        #expect(DeepLink.parse(url: url) == .chat)
    }

    /// `onOpenURL` sees everything the app is registered for, including the
    /// Google sign-in callback. A URL pointing somewhere else must never be read
    /// as a route into this app.
    @Test("A link to anywhere else is refused", arguments: [
        "https://example.com/chat",
        "https://familyrecord.app.evil.test/chat",
        "http://familyrecord.app/chat",
        "com.googleusercontent.apps.123://oauth/callback",
    ])
    func foreignURLsAreRefused(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(DeepLink.parse(url: url) == nil)
    }

    @Test("The host is matched without regard to case")
    func hostIsCaseInsensitive() throws {
        let url = try #require(URL(string: "https://FamilyRecord.app/photos"))
        #expect(DeepLink.parse(url: url) == .photos)
    }

    // MARK: - Push payloads

    /// The shape `push_worker.go` sends. `type` and `record_id` are present and
    /// deliberately not consulted — the server picks the destination from one
    /// spec table so that a new event type does not need a new branch here.
    private static func chatPush(destination: String = "/chat") -> [AnyHashable: Any] {
        [
            "aps": ["alert": ["title": "New message", "body": "…"], "category": "chat_message"],
            "data": [
                "v": 1,
                "type": "chat_message",
                "record_id": 812,
                "destination": destination,
                "family_id": 2,
                "sender_id": 4,
                "message_id": 812
            ]
        ]
    }

    @Test("A chat notification routes to chat")
    func chatPushRoutes() {
        #expect(DeepLink.parse(pushPayload: Self.chatPush()) == .chat)
    }

    @Test("An event this build has never heard of still routes by destination")
    func unknownEventTypeStillRoutes() {
        var payload = Self.chatPush(destination: "/photos")
        var data = payload["data"] as! [AnyHashable: Any]
        data["type"] = "photo_ready_in_some_future_release"
        payload["data"] = data

        #expect(DeepLink.parse(pushPayload: payload) == .photos)
    }

    /// Not a parameterized test: `[AnyHashable: Any]` is not `Sendable`, and
    /// four `#expect`s say the same thing without asking the test runner to
    /// carry a dictionary of `Any` across an isolation boundary.
    @Test("A payload with nothing to route on is refused")
    func unroutablePayloadsAreRefused() {
        // Nothing at all.
        #expect(DeepLink.parse(pushPayload: [:]) == nil)
        // An alert with no routing half — which is what a payload sent by a
        // server older than the versioning looks like.
        #expect(DeepLink.parse(pushPayload: ["aps": ["alert": "hello"]]) == nil)
        // A routing half with no destination.
        #expect(DeepLink.parse(pushPayload: ["data": ["v": 1, "type": "chat_message"]]) == nil)
        // A destination this build has no screen for.
        #expect(DeepLink.parse(pushPayload: ["data": ["destination": "/nowhere-in-particular"]]) == nil)
    }

    // MARK: - Router

    @MainActor
    @Test("A link waits until something claims it")
    func linkIsHeldUntilClaimed() {
        let router = DeepLinkRouter()
        router.open(.chat)

        #expect(router.pending == .chat)
        // The wrong claimant leaves it alone, which is what keeps the tab
        // switch from consuming a link the navigation stack still has to act on.
        #expect(router.claim { $0 == .photos } == nil)
        #expect(router.pending == .chat)

        #expect(router.claim { $0 == .chat } == .chat)
        #expect(router.pending == nil)
    }

    @MainActor
    @Test("An unroutable URL does not park anything")
    func unroutableURLLeavesNothingPending() throws {
        let router = DeepLinkRouter()
        router.open(url: try #require(URL(string: "https://example.com/chat")))

        // Parking it would mean the next screen to look for a link picks up
        // something nobody asked for.
        #expect(router.pending == nil)
    }

    @MainActor
    @Test("A second link replaces the first")
    func latestLinkWins() {
        let router = DeepLinkRouter()
        router.open(.chat)
        router.open(.photos)

        #expect(router.pending == .photos)
    }

    @MainActor
    @Test("Clearing drops a link a signed-out account left behind")
    func clearDropsPending() {
        let router = DeepLinkRouter()
        router.open(.person(remoteId: 7))
        router.clear()

        #expect(router.pending == nil)
    }
}
