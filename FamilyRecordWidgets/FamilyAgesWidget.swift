import AppIntents
import SwiftUI
import WidgetKit

struct FamilyAgesIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Family Ages"
    static let description = IntentDescription("How old everyone is, and whose birthday is coming up. People, when chosen, decides who is shown; otherwise Person; otherwise the whole family.")

    @Parameter(title: "Person", description: "One person to feature. Ignored when People are chosen.")
    var person: PersonEntity?

    @Parameter(title: "People", description: "Who the widget shows, in family order. Leave empty for the whole family.")
    var people: [PersonEntity]?

    var personIds: [Int] {
        WidgetTimeline.familySelection(people: people?.map(\.id), person: person?.id)
    }
}

struct FamilyAgesEntry: TimelineEntry {
    let date: Date
    /// nil when signed out.
    let ages: FamilyAges?
}

/// One entry a day — ages, birthdays and the spotlight only change at midnight — read from the ages the app worked out ahead.
struct FamilyAgesProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> FamilyAgesEntry {
        FamilyAgesEntry(date: Date(), ages: .placeholder)
    }

    func snapshot(for configuration: FamilyAgesIntent, in context: Context) async -> FamilyAgesEntry {
        let ages = WidgetTimeline.ages(WidgetStore.shared()?.read(), at: Date(), personIds: configuration.personIds)
        return FamilyAgesEntry(date: Date(), ages: ages == nil && context.isPreview ? .placeholder : ages)
    }

    func timeline(for configuration: FamilyAgesIntent, in context: Context) async -> Timeline<FamilyAgesEntry> {
        let snapshot = WidgetStore.shared()?.read()
        let now = Date()
        let tomorrow = WidgetDay.nextMidnight(after: now)
        let entries = [now, tomorrow].map {
            FamilyAgesEntry(date: $0, ages: WidgetTimeline.ages(snapshot, at: $0, personIds: configuration.personIds))
        }
        return Timeline(entries: entries, policy: .after(WidgetDay.nextMidnight(after: tomorrow)))
    }
}

struct FamilyAgesWidget: Widget {
    /// Kept from when the widget was "Family Ages", so installed widgets survive the rename.
    nonisolated static let kind = "FamilyAges"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: FamilyAgesIntent.self, provider: FamilyAgesProvider()) { entry in
            FamilyAgesView(ages: entry.ages)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: AppLinks.site + "/dashboard"))
        }
        .configurationDisplayName(WidgetCopy.agesName)
        .description(WidgetCopy.agesDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

/// The Family widget has no item to name a site by, so it uses the snapshot's, falling back to the production site.
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
                Text(FamilyFocus(ages).inline)
                    .privacySensitive()
            case .accessoryRectangular:
                FamilyAccessoryView(focus: FamilyFocus(ages))
            case .systemMedium:
                FamilyOverviewView(ages: ages, large: false)
            case .systemLarge:
                FamilyOverviewView(ages: ages, large: true)
            default:
                FamilySmallView(focus: FamilyFocus(ages))
            }
        } else if family == .accessoryInline || family == .accessoryRectangular {
            Text(ages == nil ? WidgetCopy.signedOut : ages?.isStale == true ? WidgetCopy.stale : WidgetCopy.noAges)
        } else if ages == nil {
            WidgetMessage(title: WidgetCopy.signedOut, detail: WidgetCopy.signedOutDetail)
        } else if ages?.isStale == true {
            WidgetMessage(title: WidgetCopy.family, detail: WidgetCopy.stale)
        } else {
            WidgetMessage(title: WidgetCopy.noAges, detail: WidgetCopy.noAgesDetail)
        }
    }
}

// MARK: - One person or one birthday

/// What a small or accessory widget is about: the one person chosen, else the soonest birthday, else the day's spotlight. Never a partial roster.
enum FamilyFocus {
    case person(FamilyAges.Row, birthday: FamilyAges.Birthday?)
    case birthdays([FamilyAges.Birthday], later: Int)
    case spotlight(FamilyAges.Row)
    case nothing

    init(_ ages: FamilyAges) {
        if ages.rows.count == 1, let row = ages.rows.first {
            self = .person(row, birthday: ages.birthdays.first)
        } else if !ages.nextBirthdays.isEmpty {
            self = .birthdays(ages.nextBirthdays, later: ages.birthdays.count - ages.nextBirthdays.count)
        } else if let row = ages.spotlight {
            self = .spotlight(row)
        } else {
            self = .nothing
        }
    }

