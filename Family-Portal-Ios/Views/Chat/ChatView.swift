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
    }

    @ViewBuilder
    private func chatContent(chatService: ChatService) -> some View {
        VStack(spacing: 0) {
            // Connection status banner
            ConnectionStatusView(state: chatService.connectionState)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(chatService.messages, id: \.id) { message in
                            MessageBubbleView(
                                message: message,
                                isOwnMessage: message.userId == authService.currentUser?.userId,
                                onDelete: { deleteMessage(message, chatService: chatService) },
                                onRetry: { retryMessage(message, chatService: chatService) }
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: chatService.messages.count) { _, _ in
                    scrollToBottom(animated: true)
                }
            }

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
            Task {
                await chatService.onDisappear()
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
              let lastMessage = chatService.messages.last else { return }

        if animated {
            withAnimation {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        } else {
            scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}
