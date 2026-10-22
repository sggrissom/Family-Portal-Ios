import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Video")
struct VideoTests {

    // MARK: - Decoding and mapping

    private static let photoJSON = """
    {
      "id": 41, "familyId": 7, "ownerUserId": 3, "originalFilename": "IMG_1.HEIC",
      "mimeType": "image/heic", "fileSize": 1200, "width": 4032, "height": 3024,
      "filePath": "2025/41", "title": "Lake", "description": "",
      "photoDate": "2025-07-04T15:30:00Z", "createdAt": "2025-07-05T00:00:00Z",
      "status": 0
    }
    """

    private static let videoJSON = """
    {
      "id": 42, "familyId": 7, "ownerUserId": 3, "originalFilename": "IMG_2.MOV",
      "mimeType": "video/quicktime", "fileSize": 52000000, "width": 1920, "height": 1080,
      "filePath": "2025/42", "title": "First steps", "description": "",
      "photoDate": "2025-07-04T15:30:00Z", "createdAt": "2025-07-05T00:00:00Z",
      "status": 1, "tagIds": [5], "mediaKind": 1, "durationMs": 83400,
      "videoCodec": "hvc1.1.6.L93.B0", "audioCodec": "mp4a.40.2"
    }
    """

    @Test("An image from a server older than video decodes as a ready photo")
    func olderServer() throws {
        let photo = applied(try APIClient.decode(ImageDTO.self, from: Data(Self.photoJSON.utf8)))
        #expect(photo.mediaKind == .photo)
        #expect(!photo.isVideo)
        #expect(photo.videoBadgeDuration == nil)
        #expect(photo.durationMs == 0)
        #expect(photo.processingError.isEmpty)
    }

    @Test("A video maps its kind, length and status onto the local photo")
    func video() throws {
        let photo = applied(try APIClient.decode(ImageDTO.self, from: Data(Self.videoJSON.utf8)))
        #expect(photo.isVideo)
        #expect(photo.durationMs == 83_400)
        #expect(photo.videoBadgeDuration == 83_400)
        #expect(photo.status == 1)
        #expect(photo.tagRemoteIds == [5])
    }

    @Test("A rejected video keeps the server's reason")
    func rejected() throws {
        let json = Self.videoJSON
            .replacingOccurrences(of: "\"status\": 1", with: "\"status\": 2")
            .replacingOccurrences(of: "\"durationMs\": 83400", with: "\"processingError\": \"This video is longer than 10 minutes.\"")
        let photo = applied(try APIClient.decode(ImageDTO.self, from: Data(json.utf8)))
        #expect(photo.status == 2)
        #expect(photo.processingError == "This video is longer than 10 minutes.")
        #expect(photo.videoBadgeDuration == 0)
    }

    @Test("A media kind this build doesn't know reads as a photo")
    func unknownKind() throws {
        let json = Self.videoJSON.replacingOccurrences(of: "\"mediaKind\": 1", with: "\"mediaKind\": 7")
        let photo = applied(try APIClient.decode(ImageDTO.self, from: Data(json.utf8)))
        #expect(photo.mediaKind == .photo)
    }

    @Test("Playback decodes with and without its links")
    func playback() throws {
        let ready = """
        {"status": 0, "playbackUrl": "/api/media/object/p?sig=a", "mimeType": "video/mp4; codecs=\\"avc1.64001f, mp4a.40.2\\"",
         "downloadUrl": "/api/media/object/o?sig=b", "originalFilename": "IMG_2.MOV",
         "expiresAt": "2025-07-05T06:00:00.123456Z", "processingError": ""}
        """
        let dto = try APIClient.decode(GetVideoPlaybackResponseDTO.self, from: Data(ready.utf8))
        #expect(dto.playbackUrl == "/api/media/object/p?sig=a")
        #expect(dto.mimeType.contains("avc1"))
        #expect(dto.expiresAt != nil)

        let processing = #"{"status": 1, "playbackUrl": "", "mimeType": "video/mp4", "downloadUrl": "", "originalFilename": "a.mov", "expiresAt": "0001-01-01T00:00:00Z", "processingError": ""}"#
        let pending = try APIClient.decode(GetVideoPlaybackResponseDTO.self, from: Data(processing.utf8))
        #expect(pending.status == 1)
        #expect(pending.playbackUrl.isEmpty)
        #expect(pending.downloadUrl.isEmpty)
    }

    @Test("Upload instructions keep their headers")
    func instructions() throws {
        let json = #"{"uploadId": 9, "upload": {"url": "/api/media/upload/k?sig=c", "method": "PUT", "headers": {"Content-Type": "video/quicktime"}, "expiresAt": "2025-07-05T02:00:00Z"}}"#
        let dto = try APIClient.decode(BeginVideoUploadResponseDTO.self, from: Data(json.utf8))
        #expect(dto.uploadId == 9)
        #expect(dto.upload.method == "PUT")
        #expect(dto.upload.headers == ["Content-Type": "video/quicktime"])
    }

    // MARK: - Duration

