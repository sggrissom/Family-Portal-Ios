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
        navigator.select(.growth)
        navigator.push(.faces)
        navigator.select(.home)
        #expect(navigator.depth(of: .growth) == 0)
    }

    @Test("The Faces screen's counts update the menu badge, and a disabled server hides it")
    func badgeFromReview() {
        let navigator = AppNavigator()
        navigator.updateFaceReviewCount(enabled: true, unknownCount: 4, autoCount: 2)
        #expect(navigator.faceReviewCount == 6)
        navigator.updateFaceReviewCount(enabled: false, unknownCount: 4, autoCount: 2)
        #expect(navigator.faceReviewCount == nil)
    }
}
