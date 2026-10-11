import AppIntents
import SwiftUI
import WidgetKit

struct MemoryEntry: TimelineEntry {
    let date: Date
    let moment: WidgetMoment
}

/// A memory from the pool, turned over at the configured interval. The order is fixed by the snapshot, so a reload lands on the same memory; only Shuffle moves it on early.
struct MemoryProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> MemoryEntry {
        MemoryEntry(date: Date(), moment: .memoryPlaceholder)
    }

    func snapshot(for configuration: MemoryWidgetIntent, in context: Context) async -> MemoryEntry {
        let now = Date()
        let moment = moment(configuration, at: now, snapshot: WidgetStore.shared()?.read())
        return MemoryEntry(date: now, moment: moment.source == .signedOut && context.isPreview ? .memoryPlaceholder : moment)
    }

    /// A day of entries, one per interval, then a reload.
    func timeline(for configuration: MemoryWidgetIntent, in context: Context) async -> Timeline<MemoryEntry> {
        let snapshot = WidgetStore.shared()?.read()
        let dates = WidgetTimeline.entryDates(from: Date(), hours: 24, slotHours: configuration.rotation.hours)
        let entries = dates.map { MemoryEntry(date: $0, moment: moment(configuration, at: $0, snapshot: snapshot)) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func moment(_ configuration: MemoryWidgetIntent, at date: Date, snapshot: WidgetSnapshot?) -> WidgetMoment {
        WidgetTimeline.memory(
            snapshot,
            at: date,
            filter: configuration.filter,
            rotationHours: configuration.rotation.hours,
            shuffle: WidgetShuffle.offset()
        )
    }
}

struct MemoryWidget: Widget {
    nonisolated static let kind = "Memory"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: MemoryWidgetIntent.self, provider: MemoryProvider()) { entry in
            MemoryView(moment: entry.moment)
        }
        .configurationDisplayName(WidgetCopy.memoryName)
        .description(WidgetCopy.memoryDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// The same faces as On This Day, plus Shuffle where there is room for it.
struct MemoryView: View {
    let moment: WidgetMoment

    var body: some View {
        OnThisDayView(moment: moment, nothing: (WidgetCopy.nothingMatches, WidgetCopy.nothingMatchesDetail), shuffles: true)
    }
}

/// Moves the Memory widgets on by one without opening the app.
struct ShuffleButton: View {
    var body: some View {
        Button(intent: ShuffleMemoryIntent()) {
            Image(systemName: "shuffle")
                .font(.footnote.weight(.semibold))
                .padding(4)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel(WidgetCopy.shuffle)
    }
}

extension WidgetMoment {
    static let memoryPlaceholder = WidgetMoment(
        source: .memory,
        items: [
            WidgetItem(id: "placeholder", kind: .quote, date: "2022-05-01", yearsAgo: nil, title: "“Bye bye moon”", personIds: [1], imageFile: nil, link: "/dashboard"),
        ],
        names: [1: "Clara"]
    )
}
