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
        let check = SnapshotImageCheck()
        let dates = WidgetTimeline.entryDates(from: Date(), hours: 24, slotHours: configuration.rotation.hours)
        let entries = dates.map { MemoryEntry(date: $0, moment: moment(configuration, at: $0, snapshot: snapshot, check: check)) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func moment(_ configuration: MemoryWidgetIntent, at date: Date, snapshot: WidgetSnapshot?, check: SnapshotImageCheck = SnapshotImageCheck()) -> WidgetMoment {
        WidgetTimeline.memory(
            snapshot,
            at: date,
            filter: configuration.filter,
            rotationHours: configuration.rotation.hours,
            shuffle: WidgetShuffle.offset(),
            imageAvailable: check.isAvailable
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

/// One memory per entry, composed by what it has, plus Shuffle where there is room for it.
struct MemoryView: View {
    let moment: WidgetMoment

    var body: some View {
        MomentView(moment: moment, style: .memory, nothing: (WidgetCopy.nothingMatches, WidgetCopy.nothingMatchesDetail))
    }
}

/// One record on a medium or large card. A picture — a photo, or the photo a milestone carries — leads with the record's own words beside or beneath it; a record that is only words makes those words the focus of the card, never a footnote over empty space.
struct SingleMemoryView: View {
    let moment: WidgetMoment
    let item: WidgetItem
    let room: FeatureText.Room
    var shuffles = false

    var body: some View {
        if item.hasImage {
            if room == .large { pictureLarge } else { pictureMedium }
        } else {
            worded
        }
    }

    private var dating: WidgetDating { moment.dating(item) }
    private var names: String { WidgetCopy.names(moment.names(for: item)) }

    private var picture: some View {
        FilledImage(file: item.imageFile, contentMode: item.imageContentMode)
            .background(.fill.quaternary)
            .clipShape(.rect(cornerRadius: room == .large ? 14 : 12))
    }

    private var pictureLarge: some View {
        VStack(alignment: .leading, spacing: 8) {
            picture.frame(maxHeight: .infinity)
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    ContextLabel(text: "\(dating.label) · \(dating.when)")
                    if !names.isEmpty {
                        Text(names).font(.headline).lineLimit(1)
                    }
                    if !item.title.isEmpty {
                        Text(item.title)
                            .font(.subheadline)
                            .italic(item.kind == .quote)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if shuffles { ShuffleButton() }
            }
        }
    }

    private var pictureMedium: some View {
        HStack(spacing: 12) {
            picture.aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 3) {
                ContextLabel(text: dating.label)
                if !names.isEmpty {
                    Text(names).font(.headline).lineLimit(1)
                }
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.callout)
                        .italic(item.kind == .quote)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                MomentFooter(text: dating.when, shuffles: shuffles)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The words in the body of the card, who said or did it beneath, and a quiet footer for the date and Shuffle.
    private var worded: some View {
        VStack(alignment: .leading, spacing: room == .large ? 8 : 4) {
            ContextLabel(text: dating.label, symbol: item.kind.symbol)
            Spacer(minLength: 0)
            FeatureText(text: MomentText.words(moment, item), kind: item.kind, room: room)
            if !item.title.isEmpty, !names.isEmpty {
                Text(names)
                    .font(room == .large ? .title3 : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            MomentFooter(text: dating.when, shuffles: shuffles)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

extension WidgetMoment {
    static let memoryPlaceholder = WidgetMoment(
        source: .memory,
        items: [
            WidgetItem(id: "placeholder", kind: .quote, date: "2022-05-01", yearsAgo: nil, title: "“Bye bye moon”", personIds: [1], imageFile: nil, link: "/dashboard"),
        ],
        names: [1: "Clara"],
        day: "2026-10-11",
        poolSize: 2
    )

    /// A short milestone with no picture: the case a large card used to strand at the top.
    static let memoryShortMilestone = WidgetMoment(
        source: .memory,
        items: [
            WidgetItem(id: "placeholder", kind: .milestone, date: "2024-03-02", yearsAgo: nil, title: "Rode a bike", personIds: [2], imageFile: nil, link: "/dashboard"),
        ],
        names: [2: "Theo"],
        day: "2026-10-11",
        poolSize: 2
    )

    static let memoryLongMilestone = WidgetMoment(
        source: .memory,
        items: [
            WidgetItem(
                id: "placeholder", kind: .milestone, date: "2023-08-19", yearsAgo: nil,
                title: "Swam the whole width of the pool without the float, then asked to do it again and again until the lifeguard called time",
                personIds: [1], imageFile: nil, link: "/dashboard"
            ),
        ],
        names: [1: "Clara"],
        day: "2026-10-11",
        poolSize: 1
    )
}

#Preview("Medium", as: .systemMedium) {
    MemoryWidget()
} timeline: {
    MemoryEntry(date: .now, moment: .memoryPlaceholder)
    MemoryEntry(date: .now, moment: .memoryShortMilestone)
    MemoryEntry(date: .now, moment: .memoryLongMilestone)
}

#Preview("Large", as: .systemLarge) {
    MemoryWidget()
} timeline: {
    MemoryEntry(date: .now, moment: .memoryShortMilestone)
    MemoryEntry(date: .now, moment: .memoryPlaceholder)
    MemoryEntry(date: .now, moment: .memoryLongMilestone)
}