    /// The Lock Screen's one line.
    var inline: String {
        switch self {
        case .person(let row, let birthday):
            birthday?.text ?? "\(row.name) · \(row.age ?? WidgetCopy.noAge)"
        case .birthdays(let birthdays, _):
            birthdays.count == 1 ? birthdays[0].text : WidgetCopy.sharedBirthday(birthdays.map(\.name), inDays: birthdays[0].inDays)
        case .spotlight(let row):
            "\(row.name) · \(row.age ?? "")"
        case .nothing:
            WidgetCopy.noAges
        }
    }
}

extension FamilyAges.Birthday {
    /// "Turns 12", or on the day "12 today!" — nil from a snapshot without the age, which then shows its sentence.
    var turningLine: String? {
        turning.map { inDays == 0 ? WidgetCopy.ageToday($0) : WidgetCopy.turns($0) }
    }
}

struct FamilySmallView: View {
    let focus: FamilyFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch focus {
            case .person(let row, let birthday):
                ContextLabel(text: WidgetCopy.family)
                Spacer(minLength: 0)
                name(row.name)
                Text(row.age ?? WidgetCopy.noAge)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let birthday {
                    Label(birthday.turningLine.map { "\($0) · \(WidgetCopy.countdown(birthday.inDays))" } ?? birthday.text, systemImage: "gift.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                        .lineLimit(2)
                }
            case .birthdays(let birthdays, let later):
                ContextLabel(text: WidgetCopy.birthdayLabel, symbol: "gift.fill")
                Spacer(minLength: 0)
                if birthdays.count == 1 {
                    let birthday = birthdays[0]
                    name(birthday.name)
                    if let turning = birthday.turningLine {
                        Text(turning).font(.title3.weight(.medium)).lineLimit(1)
                        if birthday.inDays > 0 {
                            countdown(birthday.inDays)
                        }
                    } else {
                        Text(birthday.text).font(.callout).lineLimit(3)
                    }
                } else {
                    // Two names fit; a third and beyond are counted rather than dropped.
                    let named = Array(birthdays.prefix(2))
                    Text(WidgetCopy.names(named.map(\.name)))
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    countdown(birthdays[0].inDays)
                    if birthdays.count > 2 {
                        Text(WidgetCopy.moreBirthdays(birthdays.count - 2))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if later > 0 {
                    Text(WidgetCopy.moreBirthdays(later))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .spotlight(let row):
                ContextLabel(text: WidgetCopy.familySpotlight, symbol: "sparkles")
                Spacer(minLength: 0)
                name(row.name)
                Text(row.age ?? "")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            case .nothing:
                WidgetMessage(title: WidgetCopy.noAges, detail: WidgetCopy.noAgesDetail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func name(_ text: String) -> some View {
        Text(text)
            .font(.title2.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func countdown(_ days: Int) -> some View {
        Text(WidgetCopy.countdown(days))
            .font(.headline)
            .foregroundStyle(.tint)
            .widgetAccentable()
    }
}

struct FamilyAccessoryView: View {
    let focus: FamilyFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch focus {
            case .person(let row, let birthday):
                Text(row.name).font(.headline).widgetAccentable()
                Text(row.age ?? WidgetCopy.noAge).font(.caption)
                if let birthday {
                    Label(birthday.turningLine.map { "\($0) · \(WidgetCopy.countdown(birthday.inDays))" } ?? birthday.text, systemImage: "gift.fill")
                        .font(.caption)
                }
            case .birthdays(let birthdays, _):
                Label(WidgetCopy.names(birthdays.map(\.name)), systemImage: "gift.fill")
                    .font(.headline)
                    .widgetAccentable()
                if birthdays.count == 1, let turning = birthdays[0].turningLine {
                    Text(turning).font(.caption)
                } else if birthdays.count == 1 {
                    Text(birthdays[0].text).font(.caption)
                }
                Text(WidgetCopy.countdown(birthdays[0].inDays)).font(.caption)
            case .spotlight(let row):
                Text(WidgetCopy.familySpotlight).font(.caption2).widgetAccentable()
                Text(row.name).font(.headline)
                Text(row.age ?? "").font(.caption)
            case .nothing:
                Text(WidgetCopy.noAges).font(.caption)
            }
        }
        .lineLimit(1)
        .privacySensitive()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The overview

/// Everyone chosen at once: two columns, a cell for anyone who does not fit saying how many, and a birthday area of its own. Larger text shows fewer cells rather than smaller words, and the count says so.
struct FamilyOverviewView: View {
    let ages: FamilyAges
    let large: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Cells, the "+N more" one included.
    private var capacity: Int {
        if typeSize.isAccessibilitySize { return large ? 4 : 2 }
        if typeSize >= .xxLarge { return large ? 6 : 4 }
        return large ? 8 : 6
    }

    var body: some View {
        let (shown, more) = ages.overview(capacity: capacity)
        VStack(alignment: .leading, spacing: large ? 10 : 6) {
            ContextLabel(text: WidgetCopy.family)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: large ? 12 : 6) {
                ForEach(Array(stride(from: 0, to: shown.count + (more > 0 ? 1 : 0), by: 2)), id: \.self) { start in
                    GridRow {
                        cell(at: start, shown: shown, more: more)
                        cell(at: start + 1, shown: shown, more: more)
                    }
                }
            }
            Spacer(minLength: 0)
            birthdays
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func cell(at index: Int, shown: [FamilyAges.Row], more: Int) -> some View {
        if index < shown.count {
            personCell(shown[index])
        } else if index == shown.count, more > 0 {
            moreCell(more)
        } else {
            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
        }
    }

    @ViewBuilder
    private func personCell(_ row: FamilyAges.Row) -> some View {
        if large {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).font(.headline).lineLimit(1)
                Text(row.age ?? WidgetCopy.noAge).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // One line a person, so six fit with the birthday beneath; the age keeps its room and a long name gives way.
            HStack(spacing: 4) {
                Text(row.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 2)
                Text(row.age ?? WidgetCopy.noAge).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moreCell(_ more: Int) -> some View {
        Group {
            if large {
                VStack(alignment: .leading, spacing: 1) {
                    Text(WidgetCopy.morePeople(more)).font(.headline)
                    Text(WidgetCopy.openFamily).font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    Text("\(WidgetCopy.morePeople(more)) · \(WidgetCopy.openFamily)")
                    Text(WidgetCopy.morePeople(more))
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            }
        }
        .foregroundStyle(.tint)
        .widgetAccentable()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Medium: the soonest birthday day in one line. Large: up to three, each its own line, and a count of the rest.
    @ViewBuilder
    private var birthdays: some View {
        if large {
            if !ages.birthdays.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(ages.birthdays.prefix(3).enumerated()), id: \.offset) { _, birthday in
                        Label(birthday.text, systemImage: "gift.fill")
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                    }
                    if ages.birthdays.count > 3 {
                        Text(WidgetCopy.moreBirthdays(ages.birthdays.count - 3))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.tint)
                .widgetAccentable()
            }
        } else if !ages.nextBirthdays.isEmpty {
            let next = ages.nextBirthdays
            let others = ages.birthdays.count - next.count
            Label {
                Text(next.count == 1 ? next[0].text : WidgetCopy.sharedBirthday(next.map(\.name), inDays: next[0].inDays))
                    + Text(others > 0 ? "  \(WidgetCopy.moreBirthdays(others))" : "").foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "gift.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .widgetAccentable()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
    }
}

extension FamilyAges {
    /// Six synthetic people, for the gallery before anyone signs in.
    static let placeholder: FamilyAges = {
        let people = [("Ruth", "38y"), ("Steven", "40y"), ("Clara", "5y 4m"), ("Mia", "3y 1m"), ("Theo", "11m"), ("Baby", "Due in 7w")]
        let rows = people.enumerated().map { FamilyAges.Row(id: "placeholder:\($0.offset)", personId: $0.offset + 1, name: $0.element.0, age: $0.element.1) }
        return FamilyAges(
            rows: rows,
            birthdays: [Birthday(personId: 5, name: "Theo", turning: 1, inDays: 5, text: "Theo turns 1 in 5 days")],
            isStale: false,
            spotlight: rows[2]
        )
    }()
}

#Preview("Medium", as: .systemMedium) {
    FamilyAgesWidget()
} timeline: {
    FamilyAgesEntry(date: .now, ages: .placeholder)
}

#Preview("Small", as: .systemSmall) {
    FamilyAgesWidget()
} timeline: {
    FamilyAgesEntry(date: .now, ages: .placeholder)
}