    @Test("Durations print as the web prints them")
    func duration() {
        #expect(VideoDuration.format(milliseconds: 0) == "0:00")
        #expect(VideoDuration.format(milliseconds: 4_499) == "0:04")
        #expect(VideoDuration.format(milliseconds: 4_500) == "0:05")
        #expect(VideoDuration.format(milliseconds: 83_400) == "1:23")
        #expect(VideoDuration.format(milliseconds: 600_000) == "10:00")
        #expect(VideoDuration.format(milliseconds: 3_725_000) == "1:02:05")
        #expect(VideoDuration.format(milliseconds: -50) == "0:00")
    }

    // MARK: - Playback failures (the web's videoPlayback.test.ts table)

    private static let now = Date(timeIntervalSince1970: 1_000)
    private static let later = now.addingTimeInterval(3_600)

    private func classify(network: Bool, _ probe: Int?, at now: Date = VideoTests.now) -> PlaybackProblem {
        VideoPlayback.classify(isNetworkError: network, probeStatus: probe, now: now, expiresAt: Self.later)
    }

    @Test("A link at or near its expiry is renewed without probing")
    func nearExpiry() {
        #expect(classify(network: false, nil, at: Self.later) == .expired)
        #expect(classify(network: true, nil, at: Self.later.addingTimeInterval(-30)) == .expired)
    }

    @Test("A link the server refuses is renewed")
    func refused() {
        #expect(classify(network: false, 403) == .expired)
        #expect(classify(network: false, 400) == .expired)
        #expect(classify(network: false, 401) == .expired)
    }

    @Test("A reachable file the device won't decode is unsupported")
    func undecodable() {
        #expect(classify(network: false, 206) == .unsupported)
        #expect(classify(network: false, 200) == .unsupported)
    }

    @Test("An unreachable file is a connection problem")
    func unreachable() {
        #expect(classify(network: true, nil) == .network)
        #expect(classify(network: false, 502) == .network)
        #expect(classify(network: true, 206) == .network)
    }

    @Test("A URL-loading error beneath AVFoundation's counts as the network")
    func networkErrors() {
        let url = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        let wrapped = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [NSUnderlyingErrorKey: url])
        let decode = NSError(domain: "AVFoundationErrorDomain", code: -11828)
        #expect(VideoPlayback.isNetworkError(wrapped))
        #expect(!VideoPlayback.isNetworkError(decode))
        #expect(!VideoPlayback.isNetworkError(nil))
    }

    @Test("A probe goes out with a range and without credentials")
    func probe() async {
        let server = FakeHTTPServer()
        server.route("api/media/object/p", respond: .init(status: 206, headers: [:], body: Data([0])))
        let client = server.apiClient()
        await client.setAccessToken("jwt")

        #expect(await client.probeMedia("/api/media/object/p?sig=1") == 206)
        let request = server.requests(for: "api/media/object/p").first
        #expect(request?.headers["Range"] == "bytes=0-0")
        #expect(request?.headers["Authorization"] == nil)
    }

    // MARK: - Media links

    @Test("A relative link is on the API origin and keeps its signature")
    func relativeLink() {
        let base = URL(string: "https://family.example/app")!
        let url = APIClient.mediaURL("/api/media/object/abc?exp=1&sig=x%2By", baseURL: base)
        #expect(url?.absoluteString == "https://family.example/api/media/object/abc?exp=1&sig=x%2By")
    }

    @Test("An absolute link is used as is")
    func absoluteLink() {
        let base = URL(string: "https://family.example")!
        let link = "https://bucket.r2.example/v/abc.mp4?X-Amz-Signature=1"
        #expect(APIClient.mediaURL(link, baseURL: base)?.absoluteString == link)
        #expect(APIClient.mediaURL("", baseURL: base) == nil)
    }

    @Test("A video's original is fetched without the app's credentials")
    func originalWithoutCredentials() async throws {
        let server = FakeHTTPServer()
        server.route("api/media/object/orig", respond: .init(
            status: 200,
            headers: ["Content-Type": "video/quicktime"],
            body: Data([1, 2, 3])
        ))
        let client = server.apiClient()
        await client.setAccessToken("jwt")

        let original = try await client.downloadMedia(link: "/api/media/object/orig?sig=1", suggested: "IMG_2.MOV", photoId: 42)
        defer { original.remove() }

        #expect(original.fileURL.lastPathComponent == "IMG_2.MOV")
        #expect(try Data(contentsOf: original.fileURL) == Data([1, 2, 3]))
        let request = try #require(server.requests(for: "api/media/object/orig").first)
        #expect(request.headers["Authorization"] == nil)
        #expect(request.headers["Cookie"] == nil)
    }

    @Test("Without a name, a video's original is named by its type")
    func videoFallbackName() {
        #expect(OriginalPhotoFile.filename(suggested: "", mimeType: "video/quicktime", photoId: 42) == "photo-42.mov")
        #expect(OriginalPhotoFile.filename(suggested: nil, mimeType: "video/mp4", photoId: 42) == "photo-42.mp4")
    }
}
