import Foundation
import SwiftData
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Artwork")
struct ArtworkTests {

    @Test("Artwork comes down from the server as its own category")
    func decodesArtwork() throws {
        let json = try JSONSerialization.data(withJSONObject: Fixture.milestone(
            id: 41, personId: 12, description: "Drew the whole family as dinosaurs", category: "artwork", photoIds: [77]
        ))
        let milestone = applied(try APIClient.decode(MilestoneDTO.self, from: json))

        #expect(milestone.category == .artwork)
        #expect(milestone.category.label == "Artwork")
        #expect(milestone.photoRemoteIds == [77])
        #expect(milestone.displayText == "Drew the whole family as dinosaurs")
    }

    @Test("The form asks what they made")
    func asksWhatTheyMade() {
        #expect(MilestoneCategory.artwork.entryPrompt.label == Copy.milestone.whatTheyMade)
        #expect(MilestoneCategory.quote.entryPrompt.label == Copy.milestone.whatTheySaid)
        #expect(MilestoneCategory.first.entryPrompt.label == Copy.milestone.whatHappened)
    }

    @Test("A photo of the piece is tagged to the artist and uploads before the milestone that attaches it")
    func photoUploadsAheadOfMilestone() async throws {
        let harness = try TestSync.harness(connected: false)
        let artist = Person(name: "Rowan", gender: .other, birthday: Date())
        artist.remoteId = "12"
        harness.context.insert(artist)
        let milestone = Milestone(descriptionText: "Drew the whole family as dinosaurs", category: .artwork, date: Date())
        milestone.person = artist
        harness.context.insert(milestone)
        try harness.context.save()
        harness.server.route("api/upload-photo", respond: .json(["image": Fixture.image(id: 77, title: "")]))
        harness.server.route("rpc/AddMilestone", respond: .json([
            "milestone": Fixture.milestone(id: 41, personId: 12, description: "Drew the whole family as dinosaurs",
                                           category: "artwork", photoIds: [77])
        ]))

        let photos = try await ArtworkPhotos.queue(
            [PickedArtwork(data: Data([0xFF, 0xD8]), captureDate: nil)],
            artist: artist, context: harness.context, syncService: harness.service
        )
        try await harness.service.addMilestone(milestone, for: artist, photos: photos)
        #expect(photos.first?.taggedPeople.map(\.id) == [artist.id])

        harness.monitor.isConnected = true
        await harness.service.processQueue()

        #expect(harness.server.requests(for: "api/upload-photo").count == 1)
        let request = try #require(harness.server.requests(for: "rpc/AddMilestone").first)
        let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["category"] as? String == "artwork")
        #expect(body["photoIds"] as? [Int] == [77])
        #expect(await harness.service.syncQueue.count() == 0)
    }
}
