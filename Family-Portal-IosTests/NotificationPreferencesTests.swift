import Foundation
import Testing
@testable import Family_Portal_Ios

/// Payloads shaped on backend/notification_preferences.go.
@MainActor
@Suite("Notification preferences")
struct NotificationPreferencesTests {

    private func body(_ request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    private func loaded(_ server: FakeHTTPServer, chat: Bool = true, text: Bool = false) async -> NotificationPreferencesModel {
        server.route("rpc/GetNotificationPreferences", respond: .json(["chatEnabled": chat, "showMessageText": text]))
        let model = NotificationPreferencesModel(apiClient: server.apiClient())
        await model.load(isConnected: true)
        return model
    }

    // MARK: - Decoding

    @Test("Missing fields take the server's defaults: chat on, message text off")
    func defaults() throws {
        let decoded = try APIClient.decode(NotificationPreferencesDTO.self, from: Fixture.data([String: Any]()))
        #expect(decoded == NotificationPreferencesDTO(chatEnabled: true, showMessageText: false))
    }

    // MARK: - Loading

    @Test("Changes made on the web show when the screen loads")
    func loadsFromServer() async {
        let server = FakeHTTPServer()
        let model = await loaded(server, chat: false, text: true)
        #expect(model.shown == NotificationPreferencesDTO(chatEnabled: false, showMessageText: true))
        #expect(model.loadFailed == false)
    }

    @Test("A failed first read shows no toggles rather than defaults")
    func loadFailure() async {
        let server = FakeHTTPServer()
        server.route("rpc/GetNotificationPreferences", respond: .status(500))
        let model = NotificationPreferencesModel(apiClient: server.apiClient())
        await model.load(isConnected: true)
        #expect(model.shown == nil)
        #expect(model.loadFailed)
    }

    @Test("Offline, nothing is asked and nothing is shown")
    func loadOffline() async {
        let server = FakeHTTPServer()
        let model = NotificationPreferencesModel(apiClient: server.apiClient())
        await model.load(isConnected: false)
        #expect(model.loadFailed)
        #expect(server.allRequests.isEmpty)
    }

    // MARK: - Saving

    @Test("A change sends both fields and takes the server's answer")
    func saves() async throws {
        let server = FakeHTTPServer()
        let model = await loaded(server)
        server.route("rpc/UpdateNotificationPreferences", respond: .json(["preferences": ["chatEnabled": true, "showMessageText": true]]))

        await model.set(.showMessageText, to: true, isConnected: true)

        let sent = try body(try #require(server.requests(for: "rpc/UpdateNotificationPreferences").first))
        #expect(sent["chatEnabled"] as? Bool == true)
        #expect(sent["showMessageText"] as? Bool == true)
        #expect(model.confirmed?.showMessageText == true)
        #expect(model.didSave)
        #expect(model.saveError == nil)
    }

    @Test("A failed save puts the toggle back and never reads as saved")
    func failedSaveReverts() async {
        let server = FakeHTTPServer()
        let model = await loaded(server)
        server.route("rpc/UpdateNotificationPreferences", respond: .status(500))

        await model.set(.chatEnabled, to: false, isConnected: true)

        #expect(model.shown?.chatEnabled == true)
        #expect(model.confirmed?.chatEnabled == true)
        #expect(model.didSave == false)
        #expect(model.saveError == Copy.notifications.saveFailed)
    }

    @Test("Offline, a change is refused without being sent")
    func offlineSave() async {
        let server = FakeHTTPServer()
        let model = await loaded(server)

        await model.set(.chatEnabled, to: false, isConnected: false)

        #expect(server.requests(for: "rpc/UpdateNotificationPreferences").isEmpty)
        #expect(model.shown?.chatEnabled == true)
        #expect(model.saveError == Copy.notifications.offline)
    }

    @Test("Turning chat off leaves message text as it was")
    func oneFieldAtATime() async throws {
        let server = FakeHTTPServer()
        let model = await loaded(server, chat: true, text: false)
        server.route("rpc/UpdateNotificationPreferences", respond: .json(["preferences": ["chatEnabled": false, "showMessageText": false]]))

        await model.set(.chatEnabled, to: false, isConnected: true)

        let sent = try body(try #require(server.requests(for: "rpc/UpdateNotificationPreferences").first))
        #expect(sent["showMessageText"] as? Bool == false)
    }
}
