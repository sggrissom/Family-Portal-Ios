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
                onMessagesCountChange: { scrollToBottom(animated: true) },
                onDismissKeyboard: { isInputFocused = false }
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
        let onMessagesCountChange: () -> Void
        var onDismissKeyboard: (() -> Void)?

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
                .onAppear { scrollProxy = proxy }
                .onChange(of: messages.count) { _, _ in
                    onMessagesCountChange()
                }
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
