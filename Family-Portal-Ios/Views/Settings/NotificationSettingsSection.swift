import SwiftUI
import UserNotifications

/// Settings' **Notifications**: the account's chat-notification and message-text preferences, saved to the server as each toggle changes — and, apart from them, whether iOS lets notifications through to this iPhone at all. The two are different switches, and the section says which is which.
struct NotificationSettingsSection: View {
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = NotificationPreferencesModel()
    @State private var systemStatus: UNAuthorizationStatus?

    private var isConnected: Bool { network.isConnected }

    var body: some View {
        Section {
            if let shown = model.shown {
                toggle(Copy.notifications.chat, detail: Copy.notifications.chatDetail, isOn: shown.chatEnabled, field: .chatEnabled)
                toggle(Copy.notifications.showText, detail: Copy.notifications.showTextDetail, isOn: shown.showMessageText, field: .showMessageText)

                if let saveError = model.saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if model.didSave {
                    Label(Copy.notifications.saved, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            } else if model.loadFailed {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isConnected ? Copy.notifications.loadFailed : Copy.notifications.offline)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(Copy.notifications.retry) {
                        Task { await model.load(isConnected: isConnected) }
                    }
                    .font(.footnote)
                }
            } else {
                ProgressView()
            }

            systemStatusRow
        } header: {
            Text(Copy.notifications.title)
        } footer: {
            Text(Copy.notifications.accountNote)
        }
        .task {
            await model.load(isConnected: isConnected)
            await refreshSystemStatus()
        }
        // Coming back from iOS Settings is the moment the answer is likely to have changed.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshSystemStatus() }
            }
        }
    }

    private func toggle(_ title: String, detail: String, isOn: Bool, field: NotificationPreferencesModel.Field) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { value in Task { await model.set(field, to: value, isConnected: isConnected) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(model.isSaving)
    }

    @ViewBuilder
    private var systemStatusRow: some View {
        switch systemStatus {
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label(Copy.notifications.systemOff, systemImage: "bell.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(Copy.notifications.openSystemSettings) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.footnote)
            }
        case .notDetermined:
            Label(Copy.notifications.systemNotAsked, systemImage: "bell")
                .font(.footnote)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private func refreshSystemStatus() async {
        systemStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
