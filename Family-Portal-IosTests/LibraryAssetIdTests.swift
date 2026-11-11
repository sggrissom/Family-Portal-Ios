import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// `Photo.libraryAssetId` is device-local knowledge of where a photo came from, so nothing the server sends may clear it.
@MainActor
@Suite("Library asset ids")
struct LibraryAssetIdTests {

    @Test("A photo picked for a milestone remembers the library asset it came from")
    func milestonePickKeepsAssetId() async throws {
        let context = try TestStore.makeContext()
        let artist = Person(name: "Rowan", gender: .other, birthday: Date())
        context.insert(artist)

        let photos = try await MilestonePhotoUploads.queue(
            [
                PickedMilestonePhoto(data: Data([0xFF, 0xD8]), captureDate: nil, libraryAssetId: "ABC/L0/001"),
                PickedMilestonePhoto(data: Data([0xFF, 0xD8]), captureDate: nil),
            ],
            artist: artist, context: context, syncService: nil
        )

        #expect(photos.map(\.libraryAssetId) == ["ABC/L0/001", nil])
    }

    @Test("A pull's update leaves the asset id alone")
    func pullKeepsAssetId() throws {
        let photo = Photo(title: "", descriptionText: "", photoDate: Date())
        photo.libraryAssetId = "ABC/L0/001"
        let json = try JSONSerialization.data(withJSONObject: Fixture.image(id: 77, title: "Beach"))

        applyPhotoDTO(try APIClient.decode(ImageDTO.self, from: json), to: photo)

        #expect(photo.title == "Beach")
        #expect(photo.libraryAssetId == "ABC/L0/001")
    }
}
