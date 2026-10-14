import Foundation

// swiftlint:disable type_name

/// Every user-facing string the web also has words for — a port of `frontend/lib/copy.ts`, keeping its nesting so `copy.home.turned(name, age)` there is `Copy.home.turned(name:age:)` here.
/// **This file and `copy.ts` are the same list.** When the web's wording changes, this changes in the same week; views don't inline a string the web has words for.
/// The namespaces are lowercase on purpose, so a line of Swift reads like the TypeScript it mirrors.
nonisolated enum Copy {

    enum nav {
        static let home = "Home"
        static let photos = "Photos"
        static let growth = "Growth"
        static let history = "History"
        static let chat = "Chat"
        static let books = "Books"
        static let sameAge = "Same age"
        static let activities = "Activities"
        static let more = "More"
        static let add = "Add"
        static let account = "Account"
        static let interviews = "Interviews"
    }

    /// The web's `moreSheet`: More's destinations, each with a line saying what it is for.
    enum more {
        static let history = "Everything, day by day"
        static let books = "Turn memories into a story"
        static let sameAge = "Compare everyone at the same age"
        static let activities = "Seasons, meets and results"
        static let chat = "Family messages"
        static let interviews = "Same questions, every year"
    }

    enum account {
        static let signedInAs = "Signed in as"
        static let activities = "Activities"
        static let books = "Books"
        static let tags = "Tags"
        static let faceReview = "Face review"
        static let settings = "Settings"
        static let importExport = "Import/Export"
        static let admin = "Admin"
        static let logOut = "Log out"
    }

    enum addSheet {
        static let title = "Add"
        static let whoFor = "Who is this for?"
        static let photos = "Photos"
        static let measurement = "Measurement"
        static let milestone = "Moment"
        static let close = "Close"
    }

    enum when {
        static let label = "When"
        static let today = "Today"
        static let yesterday = "Yesterday"
        static let pickDate = "Pick a date…"
        static let byAge = "By age…"
        static let date = "Date"
        static let years = "Age in years"
        static let months = "and months"
    }

    enum measurement {
        static let title = "Measurement"
        static let who = "Who was measured?"
        static let height = "Height"
        static let weight = "Weight"
        static let heightUnit = "Height unit"
        static let weightUnit = "Weight unit"
        static let feet = "Feet"
        static let inches = "Inches"
        static let pounds = "Pounds"
        static let ounces = "Ounces"
        static let save = "Save"
        static let saving = "Saving…"
        static let cancel = "Cancel"
        static let pickPerson = "Pick who was measured"
    }

    enum milestone {
        static let title = "Moment"
        static let who = "Who is this about?"
        static let whatHappened = "What happened?"
        static let placeholder = "Wrote her name for the first time"
        static let whatTheySaid = "What did they say?"
        static let whatTheyMade = "What did they make?"
        static let artworkPlaceholder = "Drew the whole family as dinosaurs"
        static let artworkPhotos = "Photos of it"
        static let addArtworkPhoto = "Add a photo of it"
        static let quotePlaceholder = "The moon is following our car!"
        static let context = "Context (optional)"
        static let contextPlaceholder = "On the drive home from Grandma's"
        static let category = "Category"
        static let more = "Add photos / tags"
        static let photos = "Photos"
        static let tags = "Tags"
        static let save = "Save"
        static let saving = "Saving…"
        static let cancel = "Cancel"
        static let pickPerson = "Pick who this is about"
        static let needsText = "Say what happened"
        static let suggested = "suggested"
        static let photosAroundThen = "Photos from around then. Attach any?"
        static let attachPhoto = "Attach this photo"
        static let detachPhoto = "Don't attach this photo"
    }

    enum photos {
        static let title = "Photos"
        static let choose = "Choose photos"
        static let addMore = "Add more"
        static let whoIsIn = "Who's in these?"
        static let caption = "Caption"
        static let captionPlaceholder = "Optional"
        static let tags = "Tags"
        static let taken = "Taken"
        static let change = "change"
        static let done = "Done"
        static let finishing = "Saving…"
        static let uploading = "Uploading"
        static let uploaded = "Uploaded"
        static let failed = "Failed"
        static let dropHint = "or drop them here"
    }

    enum home {
        static let seeAll = "See all"
        static let history = "History"
        static let addPerson = "Add family member"
        static let inSeason = "In season"
        static let onThisDay = "On this day"
        static let recent = "Recent"
        static let nothingRecent = "Nothing added in the last two weeks."
        static let dismiss = "Dismiss"
        static let checkup = "measured"
        static let checkupTitle = "Measured"
        static let addPhotos = "Add photos"
        static let addResults = "Add results"
        static let viewEvent = "View event"

        static func turned(name: String, age: Int) -> String {
            "\(name) turned \(age)"
        }

        static func photoCount(_ n: Int) -> String {
            n == 1 ? "1 photo" : "\(n) photos"
        }

        static func yearsAgo(_ n: Int) -> String {
            n == 1 ? "1 year ago" : "\(n) years ago"
        }

        static let eventTiming: [String: String] = ["now": "Today", "next": "Next", "last": "Last"]
    }

    static let result = "Result"

    enum sameAge {
        static let title = "Same age"
        static let at = "At"
        static let older = "Older"
        static let younger = "Younger"
        static let now = "now"
        static let noRecords = "no records at this age"
        static let seeAll = "See everything at this age →"
        static let nobodyElse = "Nobody else has anything from this age yet."
        static let empty = "Add birthdays to compare everyone at the same age."
        static let viewPhoto = "View photo"
        static let anotherPhoto = "Another photo"
        static let views = "View"
        static let portraits = "Portraits"
        static let details = "Details"
        static let shortcuts = "Common ages"
        static let chooseAge = "Choose an age"
        static let newbornHelp = "Newborn means from birth through day 27."
        static let retry = "Try again"
        static let loadFailed = "Could not load records. Please try again."
        static let offline = "You're offline, and this age hasn't been opened yet."
        static let onlyOne = "Try another age to compare more people."
        static let noSavedRecords = "No photos, moments or measurements to compare yet. Add records to a family member’s profile to get started."
        static let nothingAtAge = "No saved records near this age. Try another age."
        static let tryAnotherAge = "Pick another age above, or see Details for other records."
        static let openPhotoPage = "Open photo page"
        static let close = "Close"

        static func atThisAge(_ age: String) -> String {
            age == "Newborn" ? "At birth" : "At \(age)"
        }

        static func pictured(_ n: Int) -> String { "\(n) pictured" }
        static func withRecords(_ n: Int) -> String { "\(n) with records" }
        static func loading(_ age: String) -> String { "Loading \(age)…" }

        static func peopleWithRecords(_ n: Int) -> String {
            "\(n) \(n == 1 ? "person has" : "people have") records"
        }

        static func missingRecords(_ n: Int) -> String {
            "\(n) other \(n == 1 ? "person has" : "people have") no records near this age."
        }

        static func noPortraits(_ age: String) -> String {
            age == "Newborn" ? "No newborn photos yet." : "No photos from around \(age) yet."
        }

        static func onlyPictured(_ name: String) -> String {
            "Only \(name) has a photo at this age so far."
        }

        static func missingPhotos(_ age: String, _ n: Int) -> String {
            "No \(age == "Newborn" ? "newborn" : age) photo for \(n) \(n == 1 ? "person" : "people")"
        }

        static func openPortrait(_ name: String, _ age: String) -> String { "\(name), \(age): open photo" }
        static func photoOf(_ name: String) -> String { "Photo of \(name)" }
        static func photoCount(_ i: Int, _ n: Int) -> String { "Photo \(i) of \(n)" }
    }

    /// Settings' Notifications section — the web's on `settings.tsx`, plus what only the phone can say: whether iOS lets them through.
    enum notifications {
        static let title = "Notifications"
        static let accountNote = "These follow your account, not this iPhone, so they apply on every device you sign in on."
        static let chat = "Chat messages"
        static let chatDetail = "Notify me when someone in my family sends a message while I am away from the app."
        static let showText = "Show message text on the lock screen"
        static let showTextDetail = "Off by default: a notification says only that a message arrived, and you see who sent it and what it says after unlocking. Turn this on to show the sender and the message itself on the lock screen."
        static let saved = "Notification settings saved."
        static let saveFailed = "Could not save your notification settings."
        static let offline = "You're offline. Notification settings change on the server, so connect to change them."
        static let loadFailed = "Couldn't load your notification settings."
        static let retry = "Try Again"
        static let systemOff = "Notifications are turned off for Family Record in iOS Settings, so none will arrive on this iPhone whatever is chosen here."
        static let systemNotAsked = "This iPhone hasn't been asked to allow notifications yet."
        static let openSystemSettings = "Open iOS Settings"
    }

    /// The photo page's original-photo actions — the web's "Download original" on `view-photo.tsx`.
    enum originalPhoto {
        static let menu = "Share or save original"
        static let share = "Share Original"
        static let save = "Save to Photos"
        static let cancel = "Cancel download"
        static let saved = "Saved to Photos"
        static let notUploaded = "The original can be shared once this photo has uploaded."
        static let offline = "You're offline. The original photo downloads from the server."
        static let shareFailed = "Couldn't Share Photo"
        static let saveFailed = "Couldn't Save Photo"
    }

    /// Similar-photo groups and place filters on `family-photos.tsx`.
    enum photoBrowse {
        static let similarHeading = "Similar photos"
        static let showSimilar = "Show similar photos separately"
        static let similarHelp = "Similar shots are grouped by default. Tap a photo’s similar badge to browse the group. Search always shows individual matches."
        static let similarCaption = "Similar photos taken around the same time"
        static let placeHeading = "Place"
        static let anyPlace = "Any place"
        static let noPlaces = "No photo places yet."
        static let placesOffline = "Places need a connection."
        static let placeOffline = "You're offline, and the photos at this place haven't been loaded on this device yet."
        static let placeFailed = "Couldn't load the photos at this place."
        static let clearPlace = "Clear Place"
        static let notSyncedPhoto = "Photo not on this device yet"
        static let notSyncedNote = "This photo hasn't synced to this device yet, so only the photo itself is shown."

        static func similarTitle(_ n: Int) -> String { "\(n) similar photos" }
        static func similarBadge(_ n: Int) -> String { "\(n) similar \(n == 1 ? "photo" : "photos")" }
        static func notSyncedHeading(_ n: Int) -> String {
            "\(n) more \(n == 1 ? "photo" : "photos") from this place, not on this device yet"
        }
    }

    /// The web's search box on `family-photos.tsx`.
    enum photoSearch {
        static let prompt = "Search names, places, moments…"
        static let offlinePrompt = "Title or description"
        static let offlineNote = "Offline, so only titles and descriptions on this device were searched."
        static let textOnlyNote = "Image search is unavailable right now, so only titles and descriptions were searched."
        static let searching = "Searching…"
        static let failed = "Search didn't go through, so only titles and descriptions on this device were searched."
        static let clear = "Clear search"
        static let more = "Show more"

        static func bestMatches(_ query: String, with names: String) -> String {
            let base = "Best matches for \u{201C}\(query)\u{201D}"
            return names.isEmpty ? base : "\(base) with \(names)"
        }
    }

    /// The web's `copy.search`: global search, from the magnifying glass on every tab.
    enum search {
        static let title = "Search"
        static let label = "Search everything"
        static let placeholder = "Search people, moments, photos…"
        static func remove(_ label: String) -> String { "Remove \(label)" }
        static let understood = "Searching for"

        enum groups {
            static let people = "People"
            static let moments = "Moments"
            static let photos = "Photos"
            static let tags = "Tags"
            static let places = "Places"
            static let activities = "Activities"
            static let books = "Books"
        }

        enum quick {
            static let moments = "Moments"
            static let photos = "Photos"
            static let growth = "Growth"
        }

        static let seeAllPhotos = "See all photos"
        static func showAllMoments(_ n: Int) -> String { "Show all \(n) moments" }
        static let tagPhotos = "Photos with this tag"
        static let family = "Family"
        static let recent = "Recent searches"
        static let clearRecent = "Clear"
        static func nothing(_ query: String) -> String { "Nothing matched \u{201C}\(query)\u{201D}." }
        static func tryWithout(_ label: String) -> String { "Try without \(label)" }
        static let textOnly = "Matching words only. Searching by meaning is unavailable right now."
        static let searching = "Searching…"
        static let failed = "Search failed. Try again."
        static func by(_ names: [String]) -> String { names.joined(separator: ", ") }

        /// Chip labels for categories that read better plural (`CATEGORY_CHIPS`).
        static let categoryChips: [String: String] = [
            "quote": "Quotes",
            "artwork": "Artwork",
            "interview": "Interview answers",
        ]
    }

    /// The web's `suggestions.tsx` and the suggested-tag chips on `view-photo.tsx`.
    enum tagSuggestions {
        static let title = "Suggested Tags"
        static let subtitle = "Tags the app thinks fit your photos. Nothing is tagged until you say so, and anything you turn down won't be suggested again."
        static let onPhotoTitle = "Suggested tags"
        static let hint = "Tap a photo to leave it out."
        static let notThis = "Not this"
        static let emptyEnabled = "No suggestions right now. New photos are checked after they upload. You can teach the app your own tags by describing them on the tags page."
        static let emptyDisabled = "Photo analysis isn't running on this server, so there's nothing to suggest."
        static let offline = "Suggestions need a connection."
        static let acceptFailed = "Couldn't Add Tag"
        static let rejectFailed = "Couldn't Dismiss Suggestion"
        static let loadFailed = "Failed to reload suggestions"

        static func addTag(_ label: String) -> String {
            "Add tag \u{201C}\(label)\u{201D}"
        }

        static func suggestedLabel(_ label: String) -> String {
            "Suggested tag \(label)"
        }

        static func tagPhotos(_ count: Int, label: String) -> String {
            "Tag \(count) photo\(count == 1 ? "" : "s") \u{201C}\(label)\u{201D}"
        }

        /// "Not these" while every shown photo is included, "Not the selected" once some are left out.
        static func reject(all: Bool) -> String {
            all ? "Not these" : "Not the selected"
        }

        static func tagged(_ count: Int, label: String) -> String {
            "Tagged \(count) photo\(count == 1 ? "" : "s") \u{201C}\(label)\u{201D}."
        }

        static func more(_ count: Int) -> String {
            "\(count) more after these."
        }
    }

    enum milestoneDetail {
        static let back = "Back"
        static let edit = "Edit"
        static let delete = "Delete"
        static let notFound = "That moment could not be found."

        static func confirmDelete(_ text: String) -> String {
            "Delete this moment: \"\(text)\"?"
        }

        static func atAge(_ age: String) -> String {
            "at \(age)"
        }

        static let matchesTitle = "The same moment in the family"

        /// "Clara at 14 months" — first name only, as the web writes it; the age is left off for someone with no birthday.
        static func match(name: String, ageMonths: Int) -> String {
            let first = name.firstName
            guard ageMonths >= 0 else { return first }
            return ageMonths == 0 ? "\(first) at birth" : "\(first) at \(AgeSteps.ageTitle(ageMonths))"
        }
    }

    enum person {
        enum tabs {
            static let story = "Story"
            static let quotes = "Quotes"
            static let artwork = "Artwork"
            static let interviews = "Interviews"
            static let photos = "Photos"
            static let growth = "Growth"
            static let activities = "Activities"
        }

        static let noPhotos = "No photos yet."
        static let contextLabel = "Context"
        static let openInPhotos = "Open in Photos →"
        static let growingUp = "Growing up"
        static let seeGrowingUp = "See the full timeline →"
        static let oftenWith = "Often photographed with"
        static let useAsProfilePhoto = "Use as Profile Photo"
        static let metric = "Measurement"
        static let showSiblings = "Show siblings"
        static let measure = "Measure"
        static let noMeasurements = "No measurements of this kind yet."

        static func born(_ date: String) -> String {
            "born \(date)"
        }

        static func measured(_ ago: String) -> String {
            "Measured \(ago)"
        }

        static func siblingThen(name: String, value: String) -> String {
            "\(name) was \(value) at this age"
        }

        static func entries(_ n: Int) -> String {
            n == 1 ? "1 entry" : "\(n) entries"
        }

        static func next(_ event: String) -> String {
            "next: \(event)"
        }

        static func nothingYet(_ name: String) -> String {
            "Nothing recorded for \(name) yet. Use + to add something."
        }

        static func noQuotes(_ name: String) -> String {
            "No quotes from \(name) yet."
        }

        static func noArtwork(_ name: String) -> String {
            "No artwork from \(name) yet."
        }
    }

    enum history {
        static let people = "People"
        static let more = "More"
        static let show = "Show"
        static let tags = "Tags"
        static let manageTags = "Manage tags →"
        static let clear = "Clear"
        static let search = "Search moments"
        static let searchPlaceholder = "Search moments"
        static let years = "Jump to year"
        static let empty = "Nothing recorded yet. Use + to add the first thing."
        static let noMatches = "Nothing matches these filters."

        static func loadYear(_ year: Int) -> String {
            "Load \(year)"
        }

        static func resultsFor(_ query: String, _ n: Int) -> String {
            "\(n == 1 ? "1 moment" : "\(n) moments") matching \"\(query)\""
        }

        enum types {
            static let milestones = "Moments"
            static let measurements = "Measurements"
            static let photos = "Photos"
            static let activities = "Activities"
            static let birthdays = "Birthdays"
        }
    }

    enum ageChart {
        static let zoomHint = "Drag across the chart to zoom"
        static let resetZoom = "Reset zoom"
    }

    enum growthPage {
        static let title = "Growth"
        static let people = "People"
        static let metric = "Measurement"
        static let bands = "Percentile bands"
        static let bandsOff = "Off"
        static let girls = "Girls"
        static let boys = "Boys"
        static let measure = "Measure"
        static let empty = "Pick people with measurements to see them here."
        static let noData = "No measurements yet."
    }

    /// `copy.interview`. The paste importer's words are left out: importing stays on the web.
    enum interview {
        static let title = "Annual interview"
        static let editAnswer = "Edit answer"
        static let answerDateHint = "The date follows the interview. Change it from the interview page."

        static func answerOf(_ title: String) -> String { "Part of \(title) →" }
        static let previousAnswer = "← Previous answer"
        static let nextAnswer = "Next answer →"

        enum questions {
            static let title = "Interview questions"
            static let intro = "The questions you ask at each interview. Rewording one keeps its answers from earlier years lined up."
            static let save = "Save changes"
            static let saving = "Saving…"
            static let saved = "All changes saved"
            static let unsaved = "Unsaved changes"
            static let addQuestion = "Add a question"
            static let addQuestionPlaceholder = "What's your favorite…?"
            static let addSection = "Add a section"
            static let sectionPlaceholder = "Section name"
            static func renameSection(_ name: String) -> String { "Rename section \(name)" }
            static let questionText = "Question"
            static let ages = "Ages"
            static let minAge = "Youngest age"
            static let maxAge = "Oldest age"
            static let anyAge = "any age"
            static func ageRange(min: Int, max: Int) -> String {
                if min > 0 && max > 0 { return "ages \(min)–\(max)" }
                if min > 0 { return "ages \(min)+" }
                if max > 0 { return "up to age \(max)" }
                return "any age"
            }
            static let moveUp = "Move up"
            static let moveDown = "Move down"
            static let moveTo = "Move to section"
            static let retire = "Retire"
            static let restore = "Restore"
            static let delete = "Delete"
            static let mergeInto = "Merge into…"
            static let mergeHint = "Save your changes before merging."
            static func confirmMerge(from: String, into: String) -> String {
                "Move every answer to \"\(from)\" onto \"\(into)\" and retire \"\(from)\"? Answers keep the wording they were asked with."
            }
            static func retired(_ n: Int) -> String { "Retired questions (\(n))" }
            static let retiredHint = "Retired questions aren't offered for new interviews. Their answers stay."
            static func asked(_ n: Int) -> String { n == 0 ? "never asked" : n == 1 ? "asked once" : "asked \(n) times" }
            static func suggested(_ n: Int) -> String { n == 1 ? "1 new suggested question" : "\(n) new suggested questions" }
            static let add = "Add"
            static let addAll = "Add all"
            static let reset = "Reset to defaults"
            static let confirmReset = "Restore every retired built-in question and add any that are missing? Your own questions stay."
            static let placeholders = "Use {name} and {age} to fill in the child's name and age."
            static let emptySection = "No questions in this section yet."
            static let edit = "Edit"
        }

        enum setup {
            static func title(_ name: String) -> String { "Interview \(name)" }
            static func inProgress(_ name: String, answered: Int, total: Int) -> String {
                "\(name) has an interview in progress (\(answered) of \(total) answered)."
            }
            static let `continue` = "Continue it"
            static let date = "Date"
            static func age(_ name: String, _ age: Int) -> String { "\(name) is \(age) on this day" }
            static let showPrevious = "Show earlier answers while asking"
            static func questions(_ n: Int) -> String { n == 1 ? "1 question" : "\(n) questions" }
            static let editList = "Edit the question list"
            static let all = "All"
            static let none = "None"
            static let outsideAges = "outside the usual ages"
            static let justThisTime = "Just for this time"
            static let addOneOff = "Add a question just for this time"
            static let add = "Add"
            static let remove = "Remove"
            static let cancel = "Cancel"
            static func start(_ n: Int) -> String { "Start · \(n) \(n == 1 ? "question" : "questions")" }
            static let starting = "Starting…"
        }

        enum ask {
            static func progress(_ i: Int, _ n: Int) -> String { "\(i) of \(n)" }
            static let done = "Done"
            static let allQuestions = "All questions"
            static let answerPlaceholder = "Their answer"
            static let wasSkipped = "Skipped"
            static func atAge(_ age: Int) -> String { "Age \(age)" }
            static let back = "Back"
            static let skip = "Skip"
            static let next = "Next"
            static let retrying = "Not saved yet. Retrying…"
            static let addFollowUp = "+ Add a follow-up question"
            static let followUpText = "Follow-up question"
            static let justOnce = "Just this once"
            static let keepIt = "Keep it for next year"
            static let addQuestion = "Add question"
            static let cancel = "Cancel"
            static let takePortrait = "Take a portrait"
            static let retakePortrait = "Retake the portrait"
            static let uploading = "Uploading…"
            static let showPrevious = "Show earlier answers"
            static let statusAnswered = "answered"
            static let statusSkipped = "skipped"
            static let statusPending = "not asked yet"
            static func allDone(_ name: String) -> String { "That's everything for \(name)" }
            static func answeredCount(_ n: Int, _ total: Int) -> String { "\(n) of \(total) questions answered." }
            static func pendingIntro(_ n: Int) -> String {
                n == 1 ? "1 question hasn't been asked yet:" : "\(n) questions haven't been asked yet:"
            }
            static let askNow = "Ask now"
            static let leaveBlank = "Anything you don't ask stays blank."
            static let finish = "Finish interview"
            static let finishing = "Finishing…"
            static let unsavedOnFinish = "Some answers haven't saved yet. Check your connection and try again."
        }

        enum view {
            static func portraitOf(_ name: String) -> String { "Portrait of \(name)" }
            static func age(_ age: Int) -> String { "age \(age)" }
            static let inProgress = "in progress"
            static let `continue` = "Continue the interview"
            static let skipped = "skipped"
            static let notAsked = "not asked"
            static let delete = "Delete interview"
            static let confirmDelete = "Delete this interview and all of its answers? This can't be undone."
            static let deleteFailed = "The interview could not be deleted."
            static let whatChanged = "What changed since last time"
            static let editAnswers = "Edit answers"
            static let doneEditing = "Done"
            static let editDetails = "Edit details"
            static let title = "Title"
            static let titlePlaceholder = "7th birthday interview"
            static let date = "Date"
            static let notes = "Notes"
            static let notesPlaceholder = "At the kitchen table, very silly mood"
            static let portrait = "Portrait"
            static let changePortrait = "Change portrait"
            static let addPortrait = "Add a portrait"
            static let removePortrait = "Remove portrait"
            static let save = "Save"
            static let saving = "Saving…"
            static let cancel = "Cancel"
            static let saveFailed = "That could not be saved. Please try again."
            static let answerSaved = "Saved"
            static let reopen = "Reopen to keep asking"
        }

        enum tab {
            static func empty(_ name: String) -> String { "\(name) hasn't had an interview yet." }
            static let startFirst = "Start the first interview"
            static let start = "New interview"
            static let typeIn = "Type in a past one"
            static let `continue` = "Continue interview"
            static let inProgress = "in progress"
            static let years = "Years"
            static let questions = "Questions"
            static let question = "Question"
            static let skipped = "skipped"
            static let legendChanged = "New answer"
            static let legendSame = "faded answers are the same as the year before"
            static let filter = "Find a question or answer"
            static let sortLabel = "Sort"
            static let sortList = "List order"
            static let sortConsistent = "Most consistent"
            static let sortChanged = "Most changed"
            static let noMatches = "Nothing matches."
        }

        enum family {
            static let title = "Interviews"
            static let intro = "Ask the same questions every year and watch the answers change."
            static let editQuestions = "Edit questions"
            static let typeIn = "Type in a past one"
            static let start = "Start"
            static func `continue`(_ answered: Int, _ total: Int) -> String { "Continue · \(answered) of \(total)" }
            static let due = "Due soon"
            static let view = "See answers"
            static let never = "No interviews yet"
            static func last(age: Int, date: String, count: Int) -> String {
                "Last at \(age), \(date)\(count > 1 ? " · \(count) interviews" : "")"
            }
            static let others = "Everyone else"
            static let empty = "Add family members to interview them."
        }

        enum past {
            static func title(_ name: String) -> String { "Type in a past interview for \(name)" }
            static let intro = "Fill in whatever was asked. Leave the rest blank."
            static let when = "When was it?"
            static let retired = "retired"
            static func showRetired(_ n: Int) -> String { "Show retired questions (\(n))" }
            static let notOnList = "Questions that aren't on your list"
            static let question = "Question"
            static let answer = "Answer"
            static let addToList = "Add to my list"
            static let addQuestion = "+ Add a question"
            static let titleAndNotes = "Title and notes"
            static func save(_ n: Int) -> String { n == 1 ? "Save 1 answer" : "Save \(n) answers" }
            static let saving = "Saving…"
            static let saveFailed = "The interview could not be saved."
        }

        enum card {
            static let title = "Annual interview"
            static func whose(_ name: String) -> String { "\(name)'s annual interview" }
            static func age(_ age: Int) -> String { "age \(age)" }
            static let inProgress = "in progress"
            static func answers(_ n: Int) -> String { n == 1 ? "1 answer" : "\(n) answers" }
            static func someAnswers(_ n: Int, _ total: Int) -> String { "\(n) of \(total) answers" }
        }

        enum compare {
            static let title = "Compare at the same age"
            static let intro = "One question, everyone's answers, lined up by how old they were."
            static let question = "Question"
            static let who = "Who to compare"
            static func atAge(_ age: Int) -> String { "At \(age)" }
            static let allSame = "Everyone said the same thing."
            static let noAnswers = "Nobody has answered this one yet."
            static let empty = "There are no interview answers to compare yet."
            static let link = "Compare at the same age"
        }
    }
}

// swiftlint:enable type_name
