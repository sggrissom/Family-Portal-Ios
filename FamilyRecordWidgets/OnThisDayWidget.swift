import SwiftUI
import WidgetKit

struct OnThisDayEntry: TimelineEntry {
    let date: Date
    let moment: WidgetMoment
}

/// Every entry comes from the snapshot on disk; nothing here can reach the network.
struct OnThisDayProvider: TimelineProvider {

    func placeholder(in context: Context) -> OnThisDayEntry {
        OnThisDayEntry(date: Date(), moment: .placeholder)
    }

    /// The gallery preview shows the family when there is one to show, not a stock picture.
    func getSnapshot(in context: Context, completion: @escaping (OnThisDayEntry) -> Void) {
        let now = Date()
        let moment = WidgetTimeline.onThisDay(WidgetStore.shared()?.read(), at: now)
        completion(OnThisDayEntry(date: now, moment: moment.source == .signedOut && context.isPreview ? .placeholder : moment))
    }

    /// Two days of entries at every slot boundary, then a reload — which reads the file again and costs nothing on the network.
    func getTimeline(in context: Context, completion: @escaping (Timeline<OnThisDayEntry>) -> Void) {
        let snapshot = WidgetStore.shared()?.read()
        let dates = WidgetTimeline.entryDates(from: Date())
        let entries = dates.map { OnThisDayEntry(date: $0, moment: WidgetTimeline.onThisDay(snapshot, at: $0)) }
        let reload = dates.last.map { WidgetDay.nextMidnight(after: $0) } ?? Date().addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(reload)))
    }
}

struct OnThisDayWidget: Widget {
    static let kind = "OnThisDay"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: OnThisDayProvider()) { entry in
            OnThisDayView(moment: entry.moment)
        }
        .configurationDisplayName(WidgetCopy.onThisDayName)
        .description(WidgetCopy.onThisDayDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct OnThisDayView: View {
    let moment: WidgetMoment
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(moment.url(for: moment.featured))
            .containerBackground(for: .widget) { background }
    }

    /// A small widget's photo is its background, so StandBy and CarPlay can take it away and leave the words.
    @ViewBuilder
    private var background: some View {
        if family == .systemSmall, let featured = moment.featured, featured.hasImage {
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
            message(WidgetCopy.nothing, WidgetCopy.nothingDetail)
        case .onThisDay, .memory:
            if let featured = moment.featured {
                switch family {
                case .accessoryRectangular:
                    AccessoryMomentView(moment: moment, item: featured)
                case .systemMedium:
                    MediumMomentView(moment: moment, item: featured)
                case .systemLarge:
                    LargeMomentView(moment: moment, item: featured)
                default:
                    SmallMomentView(moment: moment, item: featured)
                }
            }
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

/// The headline over an item: "3 years ago", or "A memory · 2021".
private func headline(_ moment: WidgetMoment, _ item: WidgetItem) -> String {
    moment.source == .memory ? "\(WidgetCopy.memory) · \(WidgetCopy.when(item))" : WidgetCopy.when(item)
}

/// "Clara · First steps" for a milestone, "Clara & Mia" for a photo with no title.
private func caption(_ moment: WidgetMoment, _ item: WidgetItem) -> String {
    let names = WidgetCopy.names(moment.names(for: item))
    return [names, item.title].filter { !$0.isEmpty }.joined(separator: " · ")
}

struct SmallMomentView: View {
    let moment: WidgetMoment
    let item: WidgetItem

    var body: some View {
        if item.hasImage {
            VStack(alignment: .leading, spacing: 1) {
                Spacer(minLength: 0)
                Text(headline(moment, item))
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
        } else {
            TextMomentView(moment: moment, item: item, lines: 4)
        }
    }
}

/// An item with only words: the headline, then what happened, then who.
struct TextMomentView: View {
    let moment: WidgetMoment
    let item: WidgetItem
    var lines = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(headline(moment, item), systemImage: item.kind.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(item.title)
                .font(item.kind == .quote ? .callout.italic() : .callout)
                .lineLimit(lines)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(WidgetCopy.names(moment.names(for: item)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MediumMomentView: View {
    let moment: WidgetMoment
    let item: WidgetItem

    /// A milestone from the same day reads beside the picture; failing that, the picture's own caption.
    private var words: WidgetItem? {
        moment.items.first { !$0.hasImage && !$0.title.isEmpty } ?? (item.title.isEmpty ? nil : item)
    }

    var body: some View {
        if item.hasImage {
            HStack(spacing: 12) {
                FilledImage(file: item.imageFile)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(moment, item))
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
}

struct LargeMomentView: View {
    let moment: WidgetMoment
    let item: WidgetItem

    private var pictures: [WidgetItem] {
        Array(moment.featuredYear.filter(\.hasImage).prefix(4))
    }

    /// The words of that year, and failing those the day's others.
    private var captions: [WidgetItem] {
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
            ForEach(captions) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: line.kind.symbol)
                        .foregroundStyle(.tint)
                    Text(caption(moment, line))
                        .lineLimit(2)
                }
                .font(.footnote)
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
            Text(headline(moment, words))
                .font(.headline)
                .widgetAccentable()
            Text(words.title.isEmpty ? WidgetCopy.names(moment.names(for: words)) : caption(moment, words))
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
