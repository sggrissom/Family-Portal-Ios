import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Apple sign-in")
struct AppleSignInTests {

    private func encodedFields(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test("Login request uses the keys appleTokenLoginHandler reads")
    func requestKeys() throws {
        let fields = try encodedFields(AppleTokenLoginRequestDTO(idToken: "identity-token", name: "Ada Lovelace"))

        #expect(fields.count == 2)
        #expect(fields["idToken"] as? String == "identity-token")
        #expect(fields["name"] as? String == "Ada Lovelace")
    }

    @Test("Joins the name Apple hands over on the first authorization")
    func joinsNameComponents() {
        var components = PersonNameComponents()
        components.givenName = "Ada"
        components.familyName = "Lovelace"

        #expect(AppleSignInService.displayName(from: components) == "Ada Lovelace")
    }

    @Test("Reports no name rather than a blank one, so the server can pick its own")
    func emptyNameComponents() {
        #expect(AppleSignInService.displayName(from: nil) == "")
        #expect(AppleSignInService.displayName(from: PersonNameComponents()) == "")
    }

    @Test("Keeps a partial name Apple did hand over")
    func partialNameComponents() {
        var components = PersonNameComponents()
        components.givenName = "Ada"

        #expect(AppleSignInService.displayName(from: components) == "Ada")
    }
}
