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
        static let add = "Add"
        static let account = "Account"
    }

    enum account {
        static let signedInAs = "Signed in as"
        static let activities = "Activities"
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
        static let milestone = "Milestone"
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
        static let title = "Milestone"
        static let who = "Who is this about?"
        static let whatHappened = "What happened?"
        static let placeholder = "Wrote her name for the first time"
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

        static func atThisAge(_ age: String) -> String {
            age == "Newborn" ? "At birth" : "At \(age)"
        }
    }

    enum milestoneDetail {
        static let back = "Back"
        static let edit = "Edit"
        static let delete = "Delete"
        static let notFound = "That milestone could not be found."

        static func confirmDelete(_ text: String) -> String {
            "Delete this milestone: \"\(text)\"?"
        }

        static func atAge(_ age: String) -> String {
            "at \(age)"
        }

        static let matchesTitle = "The same milestone in the family"

        /// "Clara at 14 months" — first name only, as the web writes it; the age is left off for someone with no birthday.
        static func match(name: String, ageMonths: Int) -> String {
            let first = name.split(separator: " ").first.map(String.init) ?? name
            guard ageMonths >= 0 else { return first }
            return ageMonths == 0 ? "\(first) at birth" : "\(first) at \(AgeSteps.ageTitle(ageMonths))"
        }
    }

    enum person {
        enum tabs {
            static let story = "Story"
            static let photos = "Photos"
            static let growth = "Growth"
            static let activities = "Activities"
        }

        static let noPhotos = "No photos yet."
        static let openInPhotos = "Open in Photos →"
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
    }

    enum history {
        static let people = "People"
        static let more = "More"
        static let show = "Show"
        static let tags = "Tags"
        static let manageTags = "Manage tags →"
        static let clear = "Clear"
        static let search = "Search milestones"
        static let searchPlaceholder = "Search milestones"
        static let years = "Jump to year"
        static let empty = "Nothing recorded yet. Use + to add the first thing."
        static let noMatches = "Nothing matches these filters."

        static func loadYear(_ year: Int) -> String {
            "Load \(year)"
        }

        static func resultsFor(_ query: String, _ n: Int) -> String {
            "\(n == 1 ? "1 milestone" : "\(n) milestones") matching \"\(query)\""
        }

        enum types {
            static let milestones = "Milestones"
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
}

// swiftlint:enable type_name
