import Foundation
import Testing
@testable import Family_Portal_Ios

/// `GetFamilyInfo` / `JoinFamily` in backend/users.go.
@Suite("Family DTOs")
struct FamilyDTOTests {

    @Test("Decodes FamilyInfoResponse, including the families list")
    func decodesFamilyInfo() throws {
        let json = """
        {
          "id": 3,
          "name": "Ada's Family",
          "inviteCode": "ABC123",
          "families": [
            { "id": 3, "name": "Ada's Family", "inviteCode": "ABC123", "role": 3, "isPrimary": true },
            { "id": 9, "name": "Grandparents", "inviteCode": "XYZ789", "role": 1, "isPrimary": false }
          ]
        }
        """
        let dto = try APIClient.decode(FamilyInfoResponseDTO.self, from: Data(json.utf8))

        #expect(dto.id == 3)
        #expect(dto.inviteCode == "ABC123")
        #expect(dto.families.count == 2)
        #expect(dto.families.first?.isPrimary == true)
        #expect(dto.families.last?.name == "Grandparents")
        #expect(dto.families.last?.inviteCode == "XYZ789")
        #expect(dto.families.last?.isPrimary == false)
    }

    /// A nil Go slice marshals as null, so the list must not be required.
    @Test("Tolerates a null families list")
    func toleratesNullFamilies() throws {
        let json = """
        { "id": 3, "name": "Ada's Family", "inviteCode": "ABC123", "families": null }
        """
        let dto = try APIClient.decode(FamilyInfoResponseDTO.self, from: Data(json.utf8))

        #expect(dto.families.isEmpty)
        #expect(dto.name == "Ada's Family")
    }

    @Test("JoinFamilyRequest uses the key the backend reads")
    func joinRequestKey() throws {
        let data = try JSONEncoder().encode(JoinFamilyRequestDTO(inviteCode: "ABC123"))
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(fields["inviteCode"] as? String == "ABC123")
    }

    /// JoinFamily reports failures in-band with HTTP 200.
    @Test("Decodes both outcomes of JoinFamily")
    func decodesJoinResponses() throws {
        let success = try APIClient.decode(
            JoinFamilyResponseDTO.self,
            from: Data("""
            {
              "success": true,
              "auth": { "id": 7, "name": "Ada", "email": "ada@example.com", "isAdmin": false, "familyId": 3, "families": [] }
            }
            """.utf8)
        )
        #expect(success.success)
        #expect(success.auth?.familyId == 3)

        let failure = try APIClient.decode(
            JoinFamilyResponseDTO.self,
            from: Data(#"{ "success": false, "error": "Invalid invite code" }"#.utf8)
        )
        #expect(!failure.success)
        #expect(failure.error == "Invalid invite code")
        #expect(failure.auth == nil)
    }
}
