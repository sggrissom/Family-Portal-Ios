import SwiftUI
import WidgetKit

struct OnThisDayEntry: TimelineEntry {
    let date: Date
    let moment: WidgetMoment
}

/// Every entry comes from the snapshot on disk; nothing here can reach the network.
struct OnThisDayProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> OnThisDayEntry {
        OnThisDayEntry(date: Date(), moment: .placeholder)
    }

    /// The gallery preview shows the family when there is one to show, not a stock picture.
    func snapshot(for configuration: OnThisDayIntent, in context: Context) async -> OnThisDayEntry {
        let now = Date()
        let moment = WidgetTimeline.onThisDay(WidgetStore.shared()?.read(), at: now, personId: configuration.person?.id)
        return OnThisDayEntry(date: now, moment: moment.source == .signedOut && context.isPreview ? .placeholder : moment)
    }

    /// Two days of entries at every slot boundary, then a reload — which reads the file again and costs nothing on the network.
    func timeline(for configuration: OnThisDayIntent, in context: Context) async -> Timeline<OnThisDayEntry> {
        let snapshot = WidgetStore.shared()?.read()
        let dates = WidgetTimeline.entryDates(from: Date())
        let entries = dates.map {
            OnThisDayEntry(date: $0, moment: WidgetTimeline.onThisDay(snapshot, at: $0, personId: configuration.person?.id))
        }
        let reload = dates.last.map { WidgetDay.nextMidnight(after: $0) } ?? Date().addingTimeInterval(86_400)
        return Timeline(entries: entries, policy: .after(reload))
    }
}

struct OnThisDayWidget: Widget {
    nonisolated static let kind = "OnThisDay"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: OnThisDayIntent.self, provider: OnThisDayProvider()) { entry in
            OnThisDayView(moment: entry.moment)
        }
        .configurationDisplayName(WidgetCopy.onThisDayName)
        .description(WidgetCopy.onThisDayDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct OnThisDayView: View {
    let moment: WidgetMoment
    /// What an empty widget says; Memory has its own words for a filter that matches nothing.
    var nothing: (title: String, detail: String) = (WidgetCopy.nothing, WidgetCopy.nothingDetail)
    /// The Memory widget's Shuffle button, on the sizes with room for it.
    var shuffles = false
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .widgetURL(moment.url(for: moment.featured))
            .containerBackground(for: .widget) { background }
    }

    /// A small widget's photo is its background, so StandBy and CarPlay can take it away and leave the words. Only in full color: tinted, a photo behind words is neither.
    @ViewBuilder
    private var background: some View {
        if family == .systemSmall, renderingMode == .fullColor, let featured = moment.featured, featured.hasImage {
            FilledImage(file: featured.imageFile)
        } else {
            Rectangle().fill(.fill.tertiary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch moment.source {
        case .signedOut:
            message(WidgetCopy.signedOut, WidgetCopy.signedOutDetail)
        case .nothing:
            message(nothing.title, nothing.detail)
        case .onThisDay, .memory:
            if let featured = moment.featured {
                switch family {
                case .accessoryRectangular:
                    AccessoryMomentView(moment: moment, item: featured)
                case .systemMedium:
                    withFootnote { MediumMomentView(moment: moment, item: featured, shuffles: shuffles) }
                case .systemLarge:
                    withFootnote { LargeMomentView(moment: moment, item: featured, shuffles: shuffles) }
                default:
                    SmallMomentView(moment: moment, item: featured)
                }
            }
        }
    }

    /// The sizes with room to say the snapshot has run out.
    private func withFootnote(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content().frame(maxHeight: .infinity)
            StaleFootnote(moment: moment)
        }
    }

    @ViewBuilder
    private func message(_ title: String, _ detail: String) -> some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Text(WidgetCopy.onThisDay).font(.headline)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            WidgetMessage(title: title, detail: detail)
        }
    }
}

// MARK: - Sizes

