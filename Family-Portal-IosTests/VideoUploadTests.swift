import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Video upload")
struct VideoUploadTests {

    // MARK: - File checks (the web's videoFiles tests)

    private static let support = GetVideoSupportResponseDTO(
        enabled: true, reason: "", maxBytes: 1024, maxDurationSeconds: 600, contentTypes: []
    )

    @Test("Types come from the extension")
    func contentTypes() {
        #expect(VideoFiles.contentType(forFilename: "IMG_1.MOV") == "video/quicktime")
        #expect(VideoFiles.contentType(forFilename: "clip.mp4") == "video/mp4")
        #expect(VideoFiles.contentType(forFilename: "clip.M4V") == "video/x-m4v")
        #expect(VideoFiles.contentType(forFilename: "a.webm") == nil)
    }

    @Test("Explains why a video can't be added")
    func problems() {
        #expect(VideoFiles.problem(filename: "a.mov", size: 10, support: Self.support) == nil)
        #expect(VideoFiles.problem(filename: "a.mov", size: 2048, support: Self.support)?.contains("over 1.0 KB") == true)
        #expect(VideoFiles.problem(filename: "a.webm", size: 10, support: Self.support)?.contains("not an MP4 or MOV") == true)

        var off = Self.support
        off.enabled = false
        off.reason = VideoUploadRefusal.disabled
        #expect(VideoFiles.problem(filename: "a.mov", size: 10, support: off) == "a.mov: Video uploads are not turned on for this family.")
        off.reason = ""
        #expect(VideoFiles.problem(filename: "a.mov", size: 10, support: off) == "a.mov: videos can't be added here")
    }

    @Test("Checks duration with a second of slack")
    func duration() {
        #expect(VideoFiles.durationProblem(filename: "a.mov", seconds: 600.5, maxSeconds: 600) == nil)
        #expect(VideoFiles.durationProblem(filename: "a.mov", seconds: nil, maxSeconds: 600) == nil)
        #expect(VideoFiles.durationProblem(filename: "a.mov", seconds: 725, maxSeconds: 600) == "a.mov is 12:05 long; videos can be at most 10 minutes")
    }

    @Test("Sizes print as the web prints them")
    func bytes() {
        #expect(VideoFiles.formatBytes(500) == "500 B")
        #expect(VideoFiles.formatBytes(1024) == "1.0 KB")
        #expect(VideoFiles.formatBytes(1_572_864) == "1.5 MB")
        #expect(VideoFiles.formatBytes(1 << 30) == "1.0 GB")
        #expect(VideoFiles.formatBytes(20 * 1_048_576) == "20 MB")
    }

    // MARK: - The contract

    private static let image: [String: Any] = [
        "id": 42, "familyId": 7, "ownerUserId": 3, "originalFilename": "IMG_2.MOV",
        "mimeType": "video/quicktime", "fileSize": 3, "width": 0, "height": 0,
        "filePath": "", "title": "", "description": "",
        "photoDate": "2025-07-04T00:00:00Z", "createdAt": "2025-07-05T00:00:00Z",
        "status": 1, "mediaKind": 1,
    ]

    private func server() -> FakeHTTPServer {
        let server = FakeHTTPServer()
        server.route("rpc/BeginVideoUpload", respond: .json([
            "uploadId": 9,
            "upload": [
                "url": "/api/media/upload/k",
                "method": "PUT",
                "headers": ["Content-Type": "video/quicktime"],
                "expiresAt": "2025-07-05T02:00:00Z",
            ],
        ]))
        server.route("api/media/upload/k", respond: .init(status: 200))
        server.route("rpc/CancelVideoUpload", respond: .json([String: Any]()))
        return server
    }

    private func file() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    private func upload(_ server: FakeHTTPServer) async throws -> ImageDTO {
        let client = server.apiClient()
        await client.setAccessToken("jwt")
        var service = VideoUploadService(apiClient: client)
        service.retryDelay = { _ in .zero }
        let url = try file()
        defer { try? FileManager.default.removeItem(at: url) }
        return try await service.upload(fileURL: url, filename: "IMG_2.MOV", contentType: "video/quicktime", size: 3, fallbackDate: "2025-07-04")
    }

    @Test("Begin, send as instructed without credentials, complete")
    func happyPath() async throws {
        let server = server()
        server.route("rpc/CompleteVideoUpload", respond: .json(["image": Self.image]))

        let image = try await upload(server)
        #expect(image.id == 42)
        #expect(image.mediaKind == 1)

        let begin = try #require(server.requests(for: "rpc/BeginVideoUpload").first)
        let sent = try JSONSerialization.jsonObject(with: begin.body) as? [String: Any]
        #expect(sent?["size"] as? Int == 3)
        #expect(sent?["contentType"] as? String == "video/quicktime")
        #expect(sent?["fallbackDate"] as? String == "2025-07-04")

        let put = try #require(server.requests(for: "api/media/upload/k").first)
        #expect(put.headers["Content-Type"] == "video/quicktime")
        #expect(put.headers["Authorization"] == nil)
        #expect(put.headers["Cookie"] == nil)
        #expect(server.requests(for: "rpc/CancelVideoUpload").isEmpty)
    }

    @Test("Completion is asked again after a failure, since it is idempotent")
    func completionRetried() async throws {
        let server = server()
        server.routeSequence("rpc/CompleteVideoUpload", [
            .status(500, message: "boom"),
            .offline(.timedOut),
            .json(["image": Self.image]),
        ])

        let image = try await upload(server)
        #expect(image.id == 42)
        #expect(server.requests(for: "rpc/CompleteVideoUpload").count == 3)
    }

    @Test("An expired session is not asked again")
    func expiredNotRetried() async throws {
        let server = server()
        server.route("rpc/CompleteVideoUpload", respond: .status(400, message: VideoUploadRefusal.expired))

        await #expect(throws: APIError.self) { _ = try await upload(server) }
        #expect(server.requests(for: "rpc/CompleteVideoUpload").count == 1)
    }

    @Test("A failed send cancels the session and never completes it")
    func failedSendCancels() async throws {
        let server = server()
        server.route("api/media/upload/k", respond: .status(403, message: "signature expired"))
        server.route("rpc/CompleteVideoUpload", respond: .json(["image": Self.image]))

        await #expect(throws: APIError.self) { _ = try await upload(server) }
        #expect(server.requests(for: "rpc/CancelVideoUpload").count == 1)
        #expect(server.requests(for: "rpc/CompleteVideoUpload").isEmpty)
    }

    @Test("Only an expired or unknown session stops the retries")
    func retryPolicy() {
        #expect(!VideoUploadService.isWorthRetrying(APIError.server(statusCode: 400, message: VideoUploadRefusal.expired)))
        #expect(!VideoUploadService.isWorthRetrying(APIError.server(statusCode: 400, message: VideoUploadRefusal.notFound)))
        #expect(VideoUploadService.isWorthRetrying(APIError.server(statusCode: 400, message: VideoUploadRefusal.missing)))
        #expect(VideoUploadService.isWorthRetrying(APIError.network(URLError(.timedOut))))
    }
}
