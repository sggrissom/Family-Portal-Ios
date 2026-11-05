import AppIntents
import Foundation
import SwiftData

/// Saves a quote without opening the app: "Add a quote from Emma in Family Record". Runs in the app's process, so the quote is written to the store and queued exactly as the moment form writes one — local first, synced when the queue next runs.
nonisolated struct AddQuoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Quote"
    static let description = IntentDescription("Writes down something someone in your family said.")

    @Parameter(title: "Person", requestValueDialog: "Who said it?")
    var person: PersonEntity

    @Parameter(title: "Quote", requestValueDialog: "What did they say?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) from \(\.$person)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let quote = try await QuickQuote.save(
            text,
            personRemoteId: person.id,
            context: DataStore.shared.container.mainContext,
            syncService: IntentServices.syncService,
            user: AuthService.cachedUser()
        )
        return .result(dialog: "Added to \(quote.personName)'s quotes.")
    }
}

/// Opens a person's page.
nonisolated struct OpenPersonIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Person"
    static let description = IntentDescription("Opens someone's page in Family Record.")
    static let openAppWhenRun = true

    @Parameter(title: "Person")
    var person: PersonEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.open(.person(remoteId: person.id))
        return .result()
    }
}

/// Opens Home, where On this day is.
nonisolated struct OpenOnThisDayIntent: AppIntent {
    static let title: LocalizedStringResource = "On This Day"
    static let description = IntentDescription("Opens Family Record to what happened on this day in earlier years.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkRouter.shared.open(.home)
        return .result()
    }
}

/// Opens search, run on the words given.
nonisolated struct SearchFamilyRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Family Record"
    static let description = IntentDescription("Searches your family's photos, moments and people.")
    static let openAppWhenRun = true

    @Parameter(title: "Search for")
    var query: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        DeepLinkRouter.shared.open(.search(query: trimmed?.isEmpty == false ? trimmed : nil))
        return .result()
    }
}

/// What Siri, Spotlight and the Action Button offer with no setup.
nonisolated struct FamilyRecordShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddQuoteIntent(),
            phrases: [
                "Add a quote from \(\.$person) in \(.applicationName)",
                "Add a quote in \(.applicationName)",
                "Save a quote in \(.applicationName)",
            ],
            shortTitle: "Add a Quote",
            systemImageName: "quote.bubble"
        )
        AppShortcut(
            intent: AddPhotosIntent(),
            phrases: ["Add photos to \(.applicationName)"],
            shortTitle: "Add Photos",
            systemImageName: "photo.on.rectangle"
        )
        AppShortcut(
            intent: OpenPersonIntent(),
            phrases: [
                "Open \(\.$person) in \(.applicationName)",
                "Show \(\.$person) in \(.applicationName)",
            ],
            shortTitle: "Open Person",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: OpenOnThisDayIntent(),
            phrases: ["On this day in \(.applicationName)"],
            shortTitle: "On This Day",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: SearchFamilyRecordIntent(),
            phrases: ["Search \(.applicationName)"],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
    }
}

/// The app's services as an intent reaches them. Set when the app starts, before any intent can run: the system launches the app to run one, and the `App` is built first.
@MainActor
enum IntentServices {
    static var syncService: SyncService?
}

/// Writes one quote the way the moment form does, for a caller with no form: today, said by `personRemoteId`, queued for sync.
@MainActor
enum QuickQuote {

    struct Saved {
        let milestone: Milestone
        let personName: String
    }

    nonisolated enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case signedOut
        case unknownPerson
        case viewOnly
        case empty

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .signedOut: "Sign in to Family Record first."
            case .unknownPerson: "That person isn't in Family Record on this phone yet. Open the app to sync, then try again."
            case .viewOnly: "You can view this family but not add to it."
            case .empty: "The quote was empty."
            }
        }
    }

    static func save(
        _ text: String,
        personRemoteId: Int,
        context: ModelContext,
        syncService: SyncService?,
        user: AuthResponseDTO?,
        today: Date = Date()
    ) async throws -> Saved {
        guard let user else { throw Failure.signedOut }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }

        let id = String(personRemoteId)
        var descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.remoteId == id })
        descriptor.fetchLimit = 1
        guard let person = try context.fetch(descriptor).first else { throw Failure.unknownPerson }
        guard FamilyAccess(auth: user).canContribute(to: person) else { throw Failure.viewOnly }

        let recordTime = RecordTime.exact(day: WhenEntry.localDateString(today))
        let milestone = Milestone(descriptionText: "", category: .quote, date: DaySummaries.date(of: recordTime.from) ?? today)
        milestone.setEntry(trimmed, context: "")
        milestone.person = person
        milestone.recordTime = recordTime
        context.insert(milestone)
        try context.save()

        // Queueing is local; the upload runs behind it, and the queue retries what doesn't make it before the system suspends the app.
        try await syncService?.addMilestone(milestone, for: person, recordTime: recordTime)
        return Saved(milestone: milestone, personName: person.name.firstName)
    }
}
