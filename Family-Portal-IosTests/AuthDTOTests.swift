import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Auth DTOs")
struct AuthDTOTests {

    private func encodedFields(_ value: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test("CreateAccountRequest uses the keys the backend reads")
    func createAccountRequestKeys() throws {
        let request = CreateAccountRequestDTO(
            name: "Ada",
            email: "ada@example.com",
            password: "supersecret",
            confirmPassword: "supersecret",
            familyCode: "ABC123",
            initialPersonName: "Ada",
            initialPersonGender: 1,
            initialPersonBirthdate: "1990-12-10"
        )

        let fields = try encodedFields(request)

        #expect(fields["name"] as? String == "Ada")
        #expect(fields["email"] as? String == "ada@example.com")
        #expect(fields["password"] as? String == "supersecret")
        #expect(fields["confirmPassword"] as? String == "supersecret")
        #expect(fields["familyCode"] as? String == "ABC123")
        #expect(fields["initialPersonName"] as? String == "Ada")
        #expect(fields["initialPersonGender"] as? Int == 1)
        #expect(fields["initialPersonBirthdate"] as? String == "1990-12-10")
    }

    @Test("Decodes CreateAccountResponse as the backend marshals it")
    func decodesCreateAccountResponse() throws {
        let json = """
        {
          "success": true,
          "token": "jwt-token",
          "auth": {
            "id": 7,
            "name": "Ada",
            "email": "ada@example.com",
            "isAdmin": false,
            "familyId": 3,
            "families": [
              { "id": 3, "name": "Ada's Family", "role": 0, "isPrimary": true }
            ]
          }
        }
        """
        let dto = try APIClient.decode(CreateAccountResponseDTO.self, from: Data(json.utf8))

        #expect(dto.success)
        #expect(dto.token == "jwt-token")
        #expect(dto.auth?.id == 7)
        #expect(dto.auth?.email == "ada@example.com")
        #expect(dto.auth?.familyId == 3)
        #expect(dto.error == nil)
    }

    @Test("A rejected sign-up decodes its error message")
    func decodesCreateAccountFailure() throws {
        let json = """
        { "success": false, "error": "Email already registered" }
        """
        let dto = try APIClient.decode(CreateAccountResponseDTO.self, from: Data(json.utf8))

        #expect(!dto.success)
        #expect(dto.error == "Email already registered")
        #expect(dto.token == nil)
        #expect(dto.auth == nil)
    }

    @Test("RequestPasswordReset round-trips")
    func passwordResetWireFormat() throws {
        let fields = try encodedFields(RequestPasswordResetRequestDTO(email: "ada@example.com"))
        #expect(fields["email"] as? String == "ada@example.com")

        let response = try APIClient.decode(
            RequestPasswordResetResponseDTO.self,
            from: Data(#"{ "success": true }"#.utf8)
        )
        #expect(response.success)
        #expect(response.error == nil)
    }
}
