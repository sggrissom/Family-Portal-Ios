import SwiftUI

struct SyncStatusView: View {
    let isConnected: Bool
    let isSyncing: Bool
    let syncError: String?
    let pendingCount: Int
    let lastSyncDate: Date?

    private var state: SyncState {
        if !isConnected {
            return .offline
        }
        if isSyncing {
            return .syncing
        }
        if syncError != nil {
            return .error
        }
        if pendingCount > 0 {
            return .pending
        }
        return .synced
    }

    var body: some View {
        HStack(spacing: 8) {
            stateIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(stateText)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let detail = stateDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var stateText: String {
        switch state {
        case .offline:
            return "Offline"
        case .syncing:
            return "Syncing..."
        case .error:
            return "Sync Error"
        case .pending:
            return "\(pendingCount) pending"
        case .synced:
            return "Synced"
        }
    }

    private var stateDetail: String? {
        switch state {
        case .error:
            return syncError
        case .synced:
            if let date = lastSyncDate {
                return relativeTime(from: date)
            }
            return nil
        default:
            return nil
        }
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct SyncStatusBadge: View {
    let isConnected: Bool
    let isSyncing: Bool
    let syncError: String?
    let pendingCount: Int

    private var state: SyncState {
        if !isConnected {
            return .offline
        }
        if isSyncing {
            return .syncing
        }
        if syncError != nil {
            return .error
        }
        if pendingCount > 0 {
            return .pending
        }
        return .synced
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            stateIcon
                .font(.system(size: 16))

            if pendingCount > 0 && state == .pending {
                Text("\(pendingCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .clipShape(Capsule())
                    .offset(x: 8, y: -6)
            }
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(.orange)
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

private enum SyncState {
    case offline
    case syncing
    case error
    case pending
    case synced
}

#Preview("Sync Status View") {
    List {
        SyncStatusView(
            isConnected: false,
            isSyncing: false,
            syncError: nil,
            pendingCount: 0,
            lastSyncDate: nil
        )
        SyncStatusView(
            isConnected: true,
            isSyncing: true,
            syncError: nil,
            pendingCount: 0,
            lastSyncDate: nil
        )
        SyncStatusView(
            isConnected: true,
            isSyncing: false,
            syncError: "Network error",
            pendingCount: 0,
            lastSyncDate: nil
        )
        SyncStatusView(
            isConnected: true,
            isSyncing: false,
            syncError: nil,
            pendingCount: 3,
            lastSyncDate: nil
        )
        SyncStatusView(
            isConnected: true,
            isSyncing: false,
            syncError: nil,
            pendingCount: 0,
            lastSyncDate: Date().addingTimeInterval(-300)
        )
    }
}

#Preview("Sync Status Badge") {
    HStack(spacing: 30) {
        SyncStatusBadge(
            isConnected: false,
            isSyncing: false,
            syncError: nil,
            pendingCount: 0
        )
        SyncStatusBadge(
            isConnected: true,
            isSyncing: true,
            syncError: nil,
            pendingCount: 0
        )
        SyncStatusBadge(
            isConnected: true,
            isSyncing: false,
            syncError: nil,
            pendingCount: 5
        )
        SyncStatusBadge(
            isConnected: true,
            isSyncing: false,
            syncError: nil,
            pendingCount: 0
        )
    }
    .padding()
}
