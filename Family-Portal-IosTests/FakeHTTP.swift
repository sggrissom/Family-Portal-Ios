import Foundation
@testable import Family_Portal_Ios

/// A stand-in backend for tests that need to exercise `APIClient`, `SyncService`
/// or `ChatService` end to end rather than one decoder at a time.
///
/// Each instance owns a unique host, and the `URLProtocol` below routes purely on
/// that host, so suites running in parallel never see each other's routes or
/// recorded requests. `APIClient` already takes an injectable `URLSession`, which
/// is the whole hook this needs.
nonisolated final class FakeHTTPServer: @unchecked Sendable {

    struct Request: Sendable {
        /// Normalised without the leading slash: `rpc/GetFamilyTimeline`.
        let path: String
        let body: Data
        let headers: [String: String]
    }

    struct Response: Sendable {
        var status: Int
        var headers: [String: String]
        var body: Data
        /// When set, the request fails at the transport instead of answering —
        /// the shape of being offline, which the app treats differently from a
        /// server that answered with an error.
        var transportFailure: URLError.Code?

        init(
            status: Int = 200,
            headers: [String: String] = [:],
            body: Data = Data(),
            transportFailure: URLError.Code? = nil
        ) {
            self.status = status
            self.headers = headers
            self.body = body
            self.transportFailure = transportFailure
        }

        static func json(_ object: Any, status: Int = 200, headers: [String: String] = [:]) -> Response {
            var allHeaders = headers
            allHeaders["Content-Type"] = "application/json"
            return Response(
                status: status,
                headers: allHeaders,
                body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            )
        }

        /// A bare status, the way the backend answers a rejected request.
        static func status(_ status: Int, message: String = "") -> Response {
            Response(status: status, body: Data(message.utf8))
        }

        /// The connection dropping, rather than any reply from the server.
        static func offline(_ code: URLError.Code = .notConnectedToInternet) -> Response {
            Response(transportFailure: code)
        }
    }

    typealias Handler = @Sendable (Request) -> Response

    let host: String
    var baseURL: URL { URL(string: "https://\(host)")! }

    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    private var recorded: [Request] = []

    init() {
        host = "fake-\(UUID().uuidString.lowercased()).test"
        Self.register(self)
    }

    deinit {
        Self.unregister(host)
    }

    // MARK: - Wiring

    func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeURLProtocol.self]
        // No HTTP cache. A test that routes a sequence of responses is asserting
        // about what reached the server, and a cached 200 answering the second
        // request would make that assertion mean something else.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    func apiClient() -> APIClient {
        APIClient(baseURL: baseURL, session: session())
    }

    // MARK: - Routes

    func route(_ path: String, handler: @escaping Handler) {
        lock.withLock { handlers[Self.normalize(path)] = handler }
    }

    func route(_ path: String, respond response: Response) {
        route(path) { _ in response }
    }

    /// Answers with each response in turn, then repeats the last one. This is how
    /// a retry, a rotated token or a changed server state is expressed.
    func routeSequence(_ path: String, _ responses: [Response]) {
        precondition(!responses.isEmpty)
        let counter = Counter()
        route(path) { _ in
            let index = min(counter.next(), responses.count - 1)
            return responses[index]
        }
    }

    // MARK: - Inspection

    var allRequests: [Request] {
        lock.withLock { recorded }
    }

    func requests(for path: String) -> [Request] {
        let wanted = Self.normalize(path)
        return lock.withLock { recorded.filter { $0.path == wanted } }
    }

    // MARK: - Dispatch

    fileprivate func handle(path: String, body: Data, headers: [String: String]) -> Response {
        let normalized = Self.normalize(path)
        let request = Request(path: normalized, body: body, headers: headers)

        let handler = lock.withLock { () -> Handler? in
            recorded.append(request)
            return handlers[normalized]
        }

        guard let handler else {
            return .status(404, message: "No fake route for \(normalized)")
        }
        return handler(request)
    }

    private static func normalize(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    // MARK: - Host registry

    /// Weak so a server disappears with the test that made it, rather than
    /// keeping every route of every test alive for the whole run.
    private final class WeakServer {
        weak var server: FakeHTTPServer?
        init(_ server: FakeHTTPServer) { self.server = server }
    }

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: WeakServer] = [:]

    private static func register(_ server: FakeHTTPServer) {
        registryLock.withLock { registry[server.host] = WeakServer(server) }
    }

    private static func unregister(_ host: String) {
        registryLock.withLock { registry[host] = nil }
    }

    fileprivate static func server(forHost host: String) -> FakeHTTPServer? {
        registryLock.withLock { registry[host]?.server }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = -1

        func next() -> Int {
            lock.withLock {
                count += 1
                return count
            }
        }
    }
}

/// Serves any request whose host belongs to a live `FakeHTTPServer`, and ignores
/// everything else so a stray real URL still fails the way it would in the app.
nonisolated final class FakeURLProtocol: URLProtocol {

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return FakeHTTPServer.server(forHost: host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let host = url.host,
              let server = FakeHTTPServer.server(forHost: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = server.handle(
            path: url.path,
            body: Self.body(of: request),
            headers: request.allHTTPHeaderFields ?? [:]
        )

        if let failure = response.transportFailure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }

        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` moves `httpBody` into `httpBodyStream` before a protocol sees
    /// the request, so reading only `httpBody` would report every POST as empty.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
