import SwiftUI

struct ConnectionStatusView: View {
    let state: WebSocketConnectionState

    var body: some View {
        switch state {
        case .connected:
            EmptyView()

        case .connecting:
            statusBanner(
                text: "Connecting...",
                color: .orange,
                showProgress: true
            )

        case .reconnecting(let attempt):
            statusBanner(
                text: "Reconnecting (attempt \(attempt))...",
                color: .orange,
                showProgress: true
            )

        case .disconnected:
            statusBanner(
                text: "Disconnected",
                color: .gray,
                showProgress: false
            )

        case .failed:
            statusBanner(
                text: "Connection failed",
                color: .red,
                showProgress: false
            )
        }
    }

    @ViewBuilder
    private func statusBanner(text: String, color: Color, showProgress: Bool) -> some View {
        HStack(spacing: 8) {
            if showProgress {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(.white)
            } else {
                Image(systemName: "wifi.slash")
                    .font(.caption)
            }

            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color)
    }
}
