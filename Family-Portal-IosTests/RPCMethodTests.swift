import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("RPC method names")
struct RPCMethodTests {

    // vbeam dispatches on the Go function name passed to vbeam.RegisterProc, so
    // every string below is the wire contract and nothing in Swift checks it
    // against the server — a rename on either side compiles clean and fails at
    // runtime. Each expectation was read off the corresponding RegisterProc
    // call in the Go source, so a drifting name has to fail here.

    @Test("Account and family proc names match the backend")
    func accountProcNames() {
        #expect(RPCMethod.createAccount.rawValue == "CreateAccount")
        #expect(RPCMethod.requestPasswordReset.rawValue == "RequestPasswordReset")
        #expect(RPCMethod.getFamilyInfo.rawValue == "GetFamilyInfo")
        #expect(RPCMethod.joinFamily.rawValue == "JoinFamily")
    }

    @Test("Person and timeline proc names match the backend")
    func personProcNames() {
        #expect(RPCMethod.addPerson.rawValue == "AddPerson")
        #expect(RPCMethod.updatePerson.rawValue == "UpdatePerson")
        #expect(RPCMethod.getFamilyTimeline.rawValue == "GetFamilyTimeline")
    }

    @Test("Growth data proc names match the backend")
    func growthProcNames() {
        #expect(RPCMethod.addGrowthData.rawValue == "AddGrowthData")
        #expect(RPCMethod.updateGrowthData.rawValue == "UpdateGrowthData")
        #expect(RPCMethod.deleteGrowthData.rawValue == "DeleteGrowthData")
    }

    @Test("Milestone proc names match the backend")
    func milestoneProcNames() {
        #expect(RPCMethod.addMilestone.rawValue == "AddMilestone")
        #expect(RPCMethod.updateMilestone.rawValue == "UpdateMilestone")
        #expect(RPCMethod.deleteMilestone.rawValue == "DeleteMilestone")
    }

    @Test("Photo proc names match the backend")
    func photoProcNames() {
        #expect(RPCMethod.listFamilyPhotos.rawValue == "ListFamilyPhotos")
        #expect(RPCMethod.updatePhoto.rawValue == "UpdatePhoto")
        #expect(RPCMethod.deletePhoto.rawValue == "DeletePhoto")
        #expect(RPCMethod.addPeopleToPhoto.rawValue == "AddPeopleToPhoto")
    }

    /// The regression this suite exists for. `RemovePersonFromPhoto` is a plain
    /// transaction helper in backend/photos.go, so the registered proc had to be
    /// named `RemovePersonFromPhotoProc`. Calling the un-suffixed name failed
    /// every untag: the queued operation retried five times, was discarded, and
    /// the next pull restored the tag — with nothing surfaced to the user.
    @Test("RemovePersonFromPhoto keeps its Proc suffix")
    func removePersonFromPhotoKeepsProcSuffix() {
        #expect(RPCMethod.removePersonFromPhoto.rawValue == "RemovePersonFromPhotoProc")
    }

    @Test("Chat proc names match the backend")
    func chatProcNames() {
        #expect(RPCMethod.sendMessage.rawValue == "SendMessage")
        #expect(RPCMethod.getChatMessages.rawValue == "GetChatMessages")
        #expect(RPCMethod.deleteMessage.rawValue == "DeleteMessage")
    }

    @Test("Push notification proc names match the backend")
    func pushProcNames() {
        #expect(RPCMethod.registerPushDevice.rawValue == "RegisterPushDevice")
        #expect(RPCMethod.unregisterPushDevice.rawValue == "UnregisterPushDevice")
    }

    @Test("Every proc name is distinct and non-empty")
    func procNamesAreDistinct() {
        let names = RPCMethod.allCases.map(\.rawValue)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    /// vbeam builds the request path itself, so a name carrying whitespace or a
    /// slash would produce a URL that 404s rather than a dispatch failure.
    @Test("Proc names are bare identifiers", arguments: RPCMethod.allCases)
    func procNamesAreBareIdentifiers(method: RPCMethod) {
        let name = method.rawValue
        #expect(!name.contains("/"))
        #expect(!name.contains(" "))
        #expect(name.first?.isUppercase == true)
    }
}
