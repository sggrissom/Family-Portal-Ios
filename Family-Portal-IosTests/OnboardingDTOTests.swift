import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Onboarding DTOs")
struct OnboardingDTOTests {

    // MARK: - CreateAccount (backend/users.go)

    @Test("CreateAccount request matches CreateAccountRequest")
    func createAccountRequestKeys() throws {
        let data = try JSONEncoder().encode(
            CreateAccountRequestDTO(
                name: "Dana",
                email: "dana@example.com",
                password: "hunter2hunter2",
                confirmPassword: "hunter2hunter2",
                familyCode: "ABC123"
            )
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["name"] as? String == "Dana")
        #expect(object["email"] as? String == "dana@example.com")
        #expect(object["password"] as? String == "hunter2hunter2")
        #expect(object["confirmPassword"] as? String == "hunter2hunter2")
        #expect(object["familyCode"] as? String == "ABC123")
    }

    @Test("Omitting the family code is encoded as absent, not empty")
    func createAccountWithoutFamilyCode() throws {
        let data = try JSONEncoder().encode(
            CreateAccountRequestDTO(
                name: "Dana",
                email: "dana@example.com",
                password: "hunter2hunter2",
                confirmPassword: "hunter2hunter2",
                familyCode: nil
            )
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        // familyCode is `omitempty` on the Go side; AddUserTx creates
        // "<Name>'s Family" when it's blank.
        #expect(object["familyCode"] == nil)
    }

    @Test("Decodes a successful CreateAccountResponse")
    func decodesCreateAccountSuccess() throws {
        let json = """
        {
          "success": true,
          "token": "jwt.token.value",
          "auth": {
            "id": 33, "name": "Dana", "email": "dana@example.com",
            "isAdmin": false, "familyId": 7, "families": []
          }
        }
        """
        let dto = try APIClient.decode(CreateAccountResponseDTO.self, from: Data(json.utf8))

        #expect(dto.success)
        #expect(dto.token == "jwt.token.value")
        #expect(dto.auth?.id == 33)
        #expect(dto.auth?.familyId == 7)
        #expect(dto.error == nil)
    }

    @Test("Decodes a rejected CreateAccountResponse")
    func decodesCreateAccountFailure() throws {
        // The proc reports validation problems in-band with success=false
        // rather than as a transport error.
        let json = """
        { "success": false, "error": "Email already registered" }
        """
        let dto = try APIClient.decode(CreateAccountResponseDTO.self, from: Data(json.utf8))

        #expect(!dto.success)
        #expect(dto.error == "Email already registered")
        #expect(dto.token == nil)
        #expect(dto.auth == nil)
    }

    // MARK: - Password reset (backend/password_reset.go)

    @Test("Password reset request carries just the email")
    func passwordResetRequestKeys() throws {
        let data = try JSONEncoder().encode(
            RequestPasswordResetRequestDTO(email: "dana@example.com")
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object.count == 1)
        #expect(object["email"] as? String == "dana@example.com")
    }

    @Test("Decodes a password reset response")
    func decodesPasswordResetResponse() throws {
        let dto = try APIClient.decode(
            RequestPasswordResetResponseDTO.self, from: Data(#"{"success":true}"#.utf8)
        )
        #expect(dto.success)
        #expect(dto.error == nil)
    }

    // MARK: - Family membership (backend/users.go)

    @Test("Decodes FamilyInfoResponse with multiple families")
    func decodesFamilyInfo() throws {
        let json = """
        {
          "id": 7,
          "name": "Dana's Family",
          "inviteCode": "ABC123",
          "families": [
            { "id": 7, "name": "Dana's Family", "inviteCode": "ABC123", "role": 3, "isPrimary": true },
            { "id": 9, "name": "Grandparents", "inviteCode": "XYZ789", "role": 1, "isPrimary": false }
          ]
        }
        """
        let dto = try APIClient.decode(FamilyInfoResponseDTO.self, from: Data(json.utf8))

        #expect(dto.id == 7)
        #expect(dto.inviteCode == "ABC123")
        #expect(dto.families.count == 2)
        #expect(dto.families[0].isPrimary)
        #expect(!dto.families[1].isPrimary)
        #expect(dto.families[1].name == "Grandparents")
    }

    @Test("Tolerates a response with no families array")
    func decodesFamilyInfoWithoutFamilies() throws {
        let json = """
        { "id": 7, "name": "Dana's Family", "inviteCode": "ABC123" }
        """
        let dto = try APIClient.decode(FamilyInfoResponseDTO.self, from: Data(json.utf8))

        #expect(dto.families.isEmpty)
        #expect(dto.inviteCode == "ABC123")
    }

    @Test("JoinFamily request matches JoinFamilyRequest")
    func joinFamilyRequestKeys() throws {
        let data = try JSONEncoder().encode(JoinFamilyRequestDTO(inviteCode: "XYZ789"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["inviteCode"] as? String == "XYZ789")
    }

    @Test("Decodes a rejected JoinFamilyResponse")
    func decodesJoinFamilyFailure() throws {
        let json = """
        { "success": false, "error": "Invalid invite code" }
        """
        let dto = try APIClient.decode(JoinFamilyResponseDTO.self, from: Data(json.utf8))

        #expect(!dto.success)
        #expect(dto.error == "Invalid invite code")
    }
}
