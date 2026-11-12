import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Face review")
struct FaceReviewTests {

    private static func face(id: Int, photoId: Int = 40, personId: Int = 0, status: Int = 0, distance: Double = 0) -> [String: Any] {
        [
            "id": id,
            "photoId": photoId,
            "familyId": 7,
            "personId": personId,
            "status": status,
            "distance": distance,
            "box": ["left": 0.2, "top": 0.1, "right": 0.4, "bottom": 0.35],
            "createdAt": "2026-03-01T10:00:00Z"
        ]
    }

    @Test("A face from a video crops from its frame, even the first; a photo's from the photo")
    func videoFaceFrames() throws {
        var video = Self.face(id: 1)
        video["frameMs"] = 0
        video["frameCount"] = 3
        var later = Self.face(id: 2)
        later["frameMs"] = 4200
        later["frameCount"] = 1
        let faces = try APIClient.decode([PhotoFaceDTO].self, from: Fixture.data([video, later, Self.face(id: 3)]))
        #expect(faces.map(\.videoFrameMs) == [0, 4200, nil])
    }

    private static func review(
        groups: Any = NSNull(),
        autoTagged: Any = NSNull(),
        families: Any = NSNull(),
        unknownCount: Int = 0,
        autoCount: Int = 0
    ) -> [String: Any] {
        [
            "enabled": true,
            "groups": groups,
            "autoTagged": autoTagged,
            "families": families,
            "unknownCount": unknownCount,
            "autoCount": autoCount
        ]
    }

    private static func service(_ server: FakeHTTPServer) -> FaceReviewService {
        FaceReviewService(apiClient: server.apiClient())
    }

