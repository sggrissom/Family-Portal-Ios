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

    private enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case userId = "user_id"
        case userName = "user_name"
        case content
        case createdAt = "created_at"
        case clientMessageId = "client_message_id"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        familyId = try container.decode(Int.self, forKey: .familyId)
        userId = try container.decode(Int.self, forKey: .userId)
        userName = try container.decode(String.self, forKey: .userName)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        clientMessageId = try container.decode(String.self, forKey: .clientMessageId)
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

    enum CodingKeys: String, CodingKey {
        case content
        case clientMessageId = "client_message_id"
    }
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
    let limit: Int
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

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
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

struct WSOutgoingMessage: Sendable {
    let type: WSMessageType
    let payload: WSOutgoingPayload

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(payload, forKey: .payload)
    }

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }
}

extension WSOutgoingMessage: Encodable {}

enum WSOutgoingPayload: Sendable {
    case sendMessage(WSSendMessagePayload)
    case deleteMessage(WSDeleteMessagePayload)
    case typing(WSTypingIndicatorPayload)

    nonisolated func encode(to encoder: Encoder) throws {
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

extension WSOutgoingPayload: Encodable {}

struct WSSendMessagePayload: Sendable {
    let content: String
    let clientMessageId: String

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(content, forKey: .content)
        try container.encode(clientMessageId, forKey: .clientMessageId)
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case clientMessageId = "client_message_id"
    }
}

extension WSSendMessagePayload: Encodable {}

struct WSDeleteMessagePayload: Sendable {
    let messageId: Int

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageId, forKey: .messageId)
    }

    private enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
    }
}

extension WSDeleteMessagePayload: Encodable {}

struct WSTypingIndicatorPayload: Sendable {
    let isTyping: Bool

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isTyping, forKey: .isTyping)
    }

    private enum CodingKeys: String, CodingKey {
        case isTyping = "is_typing"
    }
}

extension WSTypingIndicatorPayload: Encodable {}
