import Foundation

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
        // Capture delegate on the actor to avoid crossing isolation
        let delegate = self.delegate
        await MainActor.run {
            delegate?.didChangeConnectionState(state)
        }
    }

    // MARK: - Initialization

    init(baseURL: URL) {
        self.baseURL = baseURL

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

        // Cookies are automatically included via HTTPCookieStorage

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        // Start receiving messages
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        // Assume connected after task starts (first message confirms)
        connectionState = .connected
        reconnectAttempt = 0

        startHeartbeat()
        startWatchdog()
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                lastMessageTime = Date()

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
                if !isManuallyDisconnected {
                    await handleDisconnection()
                }
                break
            }
        }
    }

    private func handleIncomingMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        // Go marshals time.Time as RFC3339 with fractional seconds, which
        // JSONDecoder's `.iso8601` strategy rejects; reuse the tolerant decoder.
        do {
            // Parse type first
            struct TypeOnly: Decodable { let type: String }
            let typeMessage = try APIClient.decode(TypeOnly.self, from: data)

            guard let messageType = WSMessageType(rawValue: typeMessage.type) else {
                return
            }

            switch messageType {
            case .newMessage:
                let wrapper = try APIClient.decode(Envelope<WSNewMessagePayload>.self, from: data)
                let delegate = self.delegate
                await MainActor.run {
                    delegate?.didReceiveMessage(wrapper.payload.message)
                }

            case .deleteMessage:
                let wrapper = try APIClient.decode(Envelope<WSDeleteMessagePayload>.self, from: data)
                let delegate = self.delegate
                await MainActor.run {
                    delegate?.didReceiveDeleteMessage(
                        messageId: wrapper.payload.messageId,
                        userId: wrapper.payload.userId
                    )
                }

            case .userTyping:
                let wrapper = try APIClient.decode(Envelope<WSTypingPayload>.self, from: data)
                let delegate = self.delegate
                await MainActor.run {
                    delegate?.didReceiveTypingUpdate(
                        userId: wrapper.payload.userId,
                        userName: wrapper.payload.userName,
                        isTyping: wrapper.payload.isTyping
                    )
                }

            case .userOnline, .userOffline:
                let wrapper = try APIClient.decode(Envelope<WSUserStatusPayload>.self, from: data)
                let payload = wrapper.payload
                let delegate = self.delegate
                await MainActor.run {
                    if payload.isOnline {
                        delegate?.didReceiveUserOnline(userId: payload.userId, userName: payload.userName)
                    } else {
                        delegate?.didReceiveUserOffline(userId: payload.userId, userName: payload.userName)
                    }
                }

            case .heartbeat:
                // The receive itself already refreshed the watchdog timestamp.
                break

            case .error:
                struct ErrorEnvelope: Decodable { let payload: String? }
                let wrapper = try? APIClient.decode(ErrorEnvelope.self, from: data)
                let message = wrapper?.payload ?? "Chat connection error"
                let delegate = self.delegate
                await MainActor.run {
                    delegate?.didReceiveError(message)
                }
            }
        } catch {
            print("[WebSocket] Failed to decode message: \(error)")
        }
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let type: String
        let payload: Payload
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

        // Exponential backoff
        let delay = min(
            Self.baseReconnectDelay * pow(2, Double(reconnectAttempt - 1)),
            Self.maxReconnectDelay
        )

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

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
                try? await Task.sleep(nanoseconds: UInt64(Self.heartbeatInterval * 1_000_000_000))

                guard !Task.isCancelled else { break }

                // The server's readPump times out after 60s of silence and a ping
                // frame doesn't reset it, so send the protocol-level heartbeat it
                // understands. Its `heartbeat` reply also feeds the watchdog below.
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
                try? await Task.sleep(nanoseconds: UInt64(Self.watchdogTimeout * 1_000_000_000))

                guard !Task.isCancelled else { break }

                guard let self = self else { break }

                let timeSinceLastMessage = Date().timeIntervalSince(await self.lastMessageTime)
                if timeSinceLastMessage > Self.watchdogTimeout {
                    print("[WebSocket] Watchdog triggered - connection stale")
                    await self.handleDisconnection()
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
            print("[WebSocket] Send failed: \(error)")
        }
    }
}
