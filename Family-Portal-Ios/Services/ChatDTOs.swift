import Foundation

// MARK: - Chat Message DTOs

struct ChatMessageDTO: Codable, Sendable {
    let id: Int
    let familyId: Int
    let userId: Int
    let userName: String
    let content: String
    let createdAt: Date
    let clientMessageId: String

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case userId = "user_id"
        case userName = "user_name"
        case content
        case createdAt = "created_at"
        case clientMessageId = "client_message_id"
    }
}

// MARK: - Request/Response DTOs

struct SendMessageRequestDTO: Encodable, Sendable {
    let content: String
    let clientMessageId: String

    enum CodingKeys: String, CodingKey {
        case content
        case clientMessageId = "client_message_id"
    }
}

struct SendMessageResponseDTO: Codable, Sendable {
    let message: ChatMessageDTO
}

struct GetChatMessagesRequestDTO: Encodable, Sendable {
    let limit: Int
    let offset: Int
}

struct GetChatMessagesResponseDTO: Codable, Sendable {
    let messages: [ChatMessageDTO]
}

struct DeleteMessageRequestDTO: Encodable, Sendable {
    let messageId: Int

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
    }
}

struct DeleteMessageResponseDTO: Codable, Sendable {
    let success: Bool
}

// MARK: - WebSocket Message Types

enum WSMessageType: String, Codable, Sendable {
    case newMessage = "new_message"
    case messageDeleted = "message_deleted"
    case typing = "typing"
    case sendMessage = "send_message"
    case deleteMessage = "delete_message"
    case startTyping = "start_typing"
    case stopTyping = "stop_typing"
}

// MARK: - WebSocket Incoming Messages

struct WSIncomingMessage: Codable, Sendable {
    let type: WSMessageType
    let payload: WSIncomingPayload
}

enum WSIncomingPayload: Codable, Sendable {
    case newMessage(WSNewMessagePayload)
    case messageDeleted(WSMessageDeletedPayload)
    case typing(WSTypingPayload)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let payload = try? container.decode(WSNewMessagePayload.self) {
            self = .newMessage(payload)
            return
        }
        if let payload = try? container.decode(WSMessageDeletedPayload.self) {
            self = .messageDeleted(payload)
            return
        }
        if let payload = try? container.decode(WSTypingPayload.self) {
            self = .typing(payload)
            return
        }

        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode WSIncomingPayload")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .newMessage(let payload):
            try container.encode(payload)
        case .messageDeleted(let payload):
            try container.encode(payload)
        case .typing(let payload):
            try container.encode(payload)
        }
    }
}

struct WSNewMessagePayload: Codable, Sendable {
    let message: ChatMessageDTO
}

struct WSMessageDeletedPayload: Codable, Sendable {
    let messageId: Int

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
    }
}

struct WSTypingPayload: Codable, Sendable {
    let userId: Int
    let userName: String
    let isTyping: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case userName = "user_name"
        case isTyping = "is_typing"
    }
}

// MARK: - WebSocket Outgoing Messages

struct WSOutgoingMessage: Encodable, Sendable {
    let type: WSMessageType
    let payload: WSOutgoingPayload
}

enum WSOutgoingPayload: Encodable, Sendable {
    case sendMessage(WSSendMessagePayload)
    case deleteMessage(WSDeleteMessagePayload)
    case typing(WSTypingIndicatorPayload)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .sendMessage(let payload):
            try container.encode(payload)
        case .deleteMessage(let payload):
            try container.encode(payload)
        case .typing(let payload):
            try container.encode(payload)
        }
    }
}

struct WSSendMessagePayload: Encodable, Sendable {
    let content: String
    let clientMessageId: String

    enum CodingKeys: String, CodingKey {
        case content
        case clientMessageId = "client_message_id"
    }
}

struct WSDeleteMessagePayload: Encodable, Sendable {
    let messageId: Int

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
    }
}

struct WSTypingIndicatorPayload: Encodable, Sendable {
    let isTyping: Bool

    enum CodingKeys: String, CodingKey {
        case isTyping = "is_typing"
    }
}
