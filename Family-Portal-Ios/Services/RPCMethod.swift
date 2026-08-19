import Foundation

/// Wire names for the backend's vbeam procs, called as `POST rpc/{rawValue}`.
///
/// vbeam derives a proc's name from its *Go function name* at registration
/// (`vbeam.RegisterProc` → `_LocalProcName`) and dispatches on that exact
/// string, so nothing on the Swift side can check a name against the server: a
/// typo compiles cleanly and fails only at runtime. That is how
/// `removePersonFromPhoto` shipped as `"RemovePersonFromPhoto"` against a
/// backend registering `RemovePersonFromPhotoProc`, silently reverting every
/// untag. Collecting the names here makes the whole set auditable against the
/// Go source in one pass, and `RPCMethodTests` pins the strings.
///
/// `nonisolated` so the `APIClient` actor can read these without hopping to the
/// main actor.
nonisolated enum RPCMethod: String, Sendable, CaseIterable {

    // MARK: - Account & family (backend/users.go, backend/password_reset.go)

    case createAccount = "CreateAccount"
    case requestPasswordReset = "RequestPasswordReset"
    case getFamilyInfo = "GetFamilyInfo"
    case joinFamily = "JoinFamily"

    // MARK: - Membership (backend/membership_procs.go)

    case listFamilyMembers = "ListFamilyMembers"
    case leaveFamily = "LeaveFamily"
    case removeFamilyMember = "RemoveFamilyMember"
    case rotateInviteCode = "RotateInviteCode"

    // MARK: - People (backend/person.go)

    case addPerson = "AddPerson"
    case updatePerson = "UpdatePerson"
    case setProfilePhoto = "SetProfilePhoto"
    case getFamilyTimeline = "GetFamilyTimeline"

    // MARK: - Growth data (backend/growth.go)

    case addGrowthData = "AddGrowthData"
    case updateGrowthData = "UpdateGrowthData"
    case deleteGrowthData = "DeleteGrowthData"

    // MARK: - Milestones (backend/milestone.go)

    case addMilestone = "AddMilestone"
    case updateMilestone = "UpdateMilestone"
    case deleteMilestone = "DeleteMilestone"

    // MARK: - Photos (backend/photos.go)

    case listFamilyPhotos = "ListFamilyPhotos"
    case updatePhoto = "UpdatePhoto"
    case deletePhoto = "DeletePhoto"
    case addPeopleToPhoto = "AddPeopleToPhoto"

    /// The one registration that does not match its own DTO names: the plain
    /// `RemovePersonFromPhoto` identifier is taken by a transaction helper
    /// (backend/photos.go:440), so the proc is `RemovePersonFromPhotoProc`.
    case removePersonFromPhoto = "RemovePersonFromPhotoProc"

    // MARK: - Tags (backend/tags.go)

    case listTags = "ListTags"

    /// Applying tags is registered from the record's own file rather than
    /// tags.go — `UpdatePhotoTags` in backend/photos.go, `UpdateMilestoneTags`
    /// in backend/milestone.go — but both are whole-set writes over the same
    /// vocabulary, so they are grouped with it here.
    case updatePhotoTags = "UpdatePhotoTags"
    case updateMilestoneTags = "UpdateMilestoneTags"

    // MARK: - Chat (backend/chat.go)

    case sendMessage = "SendMessage"
    case getChatMessages = "GetChatMessages"
    case deleteMessage = "DeleteMessage"

    // MARK: - Push notifications (backend/push_notifications.go)

    case registerPushDevice = "RegisterPushDevice"
    case unregisterPushDevice = "UnregisterPushDevice"

    // MARK: - Activities: structure (backend/activity_procs.go)
    //
    // Every activities proc is registered under its own Go function name —
    // there is no `…Proc` suffix anywhere in `RegisterActivityMethods`,
    // `RegisterActivityResultMethods`, `RegisterActivityViewMethods` or
    // `RegisterActivityPhotoMethods` — so the `RemovePersonFromPhotoProc` trap
    // does not recur here. These were read off the four `RegisterProc` blocks
    // rather than off the generated TypeScript.

    case listActivities = "ListActivities"
    case createActivity = "CreateActivity"
    case updateActivity = "UpdateActivity"
    case deleteActivity = "DeleteActivity"

    case listSeasons = "ListSeasons"
    case createSeason = "CreateSeason"
    case updateSeason = "UpdateSeason"
    case deleteSeason = "DeleteSeason"

    case createEvent = "CreateEvent"
    case updateEvent = "UpdateEvent"
    case deleteEvent = "DeleteEvent"

    case createEntry = "CreateEntry"
    case updateEntry = "UpdateEntry"
    case deleteEntry = "DeleteEntry"
    case setEntryRoster = "SetEntryRoster"

    // MARK: - Activities: appearances and results (backend/activity_results.go)

    case createAppearance = "CreateAppearance"
    case updateAppearance = "UpdateAppearance"
    case deleteAppearance = "DeleteAppearance"
    case setAppearanceResults = "SetAppearanceResults"

    // MARK: - Activities: aggregate reads (backend/activity_views.go)

    case getSeasonOverview = "GetSeasonOverview"
    case getEventDetail = "GetEventDetail"
    case getEntryHistory = "GetEntryHistory"
    case getPersonSeason = "GetPersonSeason"
    case listActivityVocabulary = "ListActivityVocabulary"

    // MARK: - Activities: photos (backend/activity_photos.go)

    case setAppearancePhotos = "SetAppearancePhotos"
    case setEventPhotos = "SetEventPhotos"
}
