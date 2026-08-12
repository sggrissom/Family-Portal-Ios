import Foundation
import Testing
@testable import Family_Portal_Ios

/// Linking photos to milestones — `AddMilestoneRequest.PhotoIds` and
/// `UpdateMilestoneRequest.PhotoIds` in backend/milestone.go.
@Suite("Milestone photo links")
struct MilestonePhotoTests {

    private func fields(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("AddMilestone sends photoIds")
    func addSendsPhotoIds() throws {
        let request = AddMilestoneRequestDTO(
            personId: 1,
            description: "First steps",
            category: "first",
            inputType: "date",
            milestoneDate: "2024-03-01",
            photoIds: [4, 9]
        )

        #expect(try fields(request)["photoIds"] as? [Int] == [4, 9])
    }

    /// backend/milestone.go updates links only `if req.PhotoIds != nil`, so an
    /// omitted key has to mean "leave them alone" on the wire too.
    @Test("A nil photoIds is omitted rather than sent as null")
    func nilPhotoIdsIsOmitted() throws {
        let request = UpdateMilestoneRequestDTO(
            id: 3,
            description: "First steps",
            category: "first",
            inputType: "date",
            milestoneDate: "2024-03-01",
            photoIds: nil
        )

        #expect(try fields(request)["photoIds"] == nil)
    }

    @Test("An empty photoIds is sent, which clears the links")
    func emptyPhotoIdsIsSent() throws {
        let request = UpdateMilestoneRequestDTO(
            id: 3,
            description: "First steps",
            category: "first",
            inputType: "date",
            milestoneDate: "2024-03-01",
            photoIds: []
        )

        #expect(try fields(request)["photoIds"] as? [Int] == [])
    }

    /// Queued operations are persisted as JSON and survive app updates, so a
    /// payload written before milestone photos existed still has to decode.
    @Test("Payloads queued before photo links still decode")
    func decodesLegacyQueuedPayloads() throws {
        let createJSON = """
        {
          "personLocalId": "F1D2C3B4-0000-0000-0000-000000000001",
          "description": "First steps",
          "category": "first",
          "milestoneDate": "2024-03-01"
        }
        """
        let create = try JSONDecoder().decode(CreateMilestonePayload.self, from: Data(createJSON.utf8))
        #expect(create.photoIds == nil)
        #expect(create.description == "First steps")

        let updateJSON = """
        { "description": "First steps", "category": "first", "milestoneDate": "2024-03-01" }
        """
        let update = try JSONDecoder().decode(UpdateMilestonePayload.self, from: Data(updateJSON.utf8))
        #expect(update.photoIds == nil)
    }
}
