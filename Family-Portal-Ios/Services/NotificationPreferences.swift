import Foundation
import OSLog

// The account's push preferences (backend/notification_preferences.go) — the web's Notifications section on `/settings`.
// They follow the account, not the phone, so they are read from and written to the server and never held on the device beyond the screen showing them.

/// `NotificationPreferencesResponse`, and the update request, which carries the same two fields. Both are always sent: the server stores exactly what it is given.
nonisolated struct NotificationPreferencesDTO: Codable, Sendable, Equatable {
    var chatEnabled: Bool
    var showMessageText: Bool

    init(chatEnabled: Bool, showMessageText: Bool) {
        self.chatEnabled = chatEnabled
        self.showMessageText = showMessageText
    }

    private enum CodingKeys: String, CodingKey { case chatEnabled, showMessageText }

    /// A missing field takes the server's own default — chat on, message text off — so a key the server leaves out never turns previews on.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chatEnabled = try container.decodeIfPresent(Bool.self, forKey: .chatEnabled) ?? true
        showMessageText = try container.decodeIfPresent(Bool.self, forKey: .showMessageText) ?? false
    }
}

nonisolated struct UpdateNotificationPreferencesResponseDTO: Decodable, Sendable {
    let preferences: NotificationPreferencesDTO
}

/// The Notifications section's state. The toggles show the last values the server confirmed, moved optimistically while a save is in flight and put back if it fails, so a failed save never looks like a successful one.
@MainActor
@Observable
final class NotificationPreferencesModel {
    enum Field {
        case chatEnabled, showMessageText
    }

    /// What the server last said. Nil until it has said anything.
    private(set) var confirmed: NotificationPreferencesDTO?
    /// What the toggles show: `confirmed`, or the change being saved.
    private(set) var shown: NotificationPreferencesDTO?
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// The first read failed or could not be made; the toggles stay hidden rather than showing defaults that may not be the account's.
    private(set) var loadFailed = false
    private(set) var saveError: String?
    /// The last change was saved — for the confirmation line.
    private(set) var didSave = false

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func load(isConnected: Bool) async {
        guard !isLoading else { return }
        guard isConnected else {
            if confirmed == nil { loadFailed = true }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let preferences: NotificationPreferencesDTO = try await apiClient.callRPC(.getNotificationPreferences, payload: EmptyRequestDTO())
            // A save that started while this read was in flight has the newer word.
            guard !isSaving else { return }
            confirmed = preferences
            shown = preferences
            loadFailed = false
        } catch {
            AppLog.ui.error("Notification preferences unavailable: \(String(describing: error), privacy: .public)")
            if confirmed == nil { loadFailed = true }
        }
    }

    /// Saves one change, sending both fields as they would then stand. Online only, one save at a time; on any failure the toggle goes back to what the server holds.
    func set(_ field: Field, to value: Bool, isConnected: Bool) async {
        guard let base = confirmed, !isSaving else { return }
        var next = shown ?? base
        switch field {
        case .chatEnabled: next.chatEnabled = value
        case .showMessageText: next.showMessageText = value
        }
        guard next != shown else { return }

        didSave = false
        guard isConnected else {
            saveError = Copy.notifications.offline
            shown = base
            return
        }

        shown = next
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let response: UpdateNotificationPreferencesResponseDTO = try await apiClient.callRPC(.updateNotificationPreferences, payload: next)
            confirmed = response.preferences
            shown = response.preferences
            didSave = true
        } catch {
            AppLog.ui.error("Notification preferences not saved: \(String(describing: error), privacy: .public)")
            shown = confirmed
            saveError = Copy.notifications.saveFailed
        }
    }
}