/// The words every size puts around an item.
enum MomentText {
    /// The headline over an item: "3 years ago", or "A memory · 2021".
    static func headline(_ moment: WidgetMoment, _ item: WidgetItem) -> String {
        moment.source == .memory ? "\(WidgetCopy.memory) · \(WidgetCopy.when(item))" : WidgetCopy.when(item)
    }

    /// "Clara · First steps" for a milestone, "Clara & Mia" for a photo with no title.
    static func caption(_ moment: WidgetMoment, _ item: WidgetItem) -> String {
        let names = WidgetCopy.names(moment.names(for: item))
        return [names, item.title].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct SmallMomentView: View {
    let moment: WidgetMoment
    let item: WidgetItem
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        if !item.hasImage {
            TextMomentView(moment: moment, item: item, lines: 4)
        } else if renderingMode == .vibrant {
            // StandBy at night draws in one tone: words read, a photo does not — so the day's words lead when it has any.
            TextMomentView(moment: moment, item: moment.items.first { !$0.title.isEmpty } ?? item, lines: 4)
        } else if renderingMode == .accented {
            AccentedSmallView(moment: moment, item: item)
        } else if showsBackground {
            // The photo is the container background; the words sit on it.
            overlay
        } else {
            // StandBy and CarPlay removed the background, so the photo moves into the content.
            ZStack(alignment: .bottomLeading) {
                FilledImage(file: item.imageFile)
                    .clipShape(.rect(cornerRadius: 14))
                overlay.padding(8)
            }
        }
    }

    private var overlay: some View {
        VStack(alignment: .leading, spacing: 1) {
            Spacer(minLength: 0)
            Text(MomentText.headline(moment, item))
                .font(.caption.weight(.semibold))
            let names = WidgetCopy.names(moment.names(for: item))
            if !names.isEmpty {
                Text(names).font(.caption2)
            }
        }
        .lineLimit(1)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.7), radius: 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Tinted, on glass — CarPlay and a tinted Home Screen. Words lead, and the photo is a desaturated strip beneath them rather than a tinted silhouette.
struct AccentedSmallView: View {
    let moment: WidgetMoment
    let item: WidgetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MomentText.headline(moment, item))
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(WidgetCopy.names(moment.names(for: item)))
                .font(.caption)
                .lineLimit(1)
            FilledImage(file: item.imageFile)
                .clipShape(.rect(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// An item with only words: the headline, then what happened, then who.
struct TextMomentView: View {
    let moment: WidgetMoment
    let item: WidgetItem
    var lines = 4

    /// A photo with no title says who is in it instead.
    private var words: String {
        item.title.isEmpty ? WidgetCopy.names(moment.names(for: item)) : item.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(MomentText.headline(moment, item), systemImage: item.kind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .widgetAccentable()
            Text(words)
                .font(item.kind == .quote ? .callout.italic() : .callout)
                .lineLimit(lines)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if !item.title.isEmpty {
                Text(WidgetCopy.names(moment.names(for: item)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Shown once the app has not run for longer than the snapshot looks ahead.
struct StaleFootnote: View {
    let moment: WidgetMoment

    var body: some View {
        if moment.isStale {
            Label(WidgetCopy.stale, systemImage: "arrow.clockwise")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct MediumMomentView: View {
    let moment: WidgetMoment
    let item: WidgetItem
    var shuffles = false

    /// A milestone from the same day reads beside the picture; failing that, the picture's own caption.
    private var words: WidgetItem? {
        moment.items.first { !$0.hasImage && !$0.title.isEmpty } ?? (item.title.isEmpty ? nil : item)
    }

    var body: some View {
        Group {
        if item.hasImage {
            HStack(spacing: 12) {
                FilledImage(file: item.imageFile)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(MomentText.headline(moment, item))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    if let words {
                        Text(words.title)
                            .font(words.kind == .quote ? .callout.italic() : .callout)
                            .lineLimit(3)
                        Spacer(minLength: 0)
                        Text(WidgetCopy.names(moment.names(for: words)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Spacer(minLength: 0)
                        Text(WidgetCopy.names(moment.names(for: item)))
                            .font(.callout)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            TextMomentView(moment: moment, item: item, lines: 3)
        }
        }
        .overlay(alignment: .bottomTrailing) {
            if shuffles { ShuffleButton() }
        }
    }
}

struct LargeMomentView: View {
    let moment: WidgetMoment
    let item: WidgetItem
    var shuffles = false

    private var pictures: [WidgetItem] {
        Array(moment.featuredYear.filter(\.hasImage).prefix(4))
    }

    /// The words of that year, and failing those the day's others. A memory is one item, captioned by itself.
    private var captions: [WidgetItem] {
        if moment.source == .memory {
            return MomentText.caption(moment, item).isEmpty ? [] : [item]
        }
        let year = moment.featuredYear.filter { !$0.hasImage && !$0.title.isEmpty }
        let rest = moment.items.filter { !$0.hasImage && !$0.title.isEmpty && !year.contains($0) }
        return Array((year + rest).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(moment.source == .memory ? WidgetCopy.memory : WidgetCopy.onThisDay)
                    .font(.headline)
                Spacer()
                Text(WidgetCopy.when(item))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            if !pictures.isEmpty {
                mosaic
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(captions) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: line.kind.symbol)
                                .foregroundStyle(.tint)
                            Text(MomentText.caption(moment, line))
                                .lineLimit(2)
                        }
                        .font(.footnote)
                    }
                }
                if shuffles {
                    Spacer(minLength: 0)
                    ShuffleButton()
                }
            }
            if pictures.isEmpty && captions.isEmpty {
                TextMomentView(moment: moment, item: item, lines: 8)
            }
            Spacer(minLength: 0)
        }
    }

    /// One picture fills; two sit side by side; three put the first across the top; four make a square.
    @ViewBuilder
    private var mosaic: some View {
        let files = pictures.map(\.imageFile)
        Group {
            switch files.count {
            case 1:
                FilledImage(file: files[0])
            case 2:
                HStack(spacing: 4) { FilledImage(file: files[0]); FilledImage(file: files[1]) }
            case 3:
                VStack(spacing: 4) {
                    FilledImage(file: files[0])
                    HStack(spacing: 4) { FilledImage(file: files[1]); FilledImage(file: files[2]) }
                }
            default:
                VStack(spacing: 4) {
                    HStack(spacing: 4) { FilledImage(file: files[0]); FilledImage(file: files[1]) }
                    HStack(spacing: 4) { FilledImage(file: files[2]); FilledImage(file: files[3]) }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .frame(maxHeight: .infinity)
    }
}

/// The Lock Screen's version: words only, and redacted while the phone is locked.
struct AccessoryMomentView: View {
    let moment: WidgetMoment
    let item: WidgetItem

    private var words: WidgetItem {
        moment.items.first { !$0.title.isEmpty && $0.kind != .photo } ?? item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(MomentText.headline(moment, words))
                .font(.headline)
                .widgetAccentable()
            Text(words.title.isEmpty ? WidgetCopy.names(moment.names(for: words)) : MomentText.caption(moment, words))
                .font(.caption)
                .lineLimit(2)
                .privacySensitive()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension WidgetMoment {
    /// Fixed words and no photos: what the gallery and a redacted widget draw before anything is known.
    static let placeholder = WidgetMoment(
        source: .onThisDay,
        items: [
            WidgetItem(id: "placeholder", kind: .milestone, date: "2023-01-01", yearsAgo: 3, title: "First steps", personIds: [1], imageFile: nil, link: "/dashboard"),
        ],
        names: [1: "Clara"]
    )
}

#Preview(as: .systemMedium) {
    OnThisDayWidget()
} timeline: {
    OnThisDayEntry(date: .now, moment: .placeholder)
    OnThisDayEntry(date: .now, moment: .signedOut)
}
