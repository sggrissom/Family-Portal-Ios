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
    /// Turns false the first time a page comes back short, and never turns back
    /// on: a page that did not fill means the conversation's first message is on
    /// screen, and everything written after it is newer, not older.
    var hasMoreHistory = true
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

    /// One page of history. `GetChatMessages` caps a page at 200; 50 keeps the
    /// first paint cheap and makes each pull a small request.
    nonisolated static let pageSize = 50

    /// Where the next page of history starts, counted in messages the server has
    /// already handed over.
    ///
    /// Deliberately not `messages.count`. The list also holds messages this
    /// device sent and messages the socket delivered live, and the server's
    /// offset counts only its own ordering — so counting the whole list would
    /// step *over* history that was never fetched. Messages written while the
    /// user reads slide the window the other way, which makes the next page
    /// overlap what is already on screen; `merge` dedups that, and an overlap is
    /// the safe direction to be wrong in.
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

    /// Loads the newest page. `GetChatMessages` counts its window back from the
    /// most recent message, so offset 0 is the live end of the conversation.
    func loadMessages() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        if let page = await fetchPage(offset: 0) {
            // Never rewind: coming back to the tab after paging through history
            // must not re-fetch pages the user already pulled, or the next pull
            // would appear to do nothing until it caught back up.
            historyOffset = max(historyOffset, page.received)
            if page.received < Self.pageSize {
                hasMoreHistory = false
            }
        }

        isLoading = false
    }

    /// Loads the page before the oldest one fetched so far, for the pull at the
    /// top of the thread.
    func loadOlderMessages() async {
        guard hasMoreHistory, !isLoadingOlder, !isLoading else { return }
        isLoadingOlder = true
        error = nil

        // A pull should either put older messages on screen or reach the start of
        // the conversation. A page can come back entirely known — the store keeps
        // every message this device has ever seen, while `historyOffset` starts
        // each session at zero — so a page of pure duplicates is a page to step
        // past, not a result. Capped so a long local history cannot turn one pull
        // into an unbounded run of requests.
        //
        // Seeding the offset from the local message count would skip the walk,
        // but only by assuming the store holds an unbroken run of the newest
        // messages. A device that missed a month of chat holds an old run
        // instead, and starting there would leave a hole in the middle of the
        // thread that nothing later fills in.
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

    /// How much already-known history one pull will walk past looking for
    /// something new.
    private static let maxPagesPerPull = 5

    private struct PageResult {
        /// What the server sent, duplicates included — this is what moves the
        /// offset, since the offset counts the server's ordering and not ours.
        let received: Int
        /// What was actually new to this device, which is what the user sees.
        let added: Int
    }

    /// Fetches one page and merges it. Returns nil when the request failed, which
    /// is the one case that must not move `historyOffset`.
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

    /// Inserts everything in `dtos` this device does not already hold, and
    /// answers with how many that was.
    @discardableResult
    private func merge(_ dtos: [ChatMessageDTO]) -> Int {
        var added = 0

        for dto in dtos {
            // Skip duplicates
            let remoteIdStr = String(dto.id)
            if messages.contains(where: { $0.remoteId == remoteIdStr }) {
                continue
            }
            if !dto.clientMessageId.isEmpty, sentClientMessageIds.contains(dto.clientMessageId) {
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
            // The local row is already gone, but the server copy isn't — say so,
            // otherwise the message silently returns on the next pull.
            self.error = error.localizedDescription
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
        if !dto.clientMessageId.isEmpty, sentClientMessageIds.contains(dto.clientMessageId) {
            // Update optimistic message with server data
            if let existing = messages.first(where: { $0.clientMessageId == dto.clientMessageId }) {
                existing.remoteId = String(dto.id)
                existing.createdAt = dto.createdAt
                existing.isSending = false
                try? modelContext.save()
            }
            return
        }

        // Fallback: match our own messages when clientMessageId is missing from server
        if dto.userId == currentUserId && dto.clientMessageId.isEmpty {
            if let existing = messages.first(where: { message in
                message.userId == currentUserId
                    && message.remoteId == nil
                    && message.content == dto.content
                    && abs(message.createdAt.timeIntervalSince(dto.createdAt)) < 5
            }) {
                existing.remoteId = String(dto.id)
                existing.createdAt = dto.createdAt
                existing.isSending = false
                try? modelContext.save()
                return
            }
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

            // Populate sent IDs for deduplication. An empty id is "unknown",
            // not a match — inserting it would make every server message that
            // lacks one look like a duplicate of our own.
            for msg in localMessages where msg.userId == currentUserId && !msg.clientMessageId.isEmpty {
                sentClientMessageIds.insert(msg.clientMessageId)
            }
        }
    }

    private func sortMessages() {
        messages.sort { $0.createdAt < $1.createdAt }
    }
}
