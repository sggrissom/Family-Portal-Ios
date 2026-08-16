import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

/// Choosing a person's avatar from a photo they are tagged in. Three things here
/// are only checkable at runtime: the proc's request body (the Go handler rejects
/// on fields the compiler never sees), the tag precondition (server-side, and
/// worth five retries if it is discovered there), and the zero-means-unset
/// decoding that made every avatar ask for photo id 0.
@MainActor
@Suite("Profile photo")
struct ProfilePhotoTests {

    private struct Tagged {
        let person: Person
        let photo: Photo
    }

    /// A person and a photo the server already knows about, tagged together, so a
    /// `setProfilePhoto` on them queues with no dependency.
    private static func taggedPair(
        in harness: TestSync.Harness,
        personRemoteId: String? = "12",
        photoRemoteId: String? = "77",
        tagged: Bool = true
    ) throws -> Tagged {
        let person = Person(name: "Rowan", type: .child, gender: .other, birthday: Date())
        person.remoteId = personRemoteId
        harness.context.insert(person)

        let photo = Photo(title: "Beach", descriptionText: "", photoDate: Date(), imageData: nil)
        photo.remoteId = photoRemoteId
        if tagged {
            photo.taggedPeople = [person]
        }
        harness.context.insert(photo)

        try harness.context.save()
        return Tagged(person: person, photo: photo)
    }

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    // MARK: - Happy path