    private static func body(of request: FakeHTTPServer.Request) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    }

    @Test("A review decodes groups, automatic tags and the people to name faces as")
    func decodesReview() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetFaceReview", respond: .json(Self.review(
            groups: [[
                "familyId": 7,
                "faces": [Self.face(id: 11), Self.face(id: 12, photoId: 41)],
                "suggestedPersonId": 5,
                "suggestionDistance": 0.41
            ]],
            autoTagged: [Self.face(id: 20, personId: 6, status: 1, distance: 0.5)],
            families: [[
                "familyId": 7,
                "name": "The Grissoms",
                "people": [Fixture.person(id: 5, name: "Ada"), Fixture.person(id: 6, name: "Bea")]
            ]],
            unknownCount: 2,
            autoCount: 1
        )))

        let review = try await Self.service(server).review()

        #expect(review.enabled)
        #expect(review.groups.count == 1)
        #expect(review.groups[0].id == 11)
        #expect(review.groups[0].faces.map(\.photoId) == [40, 41])
        #expect(review.groups[0].suggestedPersonId == 5)
        #expect(review.groups[0].faces[0].box.hasArea)
        #expect(review.autoTagged.map(\.id) == [20])
        #expect(review.people(inFamily: 7).map(\.name) == ["Ada", "Bea"])
        #expect(review.personName(6) == "Bea")
        #expect(review.personName(99) == "Unknown")
        #expect(review.familyName(7) == "The Grissoms")
        #expect(review.unknownCount == 2)
        #expect(review.autoCount == 1)
    }

    @Test("Null lists from Go decode as empty")
    func decodesNullLists() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/GetFaceReview", respond: .json(Self.review()))

        let review = try await Self.service(server).review()

        #expect(review.groups.isEmpty)
        #expect(review.autoTagged.isEmpty)
        #expect(review.families.isEmpty)
    }

    @Test("Assigning sends the faces and person, and reports what the server tagged")
    func assign() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/AssignFaces", respond: .json(["assigned": 2, "autoTagged": 3]))

        let response = try await Self.service(server).assign(faceIds: [11, 12], to: 5)

        #expect(response.assigned == 2)
        #expect(response.autoTagged == 3)
        let body = try Self.body(of: try #require(server.requests(for: "rpc/AssignFaces").first))
        #expect(body["faceIds"] as? [Int] == [11, 12])
        #expect(body["personId"] as? Int == 5)
    }

    @Test("Rejecting and dismissing go to their own procs")
    func rejectAndDismiss() async throws {
        let server = FakeHTTPServer()
        server.route("rpc/RejectFaces", respond: .json(["updated": 1]))
        server.route("rpc/DismissFaces", respond: .json(["updated": 2]))

        try await Self.service(server).reject(faceIds: [20])
        try await Self.service(server).dismiss(faceIds: [11, 12])

        let rejected = try Self.body(of: try #require(server.requests(for: "rpc/RejectFaces").first))
        #expect(rejected["faceIds"] as? [Int] == [20])
        let dismissed = try Self.body(of: try #require(server.requests(for: "rpc/DismissFaces").first))
        #expect(dismissed["faceIds"] as? [Int] == [11, 12])
    }

    @Test("Tags and Faces are borrowed screens, handed back when their tab is left")
    func routesAreBorrowed() {
        #expect(AppRoute.tags.isBorrowed)
        #expect(AppRoute.faces.isBorrowed)

        let navigator = AppNavigator()
        navigator.select(.explore)
        navigator.push(.faces)
        navigator.select(.home)
        #expect(navigator.depth(of: .explore) == 0)
    }

    @Test("The Faces screen's counts update the menu badge, and a disabled server hides it")
    func badgeFromReview() {
        let navigator = AppNavigator()
        navigator.updateFaceReviewCount(enabled: true, unknownCount: 4, autoCount: 2)
        #expect(navigator.faceReviewCount == 6)
        navigator.updateFaceReviewCount(enabled: false, unknownCount: 4, autoCount: 2)
        #expect(navigator.faceReviewCount == nil)
    }

    @Test("The menu badge asks for the count, and falls back to the full review on older servers")
    func badgeFromCount() async {
        let server = FakeHTTPServer()
        server.route("rpc/GetFaceReviewCount", respond: .json(["enabled": true, "unknownCount": 3, "autoCount": 1]))
        let navigator = AppNavigator()
        await navigator.refreshFaceReviewCount(apiClient: server.apiClient())
        #expect(navigator.faceReviewCount == 4)
        #expect(server.requests(for: "rpc/GetFaceReview").isEmpty)

        let older = FakeHTTPServer()
        older.route("rpc/GetFaceReview", respond: .json(Self.review(unknownCount: 2, autoCount: 5)))
        await navigator.refreshFaceReviewCount(apiClient: older.apiClient())
        #expect(navigator.faceReviewCount == 7)
    }

    private static func state() throws -> FaceReviewState {
        let dto = try APIClient.decode(GetFaceReviewResponseDTO.self, from: Fixture.data(Self.review(
            groups: [
                ["familyId": 7, "faces": [Self.face(id: 11), Self.face(id: 12), Self.face(id: 13)], "suggestedPersonId": 5],
                ["familyId": 7, "faces": [Self.face(id: 14)]]
            ],
            autoTagged: [Self.face(id: 20, personId: 6, status: 1), Self.face(id: 21, personId: 6, status: 1)],
            unknownCount: 4,
            autoCount: 2
        )))
        return FaceReviewState(dto)
    }

    @Test("Naming part of a group shrinks it in place and drops its suggestion")
    func namingPartOfAGroup() throws {
        var review = try Self.state()
        review.removeFromGroup(11, faceIds: [11, 12])
        review.recordAssigned(try APIClient.decode(AssignFacesResponseDTO.self, from: Fixture.data(["assigned": 2, "autoTagged": 0, "skipped": 0])))

        #expect(review.groups.map(\.id) == [11, 14])
        #expect(review.groups[0].faces.map(\.id) == [13])
        #expect(review.groups[0].suggestedPersonId == 0)
        #expect(review.unknownCount == 2)
    }

    @Test("An emptied group leaves, and skipped or auto-tagged faces move the counts")
    func namingAWholeGroup() throws {
        var review = try Self.state()
        review.removeFromGroup(14, faceIds: [14])
        review.removeFromGroup(11, faceIds: [11, 12, 13])
        review.recordAssigned(try APIClient.decode(AssignFacesResponseDTO.self, from: Fixture.data(["assigned": 2, "autoTagged": 1, "skipped": 1])))

        #expect(review.groups.isEmpty)
        #expect(review.unknownCount == 0)
        #expect(review.autoCount == 3)
    }

    @Test("Confirming or rejecting an automatic tag takes it off the list; a rejected face waits to be named")
    func automaticTags() throws {
        var review = try Self.state()
        review.removeAutoTag(20, rejected: false)
        #expect(review.autoTagged.map(\.id) == [21])
        #expect(review.autoCount == 1)
        #expect(review.unknownCount == 4)

        review.removeAutoTag(21, rejected: true)
        #expect(review.autoTagged.isEmpty)
        #expect(review.autoCount == 0)
        #expect(review.unknownCount == 5)
        #expect(!review.isEmpty)

        review.removeFromGroup(11, faceIds: [11, 12, 13])
        review.removeFromGroup(14, faceIds: [14])
        #expect(review.isEmpty)
    }
}
