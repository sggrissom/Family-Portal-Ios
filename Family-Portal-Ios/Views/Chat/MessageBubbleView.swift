import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let isOwnMessage: Bool
    let onDelete: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwnMessage {
                Spacer(minLength: 60)
            } else {
                UserAvatarView(name: message.userName, size: 32)
            }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                if !isOwnMessage {
                    Text(message.userName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    if message.sendFailed {
                        Button(action: onRetry) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    Text(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(bubbleBackground)
                        .foregroundStyle(isOwnMessage ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(pendingOverlay)

                    if message.isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contextMenu {
                if isOwnMessage && !message.isSending && !message.sendFailed {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }

                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            if !isOwnMessage {
                Spacer(minLength: 60)
            }
        }
    }

    private var bubbleBackground: Color {
        isOwnMessage ? .accentColor : Color(.systemGray5)
    }

    @ViewBuilder
    private var pendingOverlay: some View {
        if message.isSending || message.sendFailed {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [4])
                )
                .foregroundStyle(message.sendFailed ? .red : .secondary)
        }
    }
}
