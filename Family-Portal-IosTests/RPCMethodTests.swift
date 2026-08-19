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

    @Test("Membership proc names match the backend")
    func membershipProcNames() {
        #expect(RPCMethod.listFamilyMembers.rawValue == "ListFamilyMembers")
        #expect(RPCMethod.leaveFamily.rawValue == "LeaveFamily")
        #expect(RPCMethod.removeFamilyMember.rawValue == "RemoveFamilyMember")
        #expect(RPCMethod.rotateInviteCode.rawValue == "RotateInviteCode")
    }

    @Test("Person and timeline proc names match the backend")
    func personProcNames() {
        #expect(RPCMethod.addPerson.rawValue == "AddPerson")
        #expect(RPCMethod.updatePerson.rawValue == "UpdatePerson")
        #expect(RPCMethod.setProfilePhoto.rawValue == "SetProfilePhoto")
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

    /// The two writes are registered from the record's own file — photos.go and
    /// milestone.go — rather than tags.go, so their names were read off those
    /// `RegisterProc` calls and not from the tag registrations next to `ListTags`.
    @Test("Tag proc names match the backend")
    func tagProcNames() {
        #expect(RPCMethod.listTags.rawValue == "ListTags")
        #expect(RPCMethod.updatePhotoTags.rawValue == "UpdatePhotoTags")
        #expect(RPCMethod.updateMilestoneTags.rawValue == "UpdateMilestoneTags")
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

    /// All 26 activities procs, read off the four `RegisterProc` blocks
    /// (`RegisterActivityMethods`, `RegisterActivityResultMethods`,
    /// `RegisterActivityViewMethods`, `RegisterActivityPhotoMethods`) rather
    /// than off the generated TypeScript. Every one matches its Go function name
    /// exactly — there is no `…Proc` suffix anywhere in this feature — so the
    /// `RemovePersonFromPhotoProc` trap does not recur here.
    @Test("Activity structure proc names match the backend")
    func activityStructureProcNames() {
        #expect(RPCMethod.listActivities.rawValue == "ListActivities")
        #expect(RPCMethod.createActivity.rawValue == "CreateActivity")
        #expect(RPCMethod.updateActivity.rawValue == "UpdateActivity")
        #expect(RPCMethod.deleteActivity.rawValue == "DeleteActivity")

        #expect(RPCMethod.listSeasons.rawValue == "ListSeasons")
        #expect(RPCMethod.createSeason.rawValue == "CreateSeason")
        #expect(RPCMethod.updateSeason.rawValue == "UpdateSeason")
        #expect(RPCMethod.deleteSeason.rawValue == "DeleteSeason")

        #expect(RPCMethod.createEvent.rawValue == "CreateEvent")
        #expect(RPCMethod.updateEvent.rawValue == "UpdateEvent")
        #expect(RPCMethod.deleteEvent.rawValue == "DeleteEvent")

        #expect(RPCMethod.createEntry.rawValue == "CreateEntry")
        #expect(RPCMethod.updateEntry.rawValue == "UpdateEntry")
        #expect(RPCMethod.deleteEntry.rawValue == "DeleteEntry")
        #expect(RPCMethod.setEntryRoster.rawValue == "SetEntryRoster")
    }

    @Test("Appearance and result proc names match the backend")
    func activityResultProcNames() {
        #expect(RPCMethod.createAppearance.rawValue == "CreateAppearance")
        #expect(RPCMethod.updateAppearance.rawValue == "UpdateAppearance")
        #expect(RPCMethod.deleteAppearance.rawValue == "DeleteAppearance")
        #expect(RPCMethod.setAppearanceResults.rawValue == "SetAppearanceResults")
    }

    @Test("Activity aggregate read proc names match the backend")
    func activityViewProcNames() {
        #expect(RPCMethod.getSeasonOverview.rawValue == "GetSeasonOverview")
        #expect(RPCMethod.getEventDetail.rawValue == "GetEventDetail")
        #expect(RPCMethod.getEntryHistory.rawValue == "GetEntryHistory")
        #expect(RPCMethod.getPersonSeason.rawValue == "GetPersonSeason")
        #expect(RPCMethod.listActivityVocabulary.rawValue == "ListActivityVocabulary")
    }

    @Test("Activity photo proc names match the backend")
    func activityPhotoProcNames() {
        #expect(RPCMethod.setAppearancePhotos.rawValue == "SetAppearancePhotos")
        #expect(RPCMethod.setEventPhotos.rawValue == "SetEventPhotos")
    }

    @Test("Every proc name is distinct and non-empty")
    func procNamesAreDistinct() {
        let names = RPCMethod.allCases.map(\.rawValue)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    /// vbeam builds the request path itself, so a name carrying whitespace or a
    /// slash would produce a URL that 404s rather than a dispatch failure.
    ///
    /// Written as a loop rather than `@Test(arguments:)` because the argument
    /// expression lives in a macro attribute, where the `@testable` import
    /// doesn't make the app module's internal `RPCMethod` visible.
    @Test("Proc names are bare identifiers")
    func procNamesAreBareIdentifiers() {
        for method in RPCMethod.allCases {
            let name = method.rawValue
            #expect(!name.contains("/"), "\(name) contains a slash")
            #expect(!name.contains(" "), "\(name) contains whitespace")
            #expect(name.first?.isUppercase == true, "\(name) is not capitalized")
        }
    }
}