    @Test("Setting a profile photo sends the person, the photo and a centred crop")
    func setProfilePhotoPushesTheChoice() async throws {
        let harness = try TestSync.harness(connected: false)
        let pair = try Self.taggedPair(in: harness)
        harness.server.route("rpc/SetProfilePhoto", respond: .json([
            "person": Fixture.person(id: 12, name: "Rowan", profilePhotoId: 77,
                                     profileCropX: 50, profileCropY: 50, profileCropScale: 1)
        ]))

        try await harness.service.setProfilePhoto(pair.photo, for: pair.person)

        // Optimistic: the avatar has to change at the tap, not at the next sync.
        #expect(pair.person.profilePhotoId == 77)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let requests = harness.server.requests(for: "rpc/SetProfilePhoto")
        #expect(requests.count == 1)

        let body = try Self.body(of: try #require(requests.first))
        #expect(body["personId"] as? Int == 12)
        #expect(body["photoId"] as? Int == 77)
        // The backend reads 0/0 as "use the default", so iOS sends the centre it
        // means rather than letting the server infer it.
        #expect(body["cropX"] as? Double == 50)
        #expect(body["cropY"] as? Double == 50)
        #expect(body["cropScale"] as? Double == 1)

        #expect(await harness.service.syncQueue.count() == 0)
        #expect(harness.service.discardedChangeWarning == nil)
    }

    @Test("The person the server returns wins over the optimistic value")
    func responsePersonIsApplied() async throws {
        let harness = try TestSync.harness(connected: false)
        let pair = try Self.taggedPair(in: harness)
        // A crop chosen on the web for this same photo: the phone has no editor,
        // so the server's framing is the only one that can be right.
        harness.server.route("rpc/SetProfilePhoto", respond: .json([
            "person": Fixture.person(id: 12, name: "Rowan", profilePhotoId: 77,
                                     profileCropX: 32, profileCropY: 18, profileCropScale: 2.5)
        ]))

        try await harness.service.setProfilePhoto(pair.photo, for: pair.person)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(pair.person.profilePhotoId == 77)
        #expect(pair.person.profileCropX == 32)
        #expect(pair.person.profileCropY == 18)
        #expect(pair.person.profileCropScale == 2.5)
    }

    /// Re-picking the photo a person already uses must not snap the framing back
    /// to centre — cropping is web-only, so a reset here is unrecoverable on the
    /// device that caused it.
    @Test("Re-picking the current photo keeps the crop chosen for it")
    func repickingKeepsTheCrop() async throws {
        let harness = try TestSync.harness(connected: false)
        let pair = try Self.taggedPair(in: harness)
        pair.person.profilePhotoId = 77
        pair.person.profileCropX = 32
        pair.person.profileCropY = 18
        pair.person.profileCropScale = 2.5
        try harness.context.save()

        harness.server.route("rpc/SetProfilePhoto", respond: .json([
            "person": Fixture.person(id: 12, name: "Rowan", profilePhotoId: 77,
                                     profileCropX: 32, profileCropY: 18, profileCropScale: 2.5)
        ]))

        try await harness.service.setProfilePhoto(pair.photo, for: pair.person)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let body = try Self.body(of: try #require(harness.server.requests(for: "rpc/SetProfilePhoto").first))
        #expect(body["cropX"] as? Double == 32)
        #expect(body["cropY"] as? Double == 18)
        #expect(body["cropScale"] as? Double == 2.5)
    }

    // MARK: - Preconditions

    /// `SetProfilePhoto` (backend/person.go) rejects a photo the person is not
    /// tagged in. Discovering that server-side costs the operation five retries
    /// and then discards it silently, so the push refuses at the tap instead.
    @Test("Choosing a photo the person is not tagged in is refused without queueing")
    func untaggedPhotoIsRefused() async throws {
        let harness = try TestSync.harness(connected: false)
        let pair = try Self.taggedPair(in: harness, tagged: false)

        await #expect(throws: SyncError.self) {
            try await harness.service.setProfilePhoto(pair.photo, for: pair.person)
        }

        #expect(pair.person.profilePhotoId == nil)
        #expect(await harness.service.syncQueue.count() == 0)
    }

    @Test("A photo still waiting to upload blocks the choice rather than losing it")
    func unsyncedPhotoBlocksTheOperation() async throws {
        let harness = try TestSync.harness(connected: false)
        let pair = try Self.taggedPair(in: harness, photoRemoteId: nil)

        try await harness.service.setProfilePhoto(pair.photo, for: pair.person)

        // No remote id yet means no avatar to show, so nothing is applied locally
        // either — the operation catches up when the upload finishes.
        #expect(pair.person.profilePhotoId == nil)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/SetProfilePhoto").isEmpty)

        let operations = await harness.service.syncQueue.allOperations()
        #expect(operations.count == 1)
        #expect(operations.first?.retryCount == 0)
    }

    @Test("An unsynced person blocks the choice rather than losing it")
    func unsyncedPersonBlocksTheOperation() async throws {
        let harness = try TestSync.harness(connected: false)
        let pair = try Self.taggedPair(in: harness, personRemoteId: nil)

        try await harness.service.setProfilePhoto(pair.photo, for: pair.person)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/SetProfilePhoto").isEmpty)
        #expect(await harness.service.syncQueue.count() == 1)
    }

    @Test("A person deleted before the operation runs drops it")
    func deletedPersonDropsTheOperation() async throws {
        let harness = try TestSync.harness(connected: false)
        let pair = try Self.taggedPair(in: harness)

        try await harness.service.setProfilePhoto(pair.photo, for: pair.person)

        harness.context.delete(pair.person)
        try harness.context.save()

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "rpc/SetProfilePhoto").isEmpty)
        #expect(await harness.service.syncQueue.count() == 0)
    }

    // MARK: - Merging

    /// A person has exactly one avatar, so three offline picks are three states of
    /// one field, not three changes to replay.
    @Test("Picking again while offline replaces the queued choice")
    func repeatedChoicesMergeIntoOne() async throws {
        let harness = try TestSync.harness(connected: false)
        let pair = try Self.taggedPair(in: harness)

        let second = Photo(title: "Park", descriptionText: "", photoDate: Date(), imageData: nil)
        second.remoteId = "78"
        second.taggedPeople = [pair.person]
        harness.context.insert(second)
        try harness.context.save()

        harness.server.route("rpc/SetProfilePhoto", respond: .json([
            "person": Fixture.person(id: 12, name: "Rowan", profilePhotoId: 78,
                                     profileCropX: 50, profileCropY: 50, profileCropScale: 1)
        ]))

        try await harness.service.setProfilePhoto(pair.photo, for: pair.person)
        try await harness.service.setProfilePhoto(second, for: pair.person)

        #expect(await harness.service.syncQueue.count() == 1)

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        let requests = harness.server.requests(for: "rpc/SetProfilePhoto")
        #expect(requests.count == 1)

        let body = try Self.body(of: try #require(requests.first))
        #expect(body["photoId"] as? Int == 78)
    }

    // MARK: - Zero means unset

    /// Go marshals an unset int as `0`, not as an absent key. Taken literally,
    /// every person without a profile photo asked `RemotePhotoView` to load photo
    /// id 0, and every avatar in a grid did it on each appearance.
    @Test("A zero profile photo id decodes as no profile photo")
    func zeroProfilePhotoIdBecomesNil() async throws {
        let harness = try TestSync.harness()
        harness.server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([
            Fixture.timelineItem(person: Fixture.personWithUnsetProfilePhoto(id: 12))
        ])))
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Fixture.familyPhotos([])))

        await harness.service.pullFamilyData()

        let person = try #require(try harness.context.fetch(FetchDescriptor<Person>()).first)
        #expect(person.profilePhotoId == nil)
        #expect(person.profileCropX == nil)
        #expect(person.profileCropY == nil)
        // A zero scale is worse than no scale: it renders the avatar at 0×.
        #expect(person.profileCropScale == nil)
    }

    @Test("A real profile photo survives the same decoding")
    func setProfilePhotoIdIsKept() async throws {
        let harness = try TestSync.harness()
        harness.server.route("rpc/GetFamilyTimeline", respond: .json(Fixture.timeline([
            Fixture.timelineItem(
                person: Fixture.person(id: 12, profilePhotoId: 77,
                                       profileCropX: 32, profileCropY: 18, profileCropScale: 2.5)
            )
        ])))
        harness.server.route("rpc/ListFamilyPhotos", respond: .json(Fixture.familyPhotos([])))

        await harness.service.pullFamilyData()

        let person = try #require(try harness.context.fetch(FetchDescriptor<Person>()).first)
        #expect(person.profilePhotoId == 77)
        #expect(person.profileCropX == 32)
        #expect(person.profileCropY == 18)
        #expect(person.profileCropScale == 2.5)
    }

    /// `personFromDTO` used to copy the id by hand and drop the crop entirely, so
    /// a person met for the first time in a pull was framed differently from the
    /// same person met again in the next one.
    @Test("A newly created person carries the same crop as an updated one")
    func newPersonGetsTheCrop() {
        let dto = PersonDTO(
            id: 12,
            familyId: 7,
            name: "Rowan",
            type: 1,
            gender: 0,
            birthday: Date(),
            age: "6 years",
            profilePhotoId: 77,
            profileCropX: 32,
            profileCropY: 18,
            profileCropScale: 2.5
        )

        let person = personFromDTO(dto)

        #expect(person.remoteId == "12")
        #expect(person.profilePhotoId == 77)
        #expect(person.profileCropX == 32)
        #expect(person.profileCropY == 18)
        #expect(person.profileCropScale == 2.5)
    }
}
