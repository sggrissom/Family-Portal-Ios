import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// A stand-in for `GetChatMessages`, built to the same rule the Go handler
/// follows: the window is cut from the *newest* end, and each page still arrives
/// oldest-first within itself so the response shape is the one it always was.
///
/// `nonisolated` because the routing closure runs on the `URLProtocol`'s thread,
/// not the main actor the suite lives on.
nonisolated enum ChatHistory {

    /// Messages are `msg-1` (oldest) through `msg-<total>` (newest).
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

    /// One minute apart and ascending with the id, so the service's own sort
    /// agrees with the order the ids imply.
    static func timestamp(_ index: Int) -> String {
        // 2026-01-05T12:00:00Z
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

/// `GetChatMessages` pages backwards from the newest message, and its offset
/// counts the server's ordering rather than the app's list. Those two facts are
/// the whole contract behind pulling for history, and neither is visible in a
/// type — a page that counted the wrong things would still compile, and would
/// lose messages out of the middle of the thread.
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

    /// The offsets asked for, in order — the sequence a paging bug shows up in.
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

    /// Before the backend honoured its offset the window was cut from the other
    /// end, so a long-running family opened the app on its first ever messages and
    /// never saw today's. Asking for offset 0 is what makes the first page recent.
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

    /// Older messages have to land *above* what is on screen rather than at the
    /// end of the list — the list is what the view groups into days and scrolls.
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

        // The pull stays attached to the scroll view once history runs out, so the
        // guard rather than the UI is what stops a pointless request.
        await service.loadOlderMessages()
        #expect(Self.requestedOffsets(server) == [0, 50])
    }

    /// A conversation shorter than one page is complete on arrival: there is no
    /// page before it, and pulling could only ever return nothing.
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

    /// The trap this is here to catch: using `messages.count` as the offset. The
    /// list also holds what the socket delivered and what this device sent, so
    /// counting it would step over history that was never fetched and leave a hole
    /// in the thread that nothing later fills.
    @Test("Messages arriving live do not push unfetched history out of reach")
    func liveMessagesDoNotSkipHistory() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 120)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()

        // Three messages land over the socket while the user is reading.
        try Self.deliverOverSocket(service, ids: 121...123)
        #expect(service.messages.count == 53)

        await service.loadOlderMessages()

        #expect(Self.requestedOffsets(server) == [0, 50])
        #expect(Self.contents(service).first == "msg-21")
        #expect(service.messages.count == 103)
    }

    /// Leaving the tab and coming back re-reads the newest page. If that reset the
    /// paging cursor, the next pull would re-fetch a page already on screen and
    /// look like a pull that did nothing.
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

    /// The store keeps every message this device has ever seen while the cursor
    /// starts each session at zero, so the first pull after a relaunch can land on
    /// a page that is entirely known. Stopping there would report "no more
    /// history" by showing nothing, so the pull walks on until it finds something.
    @Test("A pull walks past pages it already has")
    func pullWalksPastKnownPages() async throws {
        let server = FakeHTTPServer()
        ChatHistory.route(server, total: 200)
        let service = try await Self.makeService(server: server)

        await service.loadMessages()

        // The page behind the current one is already here, as it would be for a
        // device that pulled it during an earlier session.
        try Self.deliverOverSocket(service, ids: 101...150)

        await service.loadOlderMessages()

        // One pull, two pages: the known one is stepped over rather than counted
        // as a result.
        #expect(Self.requestedOffsets(server) == [0, 50, 100])
        #expect(Self.contents(service).first == "msg-51")
    }

    /// The walk cannot be unbounded, or a device holding a long history would turn
    /// one pull into a run of requests reaching all the way to the first message.
    @Test("The walk past known pages is capped")
    func walkPastKnownPagesIsCapped() async throws {
        let server = FakeHTTPServer()
        // A server answering every offset with the same full page — the
        // pathological shape of "nothing new here, keep going".
        server.route("rpc/GetChatMessages", respond: .json([
            "messages": (1...ChatService.pageSize).map { ChatHistory.message(id: $0) }
        ]))
        let service = try await Self.makeService(server: server)

        await service.loadMessages()
        await service.loadOlderMessages()

        // The first request is the newest page; the pull adds five more and stops.
        #expect(Self.historyRequests(server).count == 6)
        #expect(service.messages.count == ChatService.pageSize)
        #expect(service.hasMoreHistory)
        #expect(service.isLoadingOlder == false)
    }

    // MARK: - Failure

    /// A page that never arrived must not advance the cursor: the offset is the
    /// only record of how far back the thread has been read, and moving it past a
    /// page nothing was received for would skip those messages for good.
    @Test("A failed pull leaves the cursor where it was and retries the same page")
    func failedPullDoesNotAdvanceCursor() async throws {
        let server = FakeHTTPServer()
        // Call 1 is the newest page; call 2 is the first pull for history.
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
