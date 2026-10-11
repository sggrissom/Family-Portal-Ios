import AppIntents
import WidgetKit

/// A person a widget can be limited to. The choices come from the snapshot's people — the ones with a server id, by first name — so configuring a widget needs no network either.
struct PersonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static let defaultQuery = PersonQuery()

    var id: Int
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PersonQuery: EntityQuery {
    private var people: [PersonEntity] {
        (WidgetStore.shared()?.read()?.people ?? []).map { PersonEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [Int]) async throws -> [PersonEntity] {
        people.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PersonEntity] {
        people
    }
}

enum MemoryContentOption: String, AppEnum {
    case everything, photos, milestones, quotes

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Content"
    static let caseDisplayRepresentations: [MemoryContentOption: DisplayRepresentation] = [
        .everything: "Everything",
        .photos: "Photos",
        .milestones: "Milestones",
        .quotes: "Quotes",
    ]

    var content: MemoryFilter.Content {
        MemoryFilter.Content(rawValue: rawValue) ?? .everything
    }
}

enum RotationOption: String, AppEnum {
    case hourly, sixHours, daily

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Change"
    static let caseDisplayRepresentations: [RotationOption: DisplayRepresentation] = [
        .hourly: "Every hour",
        .sixHours: "Every 6 hours",
        .daily: "Every day",
    ]

    var hours: Int {
        switch self {
        case .hourly: 1
        case .sixHours: 6
        case .daily: 24
        }
    }
}

struct MemoryWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Memory"
    static let description = IntentDescription("A photo, milestone or quote from your family's record.")

    @Parameter(title: "Show", default: .everything)
    var content: MemoryContentOption

    @Parameter(title: "Person")
    var person: PersonEntity?

    @Parameter(title: "Change", default: .sixHours)
    var rotation: RotationOption

    var filter: MemoryFilter {
        MemoryFilter(content: content.content, personId: person?.id)
    }
}

struct OnThisDayIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "On This Day"
    static let description = IntentDescription("A photo or milestone from this day in an earlier year.")

    @Parameter(title: "Person")
    var person: PersonEntity?
}

/// The Memory widget's Shuffle button. Runs in the extension: it moves the shared offset on and reloads the Memory widgets, nothing more.
struct ShuffleMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Shuffle Memory"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        WidgetShuffle.advance()
        WidgetCenter.shared.reloadTimelines(ofKind: MemoryWidget.kind)
        return .result()
    }
}
