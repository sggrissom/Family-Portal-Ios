import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

nonisolated enum ChatHistory {

    static func route(_ server: FakeHTTPServer, total: Int, failingOnCall failingCall: Int? = nil) {
        let counter = CallCounter()
        server.route("rpc/GetChatMessages") { request in
            if let failingCall, counter.next() == failingCall {
                return .status(500, message: "database is down")
            }

            let payload = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            let limit = payload["limit"] as? Int ?? 100
            let offset = payload["offset"] as? Int ?? 0

            let end = max(0, total - offset)
            let start = max(0, end - limit)
            return .json(["messages": (start..<end).map { message(id: $0 + 1) }])
        }
    }

    static func message(id: Int) -> [String: Any] {
        Fixture.chatMessage(
            id: id,
            userId: 2,
            userName: "Bo",
            content: "msg-\(id)",
            createdAt: timestamp(id)
        )
    }

    static func timestamp(_ index: Int) -> String {
        let base = Date(timeIntervalSince1970: 1_767_614_400)
        return ISO8601DateFormatter().string(from: base.addingTimeInterval(TimeInterval(index) * 60))
    }

    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func next() -> Int {
            lock.withLock {
                value += 1
                return value
            }
        }
    }
}

@MainActor
@Suite("Chat history")
struct ChatHistoryTests {

    private static func makeService(server: FakeHTTPServer) async throws -> ChatService {
        let context = try TestStore.makeContext()
        return await ChatService(
            modelContext: context,
            apiClient: server.apiClient(),
            currentUserId: 1,
            currentUserName: "Ada"
        )
    }

    private static func historyRequests(_ server: FakeHTTPServer) -> [FakeHTTPServer.Request] {
        server.requests(for: "rpc/GetChatMessages")
    }

    private static func requestedOffsets(_ server: FakeHTTPServer) -> [Int] {
        historyRequests(server).map { request in
            let payload = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            return payload?["offset"] as? Int ?? -1
        }
    }

    private static func contents(_ service: ChatService) -> [String] {
        service.messages.map(\.content)
    }

    private static func deliverOverSocket(_ service: ChatService, ids: ClosedRange<Int>) throws {
        for id in ids {
            service.didReceiveMessage(try Fixture.chatMessageDTO(
                id: id,
                userId: 2,
                userName: "Bo",
                content: "msg-\(id)",
                createdAt: ChatHistory.timestamp(id)
            ))
        }
    }

    // MARK: - The newest page first

    @Test("The first load asks for the newest page")
    func firstLoadRequestsNewestPage() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 120)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()

        let first = try #require(Self.historyRequests(server).first)
        let body = try #require(JSONSerialization.jsonObject(with: first.body) as? [String: Any])
        #expect(body["offset"] as? Int == 0)
        #expect(body["limit"] as? Int == ChatService.pageSize)

        #expect(service.messages.count == 50)
        #expect(Self.contents(service).first == "msg-71")
        #expect(Self.contents(service).last == "msg-120")
        #expect(service.hasMoreHistory)
    }

    @Test("Pulling loads the page before the oldest one on screen")
    func pullLoadsThePreviousPage() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 120)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()
        await service.loadOlderMessages()

        #expect(Self.requestedOffsets(server) == [0, 50])
        #expect(service.messages.count == 100)
        #expect(Self.contents(service).first == "msg-21")
        #expect(Self.contents(service).last == "msg-120")
        #expect(service.isLoadingOlder == false)
        #expect(service.error == nil)
    }

    @Test("A loaded page lands in chronological order, not at the end")
    func historyIsInterleavedInOrder() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 120)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()
        await service.loadOlderMessages()

        let dates = service.messages.map(\.createdAt)
        #expect(dates == dates.sorted())
        #expect(Self.contents(service) == (21...120).map { "msg-\($0)" })
    }

    // MARK: - Reaching the beginning

    @Test("A short page ends the history and stops the asking")
    func shortPageEndsHistory() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 60)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()
        #expect(service.hasMoreHistory)

        await service.loadOlderMessages()

        #expect(service.messages.count == 60)
        #expect(Self.contents(service).first == "msg-1")
        #expect(service.hasMoreHistory == false)

        await service.loadOlderMessages()
        #expect(Self.requestedOffsets(server) == [0, 50])
    }

    @Test("A conversation shorter than a page has no history to pull")
    func shortConversationHasNoHistory() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 20)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()

        #expect(service.messages.count == 20)
        #expect(service.hasMoreHistory == false)

        await service.loadOlderMessages()
        #expect(Self.historyRequests(server).count == 1)
    }

    // MARK: - The offset counts the server's messages, not ours

    @Test("Messages arriving live do not push unfetched history out of reach")
    func liveMessagesDoNotSkipHistory() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 120)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()

        try Self.deliverOverSocket(service, ids: 121...123)
        #expect(service.messages.count == 53)

        await service.loadOlderMessages()

        #expect(Self.requestedOffsets(server) == [0, 50])
        #expect(Self.contents(service).first == "msg-21")
        #expect(service.messages.count == 103)
    }

    @Test("Reloading the newest page does not rewind the history cursor")
    func reloadingDoesNotRewindPaging() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 200)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()
        await service.loadOlderMessages()
        await service.loadMessages()
        await service.loadOlderMessages()

        #expect(Self.requestedOffsets(server) == [0, 50, 0, 100])
        #expect(Self.contents(service).first == "msg-51")
    }

    // MARK: - Pages the device already has

    @Test("A pull walks past pages it already has")
    func pullWalksPastKnownPages() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 200)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()

        try Self.deliverOverSocket(service, ids: 101...150)

        await service.loadOlderMessages()

        #expect(Self.requestedOffsets(server) == [0, 50, 100])
        #expect(Self.contents(service).first == "msg-51")
    }

    @Test("The walk past known pages is capped")
    func walkPastKnownPagesIsCapped() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetChatMessages", respond: .json([
            "messages": (1...ChatService.pageSize).map { ChatHistory.message(id: $0) }
        ]))
        let service = try await Self.makeService(server: server)

        await service.loadMessages()
        await service.loadOlderMessages()

        #expect(Self.historyRequests(server).count == 6)
        #expect(service.messages.count == ChatService.pageSize)
        #expect(service.hasMoreHistory)
        #expect(service.isLoadingOlder == false)
    }

    // MARK: - Failure

    @Test("A failed pull leaves the cursor where it was and retries the same page")
    func failedPullDoesNotAdvanceCursor() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 120, failingOnCall: 2)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()
        await service.loadOlderMessages()

        #expect(service.error != nil)
        #expect(service.messages.count == 50)
        #expect(service.hasMoreHistory)
        #expect(service.isLoadingOlder == false)

        await service.loadOlderMessages()

        #expect(Self.requestedOffsets(server) == [0, 50, 50])
        #expect(service.messages.count == 100)
        #expect(Self.contents(service).first == "msg-21")
        #expect(service.error == nil)
    }
}
