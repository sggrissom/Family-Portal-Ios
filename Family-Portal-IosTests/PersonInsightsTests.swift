import CoreGraphics
import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Person photo insights")
struct PersonInsightsTests {

    private static let json: [String: Any] = [
        "growingUp": [
            ["photoId": 3, "box": ["left": 0.2, "top": 0.1, "right": 0.4, "bottom": 0.4], "date": "2025-01-05T00:00:00Z", "ageMonths": 6, "year": 2025],
            ["photoId": 4, "box": ["left": 0, "top": 0, "right": 0, "bottom": 0], "date": "0001-01-01T00:00:00Z", "ageMonths": -1, "year": 2019]
        ],
        "oftenWith": [
            ["person": Fixture.person(id: 5, name: "Clara"), "count": 12, "lastDate": "2026-09-01T00:00:00Z"]
        ],
        "header": NSNull()
    ]

    @Test("Decodes growing up, often with, and a missing header")
    func decodes() throws {
        let response = try APIClient.decode(
            GetPersonPhotoInsightsResponseDTO.self,
            from: JSONSerialization.data(withJSONObject: Self.json)
        )
        #expect(response.growingUp.map(\.photoId) == [3, 4])
        #expect(response.growingUp[0].box.hasArea)
        #expect(!response.growingUp[1].box.hasArea)
        #expect(response.oftenWith.first?.person.name == "Clara")
        #expect(response.oftenWith.first?.count == 12)
        #expect(response.header == nil)
    }

    @Test("Null lists decode as empty")
    func nullLists() throws {
        let response = try APIClient.decode(
            GetPersonPhotoInsightsResponseDTO.self,
            from: Data(#"{"growingUp":null,"oftenWith":null,"header":null}"#.utf8)
        )
        #expect(response.growingUp.isEmpty)
        #expect(response.oftenWith.isEmpty)
    }

    @Test("A face is labelled by age, or by year without a birthday")
    func labels() throws {
        let response = try APIClient.decode(
            GetPersonPhotoInsightsResponseDTO.self,
            from: JSONSerialization.data(withJSONObject: Self.json)
        )
        #expect(GetPersonPhotoInsightsResponseDTO.label(for: response.growingUp[0]) == "6 months")
        #expect(GetPersonPhotoInsightsResponseDTO.label(for: response.growingUp[1]) == "2019")
    }

    @Test("The crop is a padded square in pixels, centred on the face")
    func cropIsSquare() {
        let box = FaceBoxDTO(left: 0.4, top: 0.2, right: 0.5, bottom: 0.4)
        let size = CGSize(width: 2000, height: 1000)
        let rect = FaceCropLayout.cropRect(box: box, imageSize: size, padding: 0.35)

        // The face is 200 × 200 px; padded by 35% a side it is 340 px square.
        #expect(abs(rect.width * size.width - 340) < 0.001)
        #expect(abs(rect.height * size.height - 340) < 0.001)
        #expect(abs(rect.midX - 0.45) < 0.0001)
        #expect(abs(rect.midY - 0.3) < 0.0001)
    }

    @Test("Insights are cached for the session and a failed refresh keeps the cached answer")
    func cacheSurvivesFailure() async {
        let server = FakeHTTPServer()
        server.routeSequence("rpc/GetPersonPhotoInsights", [
            .json(Self.json),
            .status(500, message: "down")
        ])
        let service = AnalysisService(apiClient: server.apiClient())

        #expect(service.cachedPersonPhotoInsights(personId: 12) == nil)
        #expect(await service.refreshPersonPhotoInsights(personId: 12) != nil)
        #expect(await service.refreshPersonPhotoInsights(personId: 12) == nil)
        #expect(service.cachedPersonPhotoInsights(personId: 12)?.growingUp.count == 2)
    }
}
