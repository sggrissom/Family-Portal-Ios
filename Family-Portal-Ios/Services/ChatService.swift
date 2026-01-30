import Foundation
import SwiftData

@Observable
@MainActor
final class ChatService: ChatWebSocketDelegate {
    // MARK: - Published State
    var messages: [ChatMessage] = []
    var connectionState: WebSocketConnectionState = .disconnected
    var onlineUsers: Set<Int> = []
    var typingUsers: [Int: String] = [:] // userId -> userName
    var isLoading = false
    var error: String?

    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let apiClient: APIClient
    private let webSocketService: ChatWebSocketService
    private let currentUserId: Int
    private let currentUserName: String

    // MARK: - Private State
    private var sentClientMessageIds: Set<String> = []
    private var typingDebounceTask: Task<Void, Never>?
    private var lastTypingSent: Date?
    private static let typingDebounceInterval: TimeInterval = 1.0

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        apiClient: APIClient,
        currentUserId: Int,
        currentUserName: String
    ) async {
        self.modelContext = modelContext
        self.apiClient = apiClient
        self.currentUserId = currentUserId
        self.currentUserName = currentUserName

        let baseURL = await apiClient.getBaseURL()
        self.webSocketService = ChatWebSocketService(baseURL: baseURL)

        await webSocketService.setDelegate(self)

        loadLocalMessages()
    }

    // MARK: - Lifecycle

    func onAppear() async {
        await connect()
        await loadMessages()
    }

    func onDisappear() async {
        await disconnect()
    }

    // MARK: - Connection

    func connect() async {
        await webSocketService.connect()
    }

    func disconnect() async {
        await webSocketService.disconnect()
    }

    // MARK: - Messages

    func loadMessages(limit: Int = 50, offset: Int = 0) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let dtos = try await apiClient.getChatMessages(limit: limit, offset: offset)

            for dto in dtos {
                // Skip duplicates
                let remoteIdStr = String(dto.id)
                if messages.contains(where: { $0.remoteId == remoteIdStr }) {
                    continue
                }
                if sentClientMessageIds.contains(dto.clientMessageId) {
                    continue
                }

                let message = ChatMessage.fromDTO(dto)
                modelContext.insert(message)
                messages.append(message)
            }

            sortMessages()
            try modelContext.save()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func sendMessage(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let clientMessageId = UUID().uuidString

        // Optimistic insert
        let message = ChatMessage(
            clientMessageId: clientMessageId,
            userId: currentUserId,
            userName: currentUserName,
            content: trimmed,
            createdAt: Date(),
            isSending: true,
            sendFailed: false
        )

        sentClientMessageIds.insert(clientMessageId)
        modelContext.insert(message)
        messages.append(message)
        sortMessages()

        do {
            let responseDTO = try await apiClient.sendMessage(
                content: trimmed,
                clientMessageId: clientMessageId
            )

            // Update with server response
            message.remoteId = String(responseDTO.id)
            message.createdAt = responseDTO.createdAt
            message.isSending = false

            try modelContext.save()
        } catch {
            message.isSending = false
            message.sendFailed = true
            try? modelContext.save()
            self.error = error.localizedDescription
        }
    }

    func retrySendMessage(_ message: ChatMessage) async {
        guard message.sendFailed else { return }

        message.isSending = true
        message.sendFailed = false

        do {
            let responseDTO = try await apiClient.sendMessage(
                content: message.content,
                clientMessageId: message.clientMessageId
            )

            message.remoteId = String(responseDTO.id)
            message.createdAt = responseDTO.createdAt
            message.isSending = false

            try modelContext.save()
        } catch {
            message.isSending = false
            message.sendFailed = true
            try? modelContext.save()
            self.error = error.localizedDescription
        }
    }

    func deleteMessage(_ message: ChatMessage) async {
        guard let remoteIdStr = message.remoteId,
              let remoteId = Int(remoteIdStr),
              message.userId == currentUserId else {
            return
        }

        // Optimistic delete
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: index)
        }
        modelContext.delete(message)

        do {
            _ = try await apiClient.deleteMessage(id: remoteId)
            try modelContext.save()
        } catch {
            // Message already deleted locally, just log
            print("[Chat] Delete failed: \(error)")
        }
    }

    // MARK: - Typing Indicator

    func userIsTyping() {
        let now = Date()

        // Debounce to avoid spamming
        if let lastSent = lastTypingSent,
           now.timeIntervalSince(lastSent) < Self.typingDebounceInterval {
            return
        }

        lastTypingSent = now

        Task {
            await webSocketService.sendTypingIndicator(isTyping: true)
        }

        // Auto-clear typing after 3 seconds of no activity
        typingDebounceTask?.cancel()
        typingDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await webSocketService.sendTypingIndicator(isTyping: false)
        }
    }

    func userStoppedTyping() {
        typingDebounceTask?.cancel()
        Task {
            await webSocketService.sendTypingIndicator(isTyping: false)
        }
    }

    // MARK: - ChatWebSocketDelegate

    func didReceiveMessage(_ dto: ChatMessageDTO) {
        // Skip if we sent this message (already have it optimistically)
        if sentClientMessageIds.contains(dto.clientMessageId) {
            // Update optimistic message with server data
            if let existing = messages.first(where: { $0.clientMessageId == dto.clientMessageId }) {
                existing.remoteId = String(dto.id)
                existing.createdAt = dto.createdAt
                existing.isSending = false
                try? modelContext.save()
            }
            return
        }

        // Skip duplicates by remoteId
        let remoteIdStr = String(dto.id)
        if messages.contains(where: { $0.remoteId == remoteIdStr }) {
            return
        }

        let message = ChatMessage.fromDTO(dto)
        modelContext.insert(message)
        messages.append(message)
        sortMessages()
        try? modelContext.save()

        // Clear typing indicator for this user
        typingUsers.removeValue(forKey: dto.userId)
    }

    func didReceiveDeleteMessage(messageId: Int, userId: Int) {
        let remoteIdStr = String(messageId)
        if let index = messages.firstIndex(where: { $0.remoteId == remoteIdStr }) {
            let message = messages[index]
            messages.remove(at: index)
            modelContext.delete(message)
            try? modelContext.save()
        }
    }

    func didReceiveTypingUpdate(userId: Int, userName: String, isTyping: Bool) {
        // Don't show our own typing
        guard userId != currentUserId else { return }

        if isTyping {
            typingUsers[userId] = userName
        } else {
            typingUsers.removeValue(forKey: userId)
        }
    }

    func didReceiveUserOnline(userId: Int, userName: String) {
        onlineUsers.insert(userId)
    }

    func didReceiveUserOffline(userId: Int, userName: String) {
        onlineUsers.remove(userId)
        typingUsers.removeValue(forKey: userId)
    }

    func didChangeConnectionState(_ state: WebSocketConnectionState) {
        connectionState = state

        // Clear typing indicators on disconnect
        if state == .disconnected || state == .failed {
            typingUsers.removeAll()
        }
    }

    func didReceiveError(_ message: String) {
        error = message
    }

    // MARK: - Helpers

    private func loadLocalMessages() {
        let descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        if let localMessages = try? modelContext.fetch(descriptor) {
            messages = localMessages

            // Populate sent IDs for deduplication
            for msg in localMessages where msg.userId == currentUserId {
                sentClientMessageIds.insert(msg.clientMessageId)
            }
        }
    }

    private func sortMessages() {
        messages.sort { $0.createdAt < $1.createdAt }
    }
}
