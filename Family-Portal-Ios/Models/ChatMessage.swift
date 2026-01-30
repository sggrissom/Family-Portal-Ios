import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID
    var remoteId: String?
    var clientMessageId: String
    var userId: Int
    var userName: String
    var content: String
    var createdAt: Date
    var isSending: Bool
    var sendFailed: Bool

    init(
        clientMessageId: String,
        userId: Int,
        userName: String,
        content: String,
        createdAt: Date = Date(),
        isSending: Bool = false,
        sendFailed: Bool = false
    ) {
        self.id = UUID()
        self.remoteId = nil
        self.clientMessageId = clientMessageId
        self.userId = userId
        self.userName = userName
        self.content = content
        self.createdAt = createdAt
        self.isSending = isSending
        self.sendFailed = sendFailed
    }

    static func fromDTO(_ dto: ChatMessageDTO) -> ChatMessage {
        let message = ChatMessage(
            clientMessageId: dto.clientMessageId,
            userId: dto.userId,
            userName: dto.userName,
            content: dto.content,
            createdAt: dto.createdAt,
            isSending: false,
            sendFailed: false
        )
        message.remoteId = String(dto.id)
        return message
    }
}
