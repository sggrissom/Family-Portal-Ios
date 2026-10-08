import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@Suite("Original photos")
struct OriginalPhotoTests {

    // MARK: - File names

    @Test("The uploaded file's own name is kept")
    func keepsServerName() {
        #expect(OriginalPhotoFile.filename(suggested: "IMG_0001.HEIC", mimeType: "image/heic", photoId: 9) == "IMG_0001.HEIC")
    }

    @Test("A name that could leave its folder is made safe")
    func sanitizes() {
        #expect(OriginalPhotoFile.filename(suggested: "../a/b.jpg", mimeType: "image/jpeg", photoId: 9) == "_a_b.jpg")
    }

    @Test("Without a usable name, the photo id and its type name the file")
    func fallsBack() {
        #expect(OriginalPhotoFile.filename(suggested: nil, mimeType: "image/jpeg", photoId: 9) == "photo-9.jpg")
        #expect(OriginalPhotoFile.filename(suggested: "original", mimeType: "image/png", photoId: 9) == "photo-9.png")
        #expect(OriginalPhotoFile.filename(suggested: "", mimeType: "application/octet-stream", photoId: 9) == "photo-9")
    }

    // MARK: - Download

    @Test("The original is downloaded to its own folder under the server's name")
    func downloads() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/9/original", respond: .init(
            status: 200,
            headers: ["Content-Type": "image/heic", "Content-Disposition": "attachment; filename=\"IMG_0001.HEIC\""],
            body: Data([1, 2, 3])
        ))

        let original = try await server.apiClient().downloadOriginal(photoId: 9)
        defer { original.remove() }

        #expect(original.fileURL.lastPathComponent == "IMG_0001.HEIC")
        #expect(original.fileURL.deletingLastPathComponent() == original.directory)
        #expect(try Data(contentsOf: original.fileURL) == Data([1, 2, 3]))
        #expect(original.mimeType == "image/heic")
        #expect(server.requests(for: "api/photo/9/original").count == 1)
    }

    @Test("Removing a downloaded original removes its folder")
    func removes() async throws {
        let server = FakeHTTPServer()
        server.route("api/photo/9/original", respond: .init(status: 200, headers: ["Content-Type": "image/jpeg"], body: Data([1])))

        let original = try await server.apiClient().downloadOriginal(photoId: 9)
        original.remove()
        #expect(!FileManager.default.fileExists(atPath: original.directory.path))
    }

    @Test("A photo the server can't find is an error, not an empty file")
    func notFound() async {
        let server = FakeHTTPServer()
        server.route("api/photo/9/original", respond: .status(404, message: "Not found"))

        await #expect(throws: APIError.self) {
            _ = try await server.apiClient().downloadOriginal(photoId: 9)
        }
    }

    @Test("Offline is reported as a network error")
    func offline() async {
        let server = FakeHTTPServer()
        server.route("api/photo/9/original", respond: .offline())

        await #expect(throws: APIError.self) {
            _ = try await server.apiClient().downloadOriginal(photoId: 9)
        }
    }
}

@MainActor
@Suite("Milestone photo suggestions")
struct MilestonePhotoSuggestionTests {

    private func photos(_ remoteIds: [String?], in context: ModelContext) -> [Photo] {
        remoteIds.map { remoteId -> Photo in
            let photo = Photo(title: "", descriptionText: "", photoDate: Date(), imageData: nil)
            photo.remoteId = remoteId
            context.insert(photo)
            return photo
        }
    }

    @Test("Suggestions keep the server's order and leave out what the milestone already had")
    func offered() throws {
        let context = try TestStore.makeContext()
        let choices = photos(["1", "2", "3", nil], in: context)
        let offered = MilestonePhotoSuggestions.offered([3, 2, 1, 99], choices: choices, alreadyAttached: [2])
        #expect(offered.map(\.remoteId) == ["3", "1"])
    }
}
