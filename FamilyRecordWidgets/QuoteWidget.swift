import AppIntents
import SwiftUI
import WidgetKit

struct QuoteWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Quote"
    static let description = IntentDescription("Something your family said.")

    @Parameter(title: "Person")
    var person: PersonEntity?
}

/// Words only, so it reads the same in StandBy, CarPlay and on the Lock Screen — the car-friendly choice when photos of the children are not wanted on a dashboard.
struct QuoteProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> MemoryEntry {
        MemoryEntry(date: Date(), moment: .memoryPlaceholder)
    }

    func snapshot(for configuration: QuoteWidgetIntent, in context: Context) async -> MemoryEntry {
        let now = Date()
        let moment = WidgetTimeline.quote(WidgetStore.shared()?.read(), at: now, personId: configuration.person?.id)
        return MemoryEntry(date: now, moment: moment.source == .signedOut && context.isPreview ? .memoryPlaceholder : moment)
    }

    func timeline(for configuration: QuoteWidgetIntent, in context: Context) async -> Timeline<MemoryEntry> {
        let snapshot = WidgetStore.shared()?.read()
        let entries = WidgetTimeline.entryDates(from: Date(), hours: 24).map {
            MemoryEntry(date: $0, moment: WidgetTimeline.quote(snapshot, at: $0, personId: configuration.person?.id))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct QuoteWidget: Widget {
    nonisolated static let kind = "Quote"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: QuoteWidgetIntent.self, provider: QuoteProvider()) { entry in
            QuoteView(moment: entry.moment)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(WidgetCopy.quoteName)
        .description(WidgetCopy.quoteDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct QuoteView: View {
    let moment: WidgetMoment
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch moment.source {
            case .signedOut:
                message(WidgetCopy.signedOut, WidgetCopy.signedOutDetail)
            case .nothing:
                message(WidgetCopy.noQuotes, WidgetCopy.noQuotesDetail)
            case .onThisDay, .memory:
                if let quote = moment.featured {
                    content(quote)
                }
            }
        }
        .widgetURL(moment.url(for: moment.featured))
    }

    @ViewBuilder
    private func content(_ quote: WidgetItem) -> some View {
        let who = [WidgetCopy.names(moment.names(for: quote)), String(quote.date.prefix(4))]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.title)
                    .font(.headline)
                    .italic()
                    .lineLimit(2)
                    .privacySensitive()
                Text(who)
                    .font(.caption)
                    .privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // The quote is the focus; who said it, and when, sit quietly beneath. Stored quotes carry their own marks, so the glyph is only for one that does not.
            VStack(alignment: .leading, spacing: 6) {
                if !WidgetCopy.isQuoted(quote.title) {
                    Image(systemName: "quote.opening")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                }
                FeatureText(text: quote.title, kind: .quote, room: family == .systemSmall ? .small : .medium)
                Spacer(minLength: 0)
                Text(who)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func message(_ title: String, _ detail: String) -> some View {
        if family == .accessoryRectangular {
            Text(title).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            WidgetMessage(title: title, detail: detail)
        }
    }
}
