import AppIntents

/// A person, as Siri, Shortcuts and the widgets offer them. The choices come from the widget snapshot's people — the ones with a server id, by first name — so choosing one needs no network, and the app and the widget extension agree on who there is.
///
/// Compiled into the app and the widget extension, not the share extension. `nonisolated` because the app target defaults to main-actor isolation and the extension does not.
nonisolated struct PersonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static let defaultQuery = PersonQuery()

    /// The server id.
    var id: Int
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

nonisolated struct PersonQuery: EntityQuery, EntityStringQuery {
    private var people: [PersonEntity] {
        (WidgetStore.shared()?.read()?.people ?? []).map { PersonEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [Int]) async throws -> [PersonEntity] {
        people.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [PersonEntity] {
        people.filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [PersonEntity] {
        people
    }
}

/// Opens the app to the add flow's photo picker. Shared with the widget extension so a Control Center control can run it; `openAppWhenRun`, so the system runs it in the app, where the router is.
nonisolated struct AddPhotosIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Photos"
    static let description = IntentDescription("Opens Family Record to choose photos to add.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if FAMILY_RECORD_APP
        DeepLinkRouter.shared.open(.addPhotos)
        #endif
        return .result()
    }
}

/// Opens the app to a new quote. The control's way in; Siri's is `AddQuoteIntent`, which saves without opening anything.
nonisolated struct OpenAddQuoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Quote"
    static let description = IntentDescription("Opens Family Record to write down something someone said.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if FAMILY_RECORD_APP
        DeepLinkRouter.shared.open(.addQuote(personRemoteId: nil))
        #endif
        return .result()
    }
}
