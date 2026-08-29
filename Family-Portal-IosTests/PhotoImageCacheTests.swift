import Foundation
import Testing
import UIKit
@testable import Family_Portal_Ios

@MainActor
@Suite("Photo image cache", .serialized)
struct PhotoImageCacheTests {

    // MARK: - Fixtures

    private static func pngBytes() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.pngData()!
    }

    private static func imageResponse() -> FakeHTTPServer.Response {
        FakeHTTPServer.Response(
            status: 200,
            headers: ["Content-Type": "image/png"],
            body: pngBytes()
        )
    }

    private static func processingResponse() -> FakeHTTPServer.Response {
        FakeHTTPServer.Response(
            status: 200,
            headers: [
                "Content-Type": "image/svg+xml",
                "Cache-Control": "no-cache, no-store, must-revalidate"
            ],
            body: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)
        )
    }

    private nonisolated static func jwt(expiringIn interval: TimeInterval) -> String {
        let claims: [String: Any] = ["exp": Date().addingTimeInterval(interval).timeIntervalSince1970]
        let payload = (try? JSONSerialization.data(withJSONObject: claims)) ?? Data()
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    private static func cache(_ server: FakeHTTPServer) async -> PhotoImageCache {
        let client = server.apiClient()
        await client.setAccessToken(Self.jwt(expiringIn: 60 * 60))
        return PhotoImageCache(apiClient: client, session: server.session())
    }

    // MARK: - Caching

    @Test("A photo asked for twice is fetched once")
    func secondAskIsServedFromMemory() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/5/thumb", respond: Self.imageResponse())
        let cache = await Self.cache(server)

        guard case .image = await cache.image(remoteId: 5, size: .thumb) else {
            Issue.record("first fetch did not produce an image")
            return
        }
        guard case .image = await cache.image(remoteId: 5, size: .thumb) else {
            Issue.record("second fetch did not produce an image")
            return
        }

        // A gallery scrolling a cell back into view must not re-download it.
        #expect(server.requests(for: "api/photo/5/thumb").count == 1)
    }

    @Test("Simultaneous asks for the same photo share one download")
    func concurrentAsksAreCoalesced() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/5/thumb", respond: Self.imageResponse())
        let cache = await Self.cache(server)

        // A grid laying out ten cells of the same avatar in one pass.
        async let a = cache.image(remoteId: 5, size: .thumb)
        async let b = cache.image(remoteId: 5, size: .thumb)
        async let c = cache.image(remoteId: 5, size: .thumb)
        _ = await (a, b, c)

        #expect(server.requests(for: "api/photo/5/thumb").count == 1)
    }

    @Test("Different variants of one photo are cached apart")
    func variantsDoNotCollide() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/5/thumb", respond: Self.imageResponse())
        server.route("api/photo/5/xlarge", respond: Self.imageResponse())
        let cache = await Self.cache(server)

        _ = await cache.image(remoteId: 5, size: .thumb)
        _ = await cache.image(remoteId: 5, size: .xlarge)

        // A key that dropped the variant would serve a thumbnail full-screen.
        #expect(server.requests(for: "api/photo/5/thumb").count == 1)
        #expect(server.requests(for: "api/photo/5/xlarge").count == 1)
    }

    @Test("cachedImage answers only after something has been fetched")
    func cachedImageIsSynchronousAfterAFetch() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/5/thumb", respond: Self.imageResponse())
        let cache = await Self.cache(server)

        #expect(cache.cachedImage(remoteId: 5, size: .thumb) == nil)
        _ = await cache.image(remoteId: 5, size: .thumb)
        #expect(cache.cachedImage(remoteId: 5, size: .thumb) != nil)
    }

    // MARK: - Processing

    @Test("The processing placeholder is not a failure and is not cached")
    func processingIsDistinctFromFailure() async throws {
        let server = FakeHTTPServer()
        server.routeSequence("api/photo/9/thumb", [
            Self.processingResponse(),
            Self.imageResponse()
        ])
        let cache = await Self.cache(server)

        guard case .processing = await cache.image(remoteId: 9, size: .thumb) else {
            Issue.record("an SVG placeholder should read as processing")
            return
        }
        // Nothing was cached, so asking again reaches the server.
        #expect(cache.cachedImage(remoteId: 9, size: .thumb) == nil)

        guard case .image = await cache.image(remoteId: 9, size: .thumb) else {
            Issue.record("the finished photo should load on the next ask")
            return
        }
        #expect(server.requests(for: "api/photo/9/thumb").count == 2)
    }

    // MARK: - Failures

    @Test("A photo the server will not serve reads as unavailable")
    func missingPhotoIsUnavailable() async throws {
        let server = FakeHTTPServer()
        // status 2 — processing failed — is a 404 from servePhotoHandler.
        server.route("api/photo/9/thumb", respond: .status(404))
        let cache = await Self.cache(server)

        guard case .unavailable = await cache.image(remoteId: 9, size: .thumb) else {
            Issue.record("a 404 should read as unavailable")
            return
        }
    }

    @Test("Bytes that are not an image read as unavailable")
    func undecodableBodyIsUnavailable() async throws {
        let server = FakeHTTPServer()
        let server200 = FakeHTTPServer.Response(
            status: 200,
            headers: ["Content-Type": "image/jpeg"],
            body: Data("not an image".utf8)
        )
        server.route("api/photo/9/thumb", respond: server200)
        let cache = await Self.cache(server)

        guard case .unavailable = await cache.image(remoteId: 9, size: .thumb) else {
            Issue.record("undecodable bytes should read as unavailable")
            return
        }
    }

    @Test("Being offline does not poison the cache")
    func offlineIsRetryable() async throws {
        let server = FakeHTTPServer()
        server.routeSequence("api/photo/5/thumb", [
            .offline(),
            Self.imageResponse()
        ])
        let cache = await Self.cache(server)

        guard case .unavailable = await cache.image(remoteId: 5, size: .thumb) else {
            Issue.record("a dropped connection should read as unavailable")
            return
        }
        guard case .image = await cache.image(remoteId: 5, size: .thumb) else {
            Issue.record("the photo should load once the network is back")
            return
        }
    }

    // MARK: - Auth

    @Test("A 401 refreshes the token and fetches again")
    func staleTokenIsRefreshedOnce() async throws {
        let server = FakeHTTPServer()
        server.routeSequence("api/photo/5/thumb", [
            .status(401),
            Self.imageResponse()
        ])
        server.route("api/refresh", respond: .json(
            ["success": true, "token": "fresh-jwt"],
            headers: ["Set-Cookie": "refreshToken=rotated; Path=/"]
        ))
        let cookie = HTTPCookie(properties: [
            .domain: server.host,
            .path: "/",
            .name: "refreshToken",
            .value: "refresh-token",
            .expires: Date().addingTimeInterval(3600)
        ])!
        HTTPCookieStorage.shared.setCookie(cookie)

        let cache = await Self.cache(server)

        guard case .image = await cache.image(remoteId: 5, size: .thumb) else {
            Issue.record("the photo should load after a refresh")
            return
        }
        // Exactly one refresh and one replay: the token was fresh, so both are the 401 path.
        #expect(server.requests(for: "api/refresh").count == 1)
        #expect(server.requests(for: "api/photo/5/thumb").count == 2)
    }

    @Test("The request carries the bearer token")
    func requestIsAuthenticated() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/5/thumb", respond: Self.imageResponse())
        let cache = await Self.cache(server)

        _ = await cache.image(remoteId: 5, size: .thumb)

        let request = server.requests(for: "api/photo/5/thumb").first
        #expect(request?.headers["Authorization"]?.hasPrefix("Bearer ") == true)
        // Constant, so the server's `Vary: Accept` cannot split the cache per header.
        #expect(request?.headers["Accept"] == "image/webp,image/jpeg,*/*")
    }

    // MARK: - Invalidation

    @Test("removeAll drops what a previous account looked at")
    func removeAllClearsMemory() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/5/thumb", respond: Self.imageResponse())
        let cache = await Self.cache(server)

        _ = await cache.image(remoteId: 5, size: .thumb)
        #expect(cache.cachedImage(remoteId: 5, size: .thumb) != nil)

        cache.removeAll()

        #expect(cache.cachedImage(remoteId: 5, size: .thumb) == nil)
        _ = await cache.image(remoteId: 5, size: .thumb)
        #expect(server.requests(for: "api/photo/5/thumb").count == 2)
    }

    @Test("A full local reset clears the photo cache")
    func fullResetClearsThePhotoCache() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/5/thumb", respond: Self.imageResponse())
        let cache = await Self.cache(server)

        _ = await cache.image(remoteId: 5, size: .thumb)
        #expect(cache.cachedImage(remoteId: 5, size: .thumb) != nil)

        await LocalDataReset.erase(
            .everything,
            context: try TestStore.makeContext(),
            syncQueue: TestStore.makeQueue(),
            photoCache: cache
        )

        #expect(cache.cachedImage(remoteId: 5, size: .thumb) == nil)
    }

    @Test("A chat-only reset leaves the photo cache alone")
    func chatOnlyResetKeepsThePhotoCache() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/5/thumb", respond: Self.imageResponse())
        let cache = await Self.cache(server)

        _ = await cache.image(remoteId: 5, size: .thumb)

        await LocalDataReset.erase(
            .chatOnly,
            context: try TestStore.makeContext(),
            syncQueue: TestStore.makeQueue(),
            photoCache: cache
        )

        #expect(cache.cachedImage(remoteId: 5, size: .thumb) != nil)
    }
}
