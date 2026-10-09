import Foundation

// MARK: - Chat Message DTOs

/// Keys match `type ChatMessage` in backend/chat.go, which marshals camelCase. Author identity and timestamp drive bubble alignment and date grouping, so those stay required and a missing key fails loudly rather than defaulting.
nonisolated struct ChatMessageDTO: Codable, Sendable {
    let id: Int
    @OrZero var familyId: Int
    let userId: Int
    @OrZero var userName: String
    let content: String
    let createdAt: Date
    @OrZero var clientMessageId: String
}

// MARK: - Request/Response DTOs

nonisolated struct SendMessageRequestDTO: Encodable, Sendable {
    let content: String
    let clientMessageId: String
}

nonisolated struct SendMessageResponseDTO: Codable, Sendable {
    let message: ChatMessageDTO
}

nonisolated struct GetChatMessagesRequestDTO: Encodable, Sendable {
    let limit: Int
    /// Counted back from the *newest* message, so offset 0 is the live end and each further page is older. A page still arrives oldest-first within itself.
    let offset: Int
}

nonisolated struct GetChatMessagesResponseDTO: Codable, Sendable {
    let messages: [ChatMessageDTO]
}

nonisolated struct DeleteMessageRequestDTO: Encodable, Sendable {
    let messageId: Int

    // backend/chat.go `DeleteMessageRequest` reads `id`.
    enum CodingKeys: String, CodingKey {
        case messageId = "id"
    }
}

nonisolated struct DeleteMessageResponseDTO: Codable, Sendable {
    let success: Bool
}

// MARK: - WebSocket Message Types

/// Wire values from `backend/websocket_chat.go`. The server uses the same value in both directions.
enum WSMessageType: String, Codable, Sendable {
    case newMessage = "new_message"
    case deleteMessage = "delete_message"
    case userTyping = "user_typing"
    case userOnline = "user_online"
    case userOffline = "user_offline"
    case heartbeat = "heartbeat"
    case error = "error"
}

// MARK: - WebSocket Payloads
// `nonisolated` keeps their Codable conformances off the main actor, so `ChatWebSocketService` can decode them from its own actor.

nonisolated struct WSNewMessagePayload: Codable, Sendable {
    let message: ChatMessageDTO
}

nonisolated struct WSDeleteMessagePayload: Codable, Sendable {
    let messageId: Int
    let userId: Int
}

nonisolated struct WSTypingPayload: Codable, Sendable {
    let userId: Int
    let userName: String
    let isTyping: Bool
}

nonisolated struct WSUserStatusPayload: Codable, Sendable {
    let userId: Int
    let userName: String
    let isOnline: Bool
}

// MARK: - WebSocket Outgoing Messages

/// Envelope for the two message types the server accepts from a client (`user_typing` and `heartbeat`).
nonisolated struct WSOutgoingMessage<Payload: Encodable>: Encodable {
    let type: WSMessageType
    let payload: Payload
}

nonisolated struct WSTypingIndicatorPayload: Encodable {
    let isTyping: Bool
}
