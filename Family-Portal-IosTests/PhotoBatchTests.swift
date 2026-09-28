import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// The photo batch form's choices, queued behind each photo's upload.
@MainActor
@Suite("Photo batch")
struct PhotoBatchTests {

    private static func queuedPhoto(in harness: TestSync.Harness) async throws -> Photo {
        let photo = Photo(title: "", descriptionText: "", photoDate: Date(), imageData: Data([0xFF, 0xD8]))
        harness.context.insert(photo)
        try harness.context.save()
        try await harness.service.uploadPhoto(photo)
        return photo
    }

    @Test("People, tags and caption queue in order, each waiting on the upload")
    func queuesBehindUpload() async throws {
        let harness = try TestSync.harness(connected: false)
        let person = Person(name: "Rowan", gender: .other)
        person.remoteId = "12"
        harness.context.insert(person)
        let photo = try await Self.queuedPhoto(in: harness)

        var choices = PhotoImporter.BatchChoices()
        choices.personIds = [person.id]
        choices.tagRemoteIds = [3]
        choices.caption = "Beach day"

        try await PhotoImporter.queueDetails(choices, changedDate: nil, for: photo, context: harness.context, syncService: harness.service)

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.map(\.type) == [.uploadPhoto, .addPeopleToPhoto, .updatePhotoTags, .updatePhoto])
        #expect(operations.dropFirst().allSatisfy { $0.dependsOnLocalId == photo.id.uuidString })
        #expect(photo.title == "Beach day")
        #expect(photo.taggedPeople.map(\.id) == [person.id])
    }

    @Test("A caption keeps the photo's date unless the date was changed")
    func keepsDateUnlessChanged() async throws {
        let harness = try TestSync.harness(connected: false)
        let kept = try await Self.queuedPhoto(in: harness)
        let changed = try await Self.queuedPhoto(in: harness)

        var choices = PhotoImporter.BatchChoices()
        choices.caption = "Beach day"
        try await PhotoImporter.queueDetails(choices, changedDate: nil, for: kept, context: harness.context, syncService: harness.service)
        try await PhotoImporter.queueDetails(PhotoImporter.BatchChoices(), changedDate: Date(timeIntervalSince1970: 0), for: changed, context: harness.context, syncService: harness.service)

        let updates = await harness.service.syncQueue.allOperations().filter { $0.type == .updatePhoto }
        let payloads = try updates.map { try JSONDecoder().decode(UpdatePhotoPayload.self, from: $0.payload) }
        #expect(updates.map(\.localId) == [kept.id.uuidString, changed.id.uuidString])
        #expect(payloads.map(\.keepDate) == [true, false])
    }

    @Test("Nothing chosen queues nothing beyond the upload, and tags nobody")
    func nothingChosen() async throws {
        let harness = try TestSync.harness(connected: false)
        let photo = try await Self.queuedPhoto(in: harness)

        try await PhotoImporter.queueDetails(PhotoImporter.BatchChoices(), changedDate: nil, for: photo, context: harness.context, syncService: harness.service)

        #expect(await harness.service.syncQueue.allOperations().map(\.type) == [.uploadPhoto])
        #expect(photo.taggedPeople.isEmpty)
    }

    @Test("A payload queued before keepDate existed still decodes, as a dated update")
    func legacyPayloadDecodes() throws {
        let data = Data(#"{"title":"","description":"","photoDate":"2026-01-05"}"#.utf8)
        let payload = try JSONDecoder().decode(UpdatePhotoPayload.self, from: data)
        #expect(payload.keepDate == nil)
    }

    @Test("An empty pick lists no entries")
    func emptyPick() throws {
        let importer = PhotoImporter()
        let ids = importer.importPicked([], into: try TestStore.makeContext(), syncService: nil, errorPresenter: nil)
        #expect(ids.isEmpty)
        #expect(importer.entries.isEmpty)
    }
}
