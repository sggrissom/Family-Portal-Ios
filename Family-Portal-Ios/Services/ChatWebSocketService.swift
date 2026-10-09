import Foundation
import OSLog

enum WebSocketConnectionState {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed

    nonisolated static func == (lhs: WebSocketConnectionState, rhs: WebSocketConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.failed, .failed):
            return true
        case (.reconnecting(let a), .reconnecting(let b)):
            return a == b
        default:
            return false
        }
    }
}

extension WebSocketConnectionState: Equatable {}

@MainActor
protocol ChatWebSocketDelegate: AnyObject {
    func didReceiveMessage(_ message: ChatMessageDTO)
    func didReceiveDeleteMessage(messageId: Int, userId: Int)
    func didReceiveTypingUpdate(userId: Int, userName: String, isTyping: Bool)
    func didReceiveUserOnline(userId: Int, userName: String)
    func didReceiveUserOffline(userId: Int, userName: String)
    func didChangeConnectionState(_ state: WebSocketConnectionState)
    func didReceiveError(_ message: String)
}

actor ChatWebSocketService {
    // MARK: - Configuration Constants
    private static let heartbeatInterval: TimeInterval = 30
    private static let watchdogTimeout: TimeInterval = 90
    private static let maxReconnectAttempts = 10
    private static let baseReconnectDelay: TimeInterval = 1.0
    private static let maxReconnectDelay: TimeInterval = 30.0

    // MARK: - Properties
    private let baseURL: URL
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var heartbeatTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var lastMessageTime: Date = Date()
    private var reconnectAttempt = 0
    private var isManuallyDisconnected = false

    private weak var delegate: ChatWebSocketDelegate?

    /// Runs before every connect so the auth cookie the handshake carries is current. Passed `true` after the server refused the last handshake with a 401.
    private let authenticate: @Sendable (_ handshakeRefused: Bool) async -> Void
    private var handshakeRefused = false

    private(set) var connectionState: WebSocketConnectionState = .disconnected {
        didSet {
            if oldValue != connectionState {
                Task { [weak self] in
                    guard let self else { return }
                    await self.notifyConnectionStateChange()
                }
            }
        }
    }

    private func notifyConnectionStateChange() async {
        let state = connectionState
        await notify { $0.didChangeConnectionState(state) }
    }

    /// Hands an event to the delegate on the main actor, where it lives.
    private func notify(_ event: @escaping @Sendable @MainActor (ChatWebSocketDelegate) -> Void) async {
        let delegate = self.delegate
        await MainActor.run {
            if let delegate { event(delegate) }
        }
    }

    // MARK: - Initialization

    init(baseURL: URL, authenticate: @escaping @Sendable (_ handshakeRefused: Bool) async -> Void = { _ in }) {
        self.baseURL = baseURL
        self.authenticate = authenticate

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public Interface

    func setDelegate(_ delegate: ChatWebSocketDelegate?) {
        self.delegate = delegate
    }

    func connect() async {
        guard connectionState == .disconnected || connectionState == .failed else {
            return
        }

        isManuallyDisconnected = false
        reconnectAttempt = 0
        await performConnect()
    }

    func disconnect() {
        isManuallyDisconnected = true
        cleanupConnection()
        connectionState = .disconnected
    }

    func sendTypingIndicator(isTyping: Bool) async {
        let message = WSOutgoingMessage(
            type: .userTyping,
            payload: WSTypingIndicatorPayload(isTyping: isTyping)
        )
        await send(message)
    }

    // MARK: - Connection Management

    private func performConnect() async {
        connectionState = reconnectAttempt > 0
            ? .reconnecting(attempt: reconnectAttempt)
            : .connecting

        let refused = handshakeRefused
        handshakeRefused = false
        await authenticate(refused)
        // A disconnect may have arrived while the token was refreshing.
        guard !isManuallyDisconnected else { return }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            connectionState = .failed
            return
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws/chat"

        guard let wsURL = components.url else {
            connectionState = .failed
            return
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 10


        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        // Optimistic: the handshake is still in flight. The backoff is only reset once something actually arrives (see `receiveLoop`), or a handshake the server refuses would retry every second forever.
        connectionState = .connected

        startHeartbeat()
        startWatchdog()
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                lastMessageTime = Date()
                reconnectAttempt = 0

                switch message {
                case .string(let text):
                    await handleIncomingMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleIncomingMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                // Tearing a connection down fails its pending receive too. That loop is no longer the connection's, and reconnecting from it would tear down whatever replaced it.
                guard task === webSocketTask, !Task.isCancelled else { break }
                let status = (task.response as? HTTPURLResponse)?.statusCode
                handshakeRefused = status == 401
                // A refused handshake is not a dropped connection. The server answers 403 to an account with no membership row for its family, and retrying cannot fix that.
                if let status, Self.isPermanentRefusal(status) {
                    AppLog.chat.error("Chat socket refused with HTTP \(status); not reconnecting")
                    cleanupConnection()
                    connectionState = .failed
                    break
                }
                if !isManuallyDisconnected {
                    await handleDisconnection()
                }
                break
            }
        }
    }

    private func handleIncomingMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        // Go marshals time.Time as RFC3339 with fractional seconds, which `.iso8601` rejects; reuse the tolerant decoder.
        do {
            struct TypeOnly: Decodable { let type: String }
            let typeMessage = try APIClient.decode(TypeOnly.self, from: data)

            guard let messageType = WSMessageType(rawValue: typeMessage.type) else {
                return
            }

            switch messageType {
            case .newMessage:
                let payload = try APIClient.decode(Envelope<WSNewMessagePayload>.self, from: data).payload
                await notify { $0.didReceiveMessage(payload.message) }

            case .deleteMessage:
                let payload = try APIClient.decode(Envelope<WSDeleteMessagePayload>.self, from: data).payload
                await notify { $0.didReceiveDeleteMessage(messageId: payload.messageId, userId: payload.userId) }

            case .userTyping:
                let payload = try APIClient.decode(Envelope<WSTypingPayload>.self, from: data).payload
                await notify {
                    $0.didReceiveTypingUpdate(userId: payload.userId, userName: payload.userName, isTyping: payload.isTyping)
                }

            case .userOnline, .userOffline:
                let payload = try APIClient.decode(Envelope<WSUserStatusPayload>.self, from: data).payload
                await notify { delegate in
                    if payload.isOnline {
                        delegate.didReceiveUserOnline(userId: payload.userId, userName: payload.userName)
                    } else {
                        delegate.didReceiveUserOffline(userId: payload.userId, userName: payload.userName)
                    }
                }

            case .heartbeat:
                break

            case .error:
                struct ErrorEnvelope: Decodable { let payload: String? }
                let wrapper = try? APIClient.decode(ErrorEnvelope.self, from: data)
                let message = wrapper?.payload ?? "Chat connection error"
                await notify { $0.didReceiveError(message) }
            }
        } catch {
            AppLog.chat.error("Failed to decode socket message: \(String(describing: error), privacy: .public)")
        }
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let type: String
        let payload: Payload
    }

    /// Handshake statuses that another attempt won't change. 401 is left to the normal path, since the token may simply need refreshing before the next connect.
    nonisolated static func isPermanentRefusal(_ status: Int) -> Bool {
        status == 403 || status == 404
    }

    private func handleDisconnection() async {
        cleanupConnection()

        guard !isManuallyDisconnected,
              reconnectAttempt < Self.maxReconnectAttempts else {
            connectionState = .failed
            return
        }

        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)

        let delay = min(
            Self.baseReconnectDelay * pow(2, Double(reconnectAttempt - 1)),
            Self.maxReconnectDelay
        )

        try? await Task.sleep(for: .seconds(delay))

        if !isManuallyDisconnected {
            await performConnect()
        }
    }

    private func cleanupConnection() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Heartbeat & Watchdog

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.heartbeatInterval))

                guard !Task.isCancelled else { break }

                // The server's readPump times out after 60s of silence and a ping frame doesn't reset it, so send the protocol-level heartbeat it understands.
                await self?.sendHeartbeat()
            }
        }
    }

    private func sendHeartbeat() async {
        await send(WSOutgoingMessage(type: .heartbeat, payload: "ping"))
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.watchdogTimeout))

                guard !Task.isCancelled else { break }

                guard let self = self else { break }

                let timeSinceLastMessage = Date().timeIntervalSince(await self.lastMessageTime)
                if timeSinceLastMessage > Self.watchdogTimeout {
                    AppLog.chat.notice("Watchdog fired: no socket traffic in \(Int(timeSinceLastMessage))s, reconnecting")
                    // Not from this task: the reconnect cancels the watchdog, which would cut the backoff sleep short.
                    Task { await self.handleDisconnection() }
                    break
                }
            }
        }
    }

    private func send<Payload: Encodable>(_ message: WSOutgoingMessage<Payload>) async {
        guard let task = webSocketTask,
              connectionState == .connected else {
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            guard let text = String(data: data, encoding: .utf8) else { return }
            try await task.send(.string(text))
        } catch {
            AppLog.chat.error("Socket send failed: \(String(describing: error), privacy: .public)")
        }
    }
}
