import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Mobile version policy")
struct MobileVersionTests {

    @Test("Maps the backend's status strings")
    func mapsWireValues() {
        #expect(MobileVersionStatus(wireValue: "ok") == .ok)
        #expect(MobileVersionStatus(wireValue: "update_available") == .updateAvailable)
        #expect(MobileVersionStatus(wireValue: "update_required") == .updateRequired)
    }

    @Test("An unrecognized status does not lock the user out")
    func unknownStatusIsPermissive() {
        #expect(MobileVersionStatus(wireValue: "") == .unknown)
        #expect(MobileVersionStatus(wireValue: "maintenance") == .unknown)
    }

    @Test("Decodes CheckMobileVersionResponse as the backend marshals it")
    func decodesPolicy() throws {
        let json = """
        {
          "status": "update_required",
          "minimumVersion": "1.2.0",
          "latestVersion": "1.4.1",
          "updateUrl": "https://apps.apple.com/app/id000000000",
          "updateMessage": "Please update to keep syncing."
        }
        """
        let dto = try APIClient.decode(MobileVersionPolicyDTO.self, from: Data(json.utf8))

        #expect(MobileVersionStatus(wireValue: dto.status) == .updateRequired)
        #expect(dto.minimumVersion == "1.2.0")
        #expect(dto.latestVersion == "1.4.1")
        #expect(dto.updateMessage == "Please update to keep syncing.")
    }

    @Test("The bundle's marketing version is strict major.minor.patch")
    func marketingVersionIsStrictSemver() throws {
        let version = try #require(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            "CFBundleShortVersionString is missing from the built Info.plist"
        )
        #expect(version == AppConstants.marketingVersion)

        let parts = version.split(separator: ".", omittingEmptySubsequences: false)

        #expect(parts.count == 3)
        for part in parts {
            let isAllDigits = part.allSatisfy { $0.isNumber }
            #expect(!part.isEmpty)
            #expect(isAllDigits)
            // The backend rejects leading zeros, e.g. "1.01.0".
            #expect(part.count == 1 || part.first != "0")
        }
    }

    @Test("The bundle declares iPhone-only device support")
    func declaresIPhoneOnly() throws {
        let families = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int],
            "UIDeviceFamily is missing from the built Info.plist"
        )
        #expect(families == [1])
    }

    @Test("The bundle ships a privacy manifest")
    func shipsPrivacyManifest() {
        #expect(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil)
    }
}
