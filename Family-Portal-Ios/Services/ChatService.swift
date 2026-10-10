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
    var isLoadingOlder = false
    var hasMoreHistory = true
    var error: String?
    private(set) var unreadCount = 0

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
    private var isViewingChat = false
    private static let typingDebounceInterval: TimeInterval = 1.0

    nonisolated static let pageSize = 50

    /// Where the next page of history starts, counted in messages the server has handed over — deliberately not `messages.count`, which also counts live and locally-sent messages and would step over unfetched history.
    private var historyOffset = 0

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
        // The socket authenticates with the auth cookie, which only `APIClient` keeps fresh. Every connect — reconnects included — asks first, and a handshake the server refused forces a refresh, since the cookie may have expired inside the proactive margin.
        self.webSocketService = ChatWebSocketService(baseURL: baseURL) { [apiClient] handshakeRefused in
            if handshakeRefused {
                _ = try? await apiClient.refreshAccessToken()
            } else {
                await apiClient.ensureFreshAccessToken()
            }
        }

        await webSocketService.setDelegate(self)

        loadLocalMessages()
    }

    // MARK: - Lifecycle

    func onAppear() async {
        isViewingChat = true
        unreadCount = 0
        await connect()
        await loadMessages()
    }

    func onDisappear() async {
        isViewingChat = false
    }

    // MARK: - Connection

    func connect() async {
        await webSocketService.connect()
    }

    func disconnect() async {
        await webSocketService.disconnect()
    }

    // MARK: - Messages

    func loadMessages() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        if let page = await fetchPage(offset: 0) {
            // Never rewind: coming back to the tab after paging through history must not re-fetch pages the user already pulled.
            historyOffset = max(historyOffset, page.received)
            if page.received < Self.pageSize {
                hasMoreHistory = false
            }
        }

        isLoading = false
    }

    func loadOlderMessages() async {
        guard hasMoreHistory, !isLoadingOlder, !isLoading else { return }
        isLoadingOlder = true
        error = nil

        // A page can come back entirely known, so a page of pure duplicates is a page to step past rather than a result. Capped so one pull cannot become an unbounded run of requests.
        var pagesFetched = 0
        while pagesFetched < Self.maxPagesPerPull {
            guard let page = await fetchPage(offset: historyOffset) else { break }
            pagesFetched += 1
            historyOffset += page.received

            if page.received < Self.pageSize {
                hasMoreHistory = false
                break
            }
            if page.added > 0 {
                break
            }
        }

        isLoadingOlder = false
    }

    private static let maxPagesPerPull = 5

    private struct PageResult {
        let received: Int
        let added: Int
    }

    /// Fetches one page and merges it. Returns nil when the request failed, which is the one case that must not move `historyOffset`.
    private func fetchPage(offset: Int) async -> PageResult? {
        do {
            let dtos = try await apiClient.getChatMessages(limit: Self.pageSize, offset: offset)
            let added = merge(dtos)
            try modelContext.save()
            return PageResult(received: dtos.count, added: added)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    private func merge(_ dtos: [ChatMessageDTO]) -> Int {
        var added = 0
        // A page against the whole history: a set, not a scan of every message per incoming one.
        var known = Set(messages.compactMap(\.serverId))

        for dto in dtos {
            guard known.insert(dto.id).inserted else { continue }
            if reconcileSent(dto) {
                continue
            }

            let message = ChatMessage.fromDTO(dto)
            modelContext.insert(message)
            messages.append(message)
            added += 1
        }

        sortMessages()
        return added
    }

    func sendMessage(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let clientMessageId = UUID().uuidString

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

        await deliver(message)
    }

    func retrySendMessage(_ message: ChatMessage) async {
        guard message.sendFailed else { return }

        message.isSending = true
        message.sendFailed = false

        await deliver(message)
    }

    /// Sends a message already on screen, adopting the server's id and time or marking it failed.
    private func deliver(_ message: ChatMessage) async {
        do {
            let responseDTO = try await apiClient.sendMessage(
                content: message.content,
                clientMessageId: message.clientMessageId
            )

            message.serverId = responseDTO.id
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
        guard let remoteId = message.serverId,
              message.userId == currentUserId else {
            return
        }

        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages.remove(at: index)
        }
        modelContext.delete(message)

        do {
            _ = try await apiClient.deleteMessage(id: remoteId)
            try modelContext.save()
        } catch {
            // The local row is gone but the server copy isn't — say so, or the message silently returns on the next pull.
            self.error = error.localizedDescription
        }
    }

    // MARK: - Typing Indicator

    func userIsTyping() {
        let now = Date()

        if let lastSent = lastTypingSent,
           now.timeIntervalSince(lastSent) < Self.typingDebounceInterval {
            return
        }

        lastTypingSent = now

        Task {
            await webSocketService.sendTypingIndicator(isTyping: true)
        }

        typingDebounceTask?.cancel()
        typingDebounceTask = Task {
            // A cancelled sleep throws: the next keystroke rescheduled this, and sending "stopped" now would flicker the indicator off for everyone watching.
            guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
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
        if reconcileSent(dto) {
            try? modelContext.save()
            return
        }

        if dto.userId == currentUserId && dto.clientMessageId.isEmpty {
            if let existing = messages.first(where: { message in
                message.userId == currentUserId
                    && message.remoteId == nil
                    && message.content == dto.content
                    && abs(message.createdAt.timeIntervalSince(dto.createdAt)) < 5
            }) {
                existing.serverId = dto.id
                existing.createdAt = dto.createdAt
                existing.isSending = false
                try? modelContext.save()
                return
            }
        }

        if messages.contains(where: { $0.serverId == dto.id }) {
            return
        }

        let message = ChatMessage.fromDTO(dto)
        modelContext.insert(message)
        messages.append(message)
        sortMessages()
        try? modelContext.save()

        if !isViewingChat, dto.userId != currentUserId {
            unreadCount += 1
        }

        typingUsers.removeValue(forKey: dto.userId)
    }

    func didReceiveDeleteMessage(messageId: Int, userId: Int) {
        if let index = messages.firstIndex(where: { $0.serverId == messageId }) {
            let message = messages[index]
            messages.remove(at: index)
            modelContext.delete(message)
            try? modelContext.save()
        }
    }

    func didReceiveTypingUpdate(userId: Int, userName: String, isTyping: Bool) {
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

        if state == .disconnected || state == .failed {
            typingUsers.removeAll()
        }
    }

    func didReceiveError(_ message: String) {
        error = message
    }

    // MARK: - Helpers

    /// Whether `dto` is a message this device sent, matched by its client id. The local copy takes the server's id and time, and stops reading as failed: a send whose answer was lost on a weak signal still reached the server, and retrying it would post it twice.
    private func reconcileSent(_ dto: ChatMessageDTO) -> Bool {
        guard !dto.clientMessageId.isEmpty, sentClientMessageIds.contains(dto.clientMessageId) else { return false }
        if let existing = messages.first(where: { $0.clientMessageId == dto.clientMessageId }) {
            existing.serverId = dto.id
            existing.createdAt = dto.createdAt
            existing.isSending = false
            existing.sendFailed = false
        }
        return true
    }

    private func loadLocalMessages() {
        let descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        if let localMessages = try? modelContext.fetch(descriptor) {
            messages = localMessages

            // An empty id is "unknown", not a match: inserting it would make every server message lacking one look like a duplicate of our own.
            for msg in localMessages where msg.userId == currentUserId && !msg.clientMessageId.isEmpty {
                sentClientMessageIds.insert(msg.clientMessageId)
            }
        }
    }

    private func sortMessages() {
        messages.sort { $0.createdAt < $1.createdAt }
    }
}
