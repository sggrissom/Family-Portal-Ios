import Foundation

// MARK: - Chat Message DTOs

struct ChatMessageDTO: Sendable {
    let id: Int
    let familyId: Int
    let userId: Int
    let userName: String
    let content: String
    let createdAt: Date
    let clientMessageId: String

    // Keys match `type ChatMessage` in backend/chat.go, which marshals camelCase.
    private enum CodingKeys: String, CodingKey {
        case id
        case familyId
        case userId
        case userName
        case content
        case createdAt
        case clientMessageId
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        familyId = try container.decodeIfPresent(Int.self, forKey: .familyId) ?? 0
        // Author identity and timestamp drive bubble alignment and date grouping,
        // so a missing key here has to fail loudly rather than default.
        userId = try container.decode(Int.self, forKey: .userId)
        userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? ""
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        clientMessageId = try container.decodeIfPresent(String.self, forKey: .clientMessageId) ?? ""
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(familyId, forKey: .familyId)
        try container.encode(userId, forKey: .userId)
        try container.encode(userName, forKey: .userName)
        try container.encode(content, forKey: .content)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(clientMessageId, forKey: .clientMessageId)
    }
}

extension ChatMessageDTO: Codable {}

// MARK: - Request/Response DTOs

struct SendMessageRequestDTO: Encodable, Sendable {
    let content: String
    let clientMessageId: String
}

struct SendMessageResponseDTO: Sendable {
    let message: ChatMessageDTO

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(ChatMessageDTO.self, forKey: .message)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case message
    }
}

extension SendMessageResponseDTO: Codable {}

struct GetChatMessagesRequestDTO: Encodable, Sendable {
    /// Capped at 200 by `GetChatMessages`; anything outside 1...200 falls back to
    /// the server's default of 100.
    let limit: Int
    /// Counted back from the *newest* message, not forward from the first, so
    /// offset 0 is the live end of the conversation and each further page is
    /// older. A page still arrives oldest-first within itself.
    let offset: Int
}

struct GetChatMessagesResponseDTO: Sendable {
    let messages: [ChatMessageDTO]

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decode([ChatMessageDTO].self, forKey: .messages)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
    }

    private enum CodingKeys: String, CodingKey {
        case messages
    }
}

extension GetChatMessagesResponseDTO: Codable {}

struct DeleteMessageRequestDTO: Encodable, Sendable {
    let messageId: Int

    // backend/chat.go `DeleteMessageRequest` reads `id`.
    enum CodingKeys: String, CodingKey {
        case messageId = "id"
    }
}

struct DeleteMessageResponseDTO: Sendable {
    let success: Bool

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
    }

    private enum CodingKeys: String, CodingKey {
        case success
    }
}

extension DeleteMessageResponseDTO: Codable {}

// MARK: - WebSocket Message Types

/// Wire values from `backend/websocket_chat.go` (`WSMsgType*`). The server uses
/// the same value in both directions, so there is no separate outgoing set.
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
//
// `nonisolated` on the declarations keeps their Codable conformances off the
// main actor, so `ChatWebSocketService` can decode them from its own actor.

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

/// Envelope for the two message types the server accepts from a client
/// (`user_typing` and `heartbeat`); everything else goes over the REST procs.
nonisolated struct WSOutgoingMessage<Payload: Encodable>: Encodable {
    let type: WSMessageType
    let payload: Payload
}

nonisolated struct WSTypingIndicatorPayload: Encodable {
    let isTyping: Bool
}
