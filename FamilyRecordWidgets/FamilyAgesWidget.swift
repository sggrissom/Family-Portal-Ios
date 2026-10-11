import AppIntents
import SwiftUI
import WidgetKit

struct FamilyAgesIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Family Ages"
    static let description = IntentDescription("How old everyone is, and whose birthday is coming up.")

    @Parameter(title: "Person")
    var person: PersonEntity?
}

struct FamilyAgesEntry: TimelineEntry {
    let date: Date
    /// nil when signed out.
    let ages: FamilyAges?
}

/// One entry a day — ages only change at midnight — read from the ages the app worked out ahead.
struct FamilyAgesProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> FamilyAgesEntry {
        FamilyAgesEntry(date: Date(), ages: .placeholder)
    }

    func snapshot(for configuration: FamilyAgesIntent, in context: Context) async -> FamilyAgesEntry {
        let ages = WidgetTimeline.ages(WidgetStore.shared()?.read(), at: Date(), personId: configuration.person?.id)
        return FamilyAgesEntry(date: Date(), ages: ages == nil && context.isPreview ? .placeholder : ages)
    }

    func timeline(for configuration: FamilyAgesIntent, in context: Context) async -> Timeline<FamilyAgesEntry> {
        let snapshot = WidgetStore.shared()?.read()
        let now = Date()
        let tomorrow = WidgetDay.nextMidnight(after: now)
        let entries = [now, tomorrow].map {
            FamilyAgesEntry(date: $0, ages: WidgetTimeline.ages(snapshot, at: $0, personId: configuration.person?.id))
        }
        return Timeline(entries: entries, policy: .after(WidgetDay.nextMidnight(after: tomorrow)))
    }
}

struct FamilyAgesWidget: Widget {
    nonisolated static let kind = "FamilyAges"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: FamilyAgesIntent.self, provider: FamilyAgesProvider()) { entry in
            FamilyAgesView(ages: entry.ages)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: AppLinks.site + "/dashboard"))
        }
        .configurationDisplayName(WidgetCopy.agesName)
        .description(WidgetCopy.agesDescription)
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

/// The Family ages widget has no item to name a site by, so it uses the snapshot's, falling back to the production site.
enum AppLinks {
    static var site: String {
        WidgetStore.shared()?.read()?.siteURL ?? "https://familyrecord.app"
    }
}

struct FamilyAgesView: View {
    let ages: FamilyAges?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let ages, !ages.rows.isEmpty {
            switch family {
            case .accessoryInline:
                Text(ages.birthdays.first ?? ages.rows.first.map { "\($0.name) · \($0.age)" } ?? "")
                    .privacySensitive()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 0) {
                    if let birthday = ages.birthdays.first {
                        Label(birthday, systemImage: "gift.fill")
                            .font(.headline)
                            .widgetAccentable()
                            .lineLimit(1)
                    }
                    ForEach(ages.rows.prefix(ages.birthdays.isEmpty ? 3 : 2), id: \.self) { row in
                        row.line.font(.caption)
                    }
                }
                .privacySensitive()
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text(WidgetCopy.family)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                    ForEach(ages.rows.prefix(ages.birthdays.isEmpty ? 5 : 4), id: \.self) { row in
                        row.line.font(.subheadline)
                    }
                    Spacer(minLength: 0)
                    if let birthday = ages.birthdays.first {
                        Label(birthday, systemImage: "gift.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tint)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else if family == .accessoryInline || family == .accessoryRectangular {
            Text(ages == nil ? WidgetCopy.signedOut : WidgetCopy.noAges)
        } else if ages == nil {
            WidgetMessage(title: WidgetCopy.signedOut, detail: WidgetCopy.signedOutDetail)
        } else if ages?.isStale == true {
            WidgetMessage(title: WidgetCopy.family, detail: WidgetCopy.stale)
        } else {
            WidgetMessage(title: WidgetCopy.noAges, detail: WidgetCopy.noAgesDetail)
        }
    }
}

private extension FamilyAges.Row {
    var line: some View {
        HStack(spacing: 4) {
            Text(name).fontWeight(.semibold)
            Spacer(minLength: 4)
            Text(age).foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

extension FamilyAges {
    static let placeholder = FamilyAges(
        rows: [Row(name: "Clara", age: "3y 4m"), Row(name: "Theo", age: "8m")],
        birthdays: ["Theo turns 1 in 5 days"],
        isStale: false
    )
}
