import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Milestone photo links")
struct MilestonePhotoTests {

    @Test("AddMilestone sends photoIds when photos are attached")
    func addCarriesPhotoIds() throws {
        let data = try JSONEncoder().encode(
            AddMilestoneRequestDTO(
                personId: 12,
                description: "First steps",
                category: "physical",
                inputType: "date",
                milestoneDate: "2026-03-15",
                ageYears: nil,
                ageMonths: nil,
                photoIds: [4, 9]
            )
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["photoIds"] as? [Int] == [4, 9])
    }

    @Test("A milestone with no photos omits the key entirely")
    func addOmitsEmptyPhotoIds() throws {
        let data = try JSONEncoder().encode(
            AddMilestoneRequestDTO(
                personId: 12,
                description: "First steps",
                category: "physical",
                inputType: "date",
                milestoneDate: "2026-03-15",
                ageYears: nil,
                ageMonths: nil,
                photoIds: nil
            )
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["photoIds"] == nil)
    }

    /// Update always sends the array, including empty, so detaching every photo
    /// is expressible. Omitting it would read as "leave them alone".
    @Test("Update can express detaching every photo")
    func updateSendsEmptyArray() throws {
        let data = try JSONEncoder().encode(
            UpdateMilestoneRequestDTO(
                id: 77,
                description: "First steps",
                category: "physical",
                inputType: "date",
                milestoneDate: "2026-03-15",
                ageYears: nil,
                ageMonths: nil,
                photoIds: []
            )
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let ids = try #require(object["photoIds"] as? [Int])
        #expect(ids.isEmpty)
    }

    @Test("Round-trips the ids the backend sends back")
    func decodesPhotoIdsFromResponse() throws {
        let json = """
        {
          "milestone": {
            "id": 77, "personId": 12, "familyId": 7,
            "description": "First steps", "category": "physical",
            "milestoneDate": "2026-03-15T00:00:00Z",
            "createdAt": "2026-03-15T10:00:00Z",
            "photoIds": [4, 9]
          }
        }
        """
        let response = try APIClient.decode(UpdateMilestoneResponseDTO.self, from: Data(json.utf8))

        #expect(response.milestone.photoIds == [4, 9])
    }

    @Test("Queued milestone payloads from an older build still decode")
    func legacyMilestonePayloadDecodes() throws {
        let json = """
        {
          "personLocalId": "abc",
          "description": "First steps",
          "category": "physical",
          "milestoneDate": "2026-03-15"
        }
        """
        let payload = try JSONDecoder().decode(CreateMilestonePayload.self, from: Data(json.utf8))

        #expect(payload.photoIds == nil)
        #expect(payload.inputType == nil)
        #expect(payload.description == "First steps")
    }
}
