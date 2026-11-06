import AppIntents
import WidgetKit

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
