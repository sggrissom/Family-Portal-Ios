import Foundation

/// Wire names for the backend's vbeam procs, called as `POST rpc/{rawValue}`.
/// vbeam dispatches on the Go function name it registered, so a typo compiles cleanly and fails only at runtime. Collecting the names here makes them auditable in one pass, and `RPCMethodTests` pins the strings.
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

    // MARK: - Relationships (backend/relation.go)

    case getPersonRelations = "GetPersonRelations"
    case addRelation = "AddRelation"
    case removeRelation = "RemoveRelation"

    // MARK: - Growth data (backend/growth.go)

    case addGrowthData = "AddGrowthData"
    /// A height and a weight on one day, saved both or neither.
    case addCheckup = "AddCheckup"
    case updateGrowthData = "UpdateGrowthData"
    case deleteGrowthData = "DeleteGrowthData"

    // MARK: - Milestones (backend/milestone.go)

    case addMilestone = "AddMilestone"
    case updateMilestone = "UpdateMilestone"
    case deleteMilestone = "DeleteMilestone"

    // MARK: - Milestone analysis (backend/milestone_analysis.go)
    // Online reads, never queued. Each comes back empty where the vision daemon isn't running.

    case suggestMilestoneCategory = "SuggestMilestoneCategory"
    case suggestMilestonePhotos = "SuggestMilestonePhotos"
    case getMilestoneMatches = "GetMilestoneMatches"

    // MARK: - Person photo insights (backend/person_photo_insights.go)
    // Face data, not the vision daemon, so this one answers in production too. Online read, never queued.

    case getPersonPhotoInsights = "GetPersonPhotoInsights"

    // MARK: - Photos (backend/photos.go)

    case listFamilyPhotos = "ListFamilyPhotos"
    /// Fetched by the photo page only, for the place and tag suggestions the mirrored list doesn't carry.
    case getPhoto = "GetPhoto"
    case updatePhoto = "UpdatePhoto"
    case deletePhoto = "DeletePhoto"
    case addPeopleToPhoto = "AddPeopleToPhoto"

    /// The one registration that does not match its own DTO names: the plain identifier is taken by a transaction helper, so the proc is `RemovePersonFromPhotoProc`.
    case removePersonFromPhoto = "RemovePersonFromPhotoProc"

    // MARK: - Tags (backend/tags.go)

    case listTags = "ListTags"
    case createTag = "CreateTag"
    case updateTag = "UpdateTag"
    case deleteTag = "DeleteTag"

    case updatePhotoTags = "UpdatePhotoTags"
    case updateMilestoneTags = "UpdateMilestoneTags"

    // MARK: - Tag suggestions (backend/tag_suggestions.go)
    // Online only and never queued, like membership changes: the server owns the outcome (accepting a catalog label can create a family tag).

    case getTagSuggestions = "GetTagSuggestions"
    case acceptTagSuggestions = "AcceptTagSuggestions"
    case rejectTagSuggestions = "RejectTagSuggestions"

    // MARK: - Chat (backend/chat.go)

    case sendMessage = "SendMessage"
    case getChatMessages = "GetChatMessages"
    case deleteMessage = "DeleteMessage"

    // MARK: - Push notifications (backend/push_notifications.go)

    case registerPushDevice = "RegisterPushDevice"
    case unregisterPushDevice = "UnregisterPushDevice"

    // MARK: - Activities: structure (backend/activity_procs.go)
    // Every activities proc is registered under its own Go function name, with no `…Proc` suffix anywhere, so the `RemovePersonFromPhotoProc` trap does not recur here.

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

    // MARK: - Overviews (backend/dashboard.go, backend/same_age.go)
    // Read-only aggregates. Cached like the activity reads, never queued.

    case getDashboard = "GetDashboard"
    case listOpenEvents = "ListOpenEvents"
    case getSameAge = "GetSameAge"

    // MARK: - Books (backend/book.go)
    // Reads are cached like the overviews; writes are online only. `GetBook` returns the records the book draws on with it, filtered to what the viewer may see.

    case listBooks = "ListBooks"
    case getBook = "GetBook"
    case getBookSources = "GetBookSources"
    case createBook = "CreateBook"
    case updateBook = "UpdateBook"
    case deleteBook = "DeleteBook"

    // MARK: - Faces (backend/faces.go)
    // Online only and never queued: naming a face makes the server re-match the family.

    case getFaceReview = "GetFaceReview"
    case assignFaces = "AssignFaces"
    case rejectFaces = "RejectFaces"
    case dismissFaces = "DismissFaces"

    // MARK: - Notification preferences (backend/notification_preferences.go)
    // Account settings, not device ones: online only and never queued, since a change means nothing until the server holds it.

    case getNotificationPreferences = "GetNotificationPreferences"
    case updateNotificationPreferences = "UpdateNotificationPreferences"
}
