import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(ChatService.self) private var chatService: ChatService?
    @Environment(AuthService.self) private var authService
    @State private var messageText = ""
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            bodyContent()
        }
    }

    @ViewBuilder
    private func bodyContent() -> some View {
        if let chatService {
            chatContent(chatService: chatService)
        } else {
            ContentUnavailableView(
                "Chat Unavailable",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Sign in to use chat")
            )
        }
    }

    @ViewBuilder
    private func chatContent(chatService: ChatService) -> some View {
        VStack(spacing: 0) {
            // Connection status banner
            ConnectionStatusView(state: chatService.connectionState)

            // A failure loading or sending is otherwise invisible: the pull ends,
            // nothing new appears, and the thread looks like it has no history.
            ChatErrorBanner(message: chatService.error) {
                chatService.error = nil
            }

            // Messages
            MessagesListView(
                messages: chatService.messages,
                isOwnMessage: { userId in
                    userId == authService.currentUser?.id
                },
                onDelete: { message in
                    deleteMessage(message, chatService: chatService)
                },
                onRetry: { message in
                    retryMessage(message, chatService: chatService)
                },
                scrollProxy: $scrollProxy,
                onLatestMessageChange: { scrollToBottom(animated: true) },
                onDismissKeyboard: { isInputFocused = false },
                hasMoreHistory: chatService.hasMoreHistory,
                isLoadingOlder: chatService.isLoadingOlder,
                onLoadOlder: { await chatService.loadOlderMessages() }
            )

            // Typing indicator
            if !chatService.typingUsers.isEmpty {
                TypingIndicatorView(
                    typingUsers: Array(chatService.typingUsers.values)
                )
            }

            // Input area
            MessageInputView(
                text: $messageText,
                isFocused: $isInputFocused,
                onTyping: { chatService.userIsTyping() },
                onSend: { sendMessage(chatService: chatService) }
            )
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await chatService.onAppear()
        }
        .onDisappear {
            isInputFocused = false
            Task {
                await chatService.onDisappear()
            }
        }
    }

    private struct MessagesListView: View {
        let messages: [ChatMessage]
        let isOwnMessage: (_ userId: Int) -> Bool
        let onDelete: (_ message: ChatMessage) -> Void
        let onRetry: (_ message: ChatMessage) -> Void
        @Binding var scrollProxy: ScrollViewProxy?
        let onLatestMessageChange: () -> Void
        var onDismissKeyboard: (() -> Void)?
        let hasMoreHistory: Bool
        let isLoadingOlder: Bool
        let onLoadOlder: () async -> Void

        private var groupedMessages: [(date: Date, messages: [ChatMessage])] {
            let grouped = Dictionary(grouping: messages) {
                Calendar.current.startOfDay(for: $0.createdAt)
            }
            return grouped
                .map { (date: $0.key, messages: $0.value) }
                .sorted { $0.date < $1.date }
        }

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        historyHeader

                        ForEach(groupedMessages, id: \.date) { group in
                            DateSeparatorView(date: group.date)

                            ForEach(group.messages, id: \.id) { message in
                                MessageBubbleView(
                                    message: message,
                                    isOwnMessage: isOwnMessage(message.userId),
                                    onDelete: { onDelete(message) },
                                    onRetry: { onRetry(message) }
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding()
                    .contentShape(Rectangle())
                    .onTapGesture { onDismissKeyboard?() }
                }
                .scrollDismissesKeyboard(.interactively)
                // A conversation opens at its live end.
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                // Older messages arrive above what the user is reading. Anchoring
                // size changes to the bottom keeps the thread still while the page
                // is inserted, instead of sliding it down by a screenful.
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .refreshable { await onLoadOlder() }
                .onAppear { scrollProxy = proxy }
                // Keyed on the newest message rather than the count: loading
                // history also changes the count, and following it to the bottom
                // would undo the pull the user just made.
                .onChange(of: messages.last?.id) { _, _ in
                    onLatestMessageChange()
                }
            }
        }

        @ViewBuilder
        private var historyHeader: some View {
            if isLoadingOlder {
                ProgressView()
                    .padding(.vertical, 8)
            } else if !hasMoreHistory && !messages.isEmpty {
                Text("Beginning of conversation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    /// Chat's own errors stay on the chat screen rather than going through
    /// `ErrorPresenter`: they are per-conversation, and unlike the sheets that
    /// report through the app-scoped alert, this view is still on screen to show
    /// them.
    private struct ChatErrorBanner: View {
        let message: String?
        let onDismiss: () -> Void

        var body: some View {
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)

                    Text(message)
                        .font(.caption)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .accessibilityLabel("Dismiss error")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.red)
            }
        }
    }

    private func sendMessage(chatService: ChatService) {
        let content = messageText
        messageText = ""
        chatService.userStoppedTyping()

        Task {
            await chatService.sendMessage(content)
            scrollToBottom(animated: true)
        }
    }

    private func deleteMessage(_ message: ChatMessage, chatService: ChatService) {
        Task {
            await chatService.deleteMessage(message)
        }
    }

    private func retryMessage(_ message: ChatMessage, chatService: ChatService) {
        Task {
            await chatService.retrySendMessage(message)
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard let chatService,
              let last: ChatMessage = chatService.messages.last else { return }

        if animated {
            withAnimation {
                scrollProxy?.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            scrollProxy?.scrollTo(last.id, anchor: .bottom)
        }
    }
}
