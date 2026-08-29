import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Push notification registration")
struct PushNotificationTests {

    @Test("RegisterPushDeviceRequest uses the keys the backend reads")
    func registerRequestKeys() throws {
        let request = RegisterPushDeviceRequestDTO(
            token: String(repeating: "a", count: 64),
            platform: "ios",
            environment: "sandbox",
            bundleId: "com.familyrecord.ios"
        )
        let data = try JSONEncoder().encode(request)
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(fields["token"] as? String == String(repeating: "a", count: 64))
        #expect(fields["platform"] as? String == "ios")
        #expect(fields["environment"] as? String == "sandbox")
        #expect(fields["bundleId"] as? String == "com.familyrecord.ios")
    }

    @Test("UnregisterPushDeviceRequest carries the token")
    func unregisterRequestKey() throws {
        let data = try JSONEncoder().encode(UnregisterPushDeviceRequestDTO(token: "abc"))
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(fields["token"] as? String == "abc")
    }

    @Test("Decodes the registration responses")
    func decodesResponses() throws {
        let register = try APIClient.decode(
            RegisterPushDeviceResponseDTO.self,
            from: Data(#"{ "success": true }"#.utf8)
        )
        let unregister = try APIClient.decode(
            UnregisterPushDeviceResponseDTO.self,
            from: Data(#"{ "success": true }"#.utf8)
        )

        #expect(register.success)
        #expect(unregister.success)
    }

    @Test("A Debug build registers against the APNs sandbox")
    @MainActor
    func debugBuildUsesSandbox() {
        #expect(PushNotificationService.environment == "sandbox")
    }
}
