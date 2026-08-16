import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// A chat message can arrive three ways — the send that created it, the socket
/// echo, and the next `loadMessages` page — and each carries a different subset
/// of the ids the others match on. The dedup rules that reconcile them are the
/// whole reason a sent message doesn't appear twice.
@MainActor
@Suite("ChatService")
struct ChatServiceTests {

    private static let currentUserId = 1

    private static func makeService(server: FakeHTTPServer) async throws -> ChatService {
        let context = try TestStore.makeContext()
        return await ChatService(
            modelContext: context,
            apiClient: server.apiClient(),
            currentUserId: currentUserId,
            currentUserName: "Ada"
        )
    }

    // MARK: - Sending

    @Test("A sent message appears immediately and adopts the server's id")
    func sendShowsMessageThenAdoptsRemoteId() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SendMessage", respond: .json([
            "message": Fixture.chatMessage(id: 42, userId: Self.currentUserId, content: "hello")
        ]))
        let service = try await Self.makeService(server: server)

        await service.sendMessage("hello")

        #expect(service.messages.count == 1)
        #expect(service.messages[0].content == "hello")
        #expect(service.messages[0].remoteId == "42")
        #expect(service.messages[0].isSending == false)
        #expect(service.messages[0].sendFailed == false)
        #expect(service.error == nil)
    }

    @Test("An empty message is not sent at all")
    func emptyMessageIsIgnored() async throws {
        let server = FakeHTTPServer()
        let service = try await Self.makeService(server: server)

        await service.sendMessage("   \n ")

        #expect(service.messages.isEmpty)
        #expect(server.allRequests.isEmpty)
    }

    /// The message is already on screen when the send fails, so it has to be
    /// marked rather than dropped — `retrySendMessage` is the only way back.
    @Test("A failed send is kept and marked, then recovers on retry")
    func failedSendIsMarkedAndRetryable() async throws {
        let server = FakeHTTPServer()
        server.routeSequence("rpc/SendMessage", [
            .status(500, message: "rejected"),
            .json(["message": Fixture.chatMessage(id: 43, userId: Self.currentUserId, content: "hello")])
        ])
        let service = try await Self.makeService(server: server)

        await service.sendMessage("hello")

        #expect(service.messages.count == 1)
        #expect(service.messages[0].sendFailed)
        #expect(service.messages[0].isSending == false)
        #expect(service.error != nil)

        await service.retrySendMessage(service.messages[0])

        #expect(service.messages.count == 1)
        #expect(service.messages[0].sendFailed == false)
        #expect(service.messages[0].remoteId == "43")
    }

    // MARK: - Deduplication

    @Test("The socket echo of our own message updates it instead of adding a copy")
    func socketEchoUpdatesOptimisticMessage() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/SendMessage", respond: .json([
            "message": Fixture.chatMessage(id: 42, userId: Self.currentUserId, content: "hello")
        ]))
        let service = try await Self.makeService(server: server)

        await service.sendMessage("hello")
        let clientMessageId = service.messages[0].clientMessageId

        service.didReceiveMessage(try Fixture.chatMessageDTO(
            id: 42,
            userId: Self.currentUserId,
            content: "hello",
            clientMessageId: clientMessageId
        ))

        #expect(service.messages.count == 1)
        #expect(service.messages[0].remoteId == "42")
    }

    @Test("A message delivered twice over the socket is stored once")
    func repeatedSocketMessageIsIgnored() async throws {
        let server = FakeHTTPServer()
        let service = try await Self.makeService(server: server)

        let dto = try Fixture.chatMessageDTO(id: 7, userId: 2, userName: "Bo", content: "hi")
        service.didReceiveMessage(dto)
        service.didReceiveMessage(dto)

        #expect(service.messages.count == 1)
        #expect(service.messages[0].userName == "Bo")
    }

    @Test("Loading a page keeps the messages already on screen")
    func loadMessagesSkipsKnownMessages() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetChatMessages", respond: .json([
            "messages": [
                Fixture.chatMessage(id: 7, userId: 2, userName: "Bo", content: "hi", createdAt: "2026-01-05T12:00:00Z"),
                Fixture.chatMessage(id: 8, userId: 2, userName: "Bo", content: "again", createdAt: "2026-01-05T12:01:00Z")
            ]
        ]))
        let service = try await Self.makeService(server: server)

        service.didReceiveMessage(try Fixture.chatMessageDTO(id: 7, userId: 2, userName: "Bo", content: "hi"))
        await service.loadMessages()

        #expect(service.messages.count == 2)
        #expect(service.messages.compactMap(\.remoteId) == ["7", "8"])
        #expect(service.isLoading == false)
    }

    @Test("Messages are kept in the order they were written")
    func messagesAreSortedByTime() async throws {
        let server = FakeHTTPServer()
        let service = try await Self.makeService(server: server)

        service.didReceiveMessage(try Fixture.chatMessageDTO(
            id: 9, userId: 2, userName: "Bo", content: "later", createdAt: "2026-01-05T12:05:00Z"
        ))
        service.didReceiveMessage(try Fixture.chatMessageDTO(
            id: 8, userId: 2, userName: "Bo", content: "earlier", createdAt: "2026-01-05T12:00:00Z"
        ))

        #expect(service.messages.map(\.content) == ["earlier", "later"])
    }

    // MARK: - Failure reporting

    @Test("A page that fails to load reports the error rather than emptying the list")
    func loadFailureIsReported() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetChatMessages", respond: .status(500, message: "database is down"))
        let service = try await Self.makeService(server: server)

        service.didReceiveMessage(try Fixture.chatMessageDTO(id: 7, userId: 2, userName: "Bo", content: "hi"))
        await service.loadMessages()

        #expect(service.error != nil)
        #expect(service.messages.count == 1)
        #expect(service.isLoading == false)
    }

    /// The local row is gone the moment the user taps delete; if the server never
    /// agrees, the message comes back on the next pull, so the failure has to be
    /// visible when it happens.
    @Test("A delete the server rejects is reported")
    func deleteFailureIsReported() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/DeleteMessage", respond: .status(500, message: "nope"))
        let service = try await Self.makeService(server: server)

        service.didReceiveMessage(try Fixture.chatMessageDTO(
            id: 11, userId: Self.currentUserId, content: "mine"
        ))

        await service.deleteMessage(service.messages[0])

        #expect(service.messages.isEmpty)
        #expect(service.error != nil)
    }

    @Test("Someone else's message cannot be deleted")
    func deletingAnotherUsersMessageDoesNothing() async throws {
        let server = FakeHTTPServer()
        let service = try await Self.makeService(server: server)

        service.didReceiveMessage(try Fixture.chatMessageDTO(id: 12, userId: 2, userName: "Bo", content: "theirs"))

        await service.deleteMessage(service.messages[0])

        #expect(service.messages.count == 1)
        #expect(server.allRequests.isEmpty)
    }
}
