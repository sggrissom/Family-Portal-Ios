import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Chat DTO decoding")
struct ChatDTODecodingTests {

    static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    static let expectedInstant = utc(2026, 3, 15, 14, 30)

    // MARK: - ChatMessage (backend/chat.go)

    static let chatMessageJSON = """
    {
      "id": 412,
      "familyId": 7,
      "userId": 33,
      "userName": "Dana",
      "content": "on my way",
      "createdAt": "2026-03-15T14:30:00.123456789Z",
      "clientMessageId": "5C6F0E1A-1E4E-4D6B-9C1B-2A0F5B7D8E90"
    }
    """

    @Test("Decodes every field from the Go camelCase payload")
    func decodesGoPayload() throws {
        let dto = try APIClient.decode(ChatMessageDTO.self, from: Data(Self.chatMessageJSON.utf8))

        #expect(dto.id == 412)
        #expect(dto.familyId == 7)
        #expect(dto.userId == 33)
        #expect(dto.userName == "Dana")
        #expect(dto.content == "on my way")
        #expect(dto.clientMessageId == "5C6F0E1A-1E4E-4D6B-9C1B-2A0F5B7D8E90")

        #expect(abs(dto.createdAt.timeIntervalSince(Self.expectedInstant)) < 1)
    }

    @Test("Accepts whole-second timestamps too")
    func decodesWholeSecondTimestamp() throws {
        let json = Self.chatMessageJSON.replacingOccurrences(
            of: "2026-03-15T14:30:00.123456789Z",
            with: "2026-03-15T14:30:00Z"
        )
        let dto = try APIClient.decode(ChatMessageDTO.self, from: Data(json.utf8))

        #expect(abs(dto.createdAt.timeIntervalSince(Self.expectedInstant)) < 1)
    }

    @Test("Accepts a non-UTC offset")
    func decodesOffsetTimestamp() throws {
        let json = Self.chatMessageJSON.replacingOccurrences(
            of: "2026-03-15T14:30:00.123456789Z",
            with: "2026-03-15T09:30:00-05:00"
        )
        let dto = try APIClient.decode(ChatMessageDTO.self, from: Data(json.utf8))

        #expect(abs(dto.createdAt.timeIntervalSince(Self.expectedInstant)) < 1)
    }

    static func chatMessageJSON(without key: String) throws -> Data {
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(chatMessageJSON.utf8)) as? [String: Any]
        )
        object.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test("Fails loudly when the author or timestamp key goes missing", arguments: ["userId", "createdAt"])
    func failsOnMissingIdentityFields(missing: String) throws {
        let data = try Self.chatMessageJSON(without: missing)

        #expect(throws: (any Error).self) {
            try APIClient.decode(ChatMessageDTO.self, from: data)
        }
    }

    @Test("Tolerates an absent clientMessageId")
    func tolerantOfMissingClientMessageId() throws {
        let dto = try APIClient.decode(
            ChatMessageDTO.self, from: Self.chatMessageJSON(without: "clientMessageId")
        )
        #expect(dto.clientMessageId.isEmpty)
    }

    // MARK: - Request encoding

    @Test("SendMessage encodes the key the server reads")
    func sendMessageRequestKeys() throws {
        let data = try JSONEncoder().encode(
            SendMessageRequestDTO(content: "hi", clientMessageId: "abc")
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // backend/chat.go SendMessageRequest.ClientMessageId is `clientMessageId`.
        #expect(object["clientMessageId"] as? String == "abc")
        #expect(object["client_message_id"] == nil)
    }

    @Test("DeleteMessage encodes `id`, not `message_id`")
    func deleteMessageRequestKeys() throws {
        let data = try JSONEncoder().encode(DeleteMessageRequestDTO(messageId: 99))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["id"] as? Int == 99)
        #expect(object["message_id"] == nil)
    }

    // MARK: - WebSocket envelopes (backend/websocket_chat.go)

    @Test("Wire values match the server's WSMsgType constants")
    func webSocketTypeRawValues() {
        #expect(WSMessageType.newMessage.rawValue == "new_message")
        #expect(WSMessageType.deleteMessage.rawValue == "delete_message")
        #expect(WSMessageType.userTyping.rawValue == "user_typing")
        #expect(WSMessageType.userOnline.rawValue == "user_online")
        #expect(WSMessageType.userOffline.rawValue == "user_offline")
        #expect(WSMessageType.heartbeat.rawValue == "heartbeat")
        #expect(WSMessageType.error.rawValue == "error")
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let type: String
        let payload: Payload
    }

    @Test("Decodes a new_message broadcast")
    func decodesNewMessageBroadcast() throws {
        let json = """
        {
          "type": "new_message",
          "payload": { "message": \(Self.chatMessageJSON) },
          "timestamp": "2026-03-15T14:30:00.9Z"
        }
        """
        let envelope = try APIClient.decode(
            Envelope<WSNewMessagePayload>.self, from: Data(json.utf8)
        )

        #expect(envelope.type == WSMessageType.newMessage.rawValue)
        #expect(envelope.payload.message.userId == 33)
        #expect(envelope.payload.message.userName == "Dana")
    }

    @Test("Decodes a delete_message broadcast with camelCase payload keys")
    func decodesDeleteBroadcast() throws {
        let json = """
        {
          "type": "delete_message",
          "payload": { "messageId": 412, "userId": 33 },
          "timestamp": "2026-03-15T14:31:00Z"
        }
        """
        let envelope = try APIClient.decode(
            Envelope<WSDeleteMessagePayload>.self, from: Data(json.utf8)
        )

        #expect(envelope.payload.messageId == 412)
        #expect(envelope.payload.userId == 33)
    }

    @Test("Decodes a user_typing broadcast")
    func decodesTypingBroadcast() throws {
        let json = """
        {
          "type": "user_typing",
          "payload": { "userId": 33, "userName": "Dana", "isTyping": true },
          "timestamp": "2026-03-15T14:31:00Z"
        }
        """
        let envelope = try APIClient.decode(
            Envelope<WSTypingPayload>.self, from: Data(json.utf8)
        )

        #expect(envelope.payload.userId == 33)
        #expect(envelope.payload.userName == "Dana")
        #expect(envelope.payload.isTyping)
    }

    @Test("Decodes user_online / user_offline, which previously had no case")
    func decodesPresenceBroadcast() throws {
        let online = """
        {
          "type": "user_online",
          "payload": { "userId": 33, "userName": "Dana", "isOnline": true },
          "timestamp": "2026-03-15T14:31:00Z"
        }
        """
        let offline = online
            .replacingOccurrences(of: "user_online", with: "user_offline")
            .replacingOccurrences(of: "\"isOnline\": true", with: "\"isOnline\": false")

        #expect(
            try APIClient.decode(Envelope<WSUserStatusPayload>.self, from: Data(online.utf8))
                .payload.isOnline
        )
        #expect(
            try !APIClient.decode(Envelope<WSUserStatusPayload>.self, from: Data(offline.utf8))
                .payload.isOnline
        )
    }

    @Test("Outgoing typing indicator carries the key the server unmarshals")
    func outgoingTypingEncoding() throws {
        let data = try JSONEncoder().encode(
            WSOutgoingMessage(type: .userTyping, payload: WSTypingIndicatorPayload(isTyping: true))
        )
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["type"] as? String == "user_typing")
        let payload = try #require(object["payload"] as? [String: Any])
        #expect(payload["isTyping"] as? Bool == true)
        #expect(payload["is_typing"] == nil)
    }
}
