import SwiftUI

// Shared pieces of the activities screens: the two states every read can land
// in, the date and result formatting the server deliberately leaves to the
// client, and the rows that render a performance wherever it appears.

// MARK: - The screen container

/// The frame every activities screen sits in.
///
/// All five of them run the same sequence — cached payload if there is one, live
/// call, replace — and all five have to keep "we could not reach the server and
/// have nothing saved" apart from "there is nothing here". Written once so they
/// cannot drift.
struct ActivityScreen<Value: Sendable, Content: View>: View {
    let state: ActivityScreenState<Value>
    /// Built at the call site because it needs the service, which the screen
    /// reads from the environment.
    let read: @MainActor () -> ActivityRead<Value>
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        Group {
            if let value = state.value {
                ScrollView {
                    content(value)
                        .padding(.vertical, 8)
                }
                .refreshable { await state.reload() }
            } else if let error = state.error {
                ActivityUnavailableView(message: error) { await state.load(read()) }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Only once the refresh has actually failed. While the live call is
            // still in flight the cached payload is simply what is on screen,
            // and announcing it as stale would flash on every open.
            if state.isShowingCached, !state.isLoading, state.value != nil {
                ActivityStaleNote(fetchedAt: state.fetchedAt)
            }
        }
        .task { await state.load(read()) }
    }
}

// MARK: - Load states

/// What a screen shows when the live call failed and there was nothing cached.
///
/// Deliberately not the empty state. Offline-with-nothing-saved and
/// this-season-has-nothing-in-it look identical if you let them, and the reader
/// draws the wrong conclusion from the wrong one.
struct ActivityUnavailableView: View {
    let message: String
    let retry: @MainActor () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Nothing Saved Yet", systemImage: "wifi.slash")
        } description: {
            Text("This screen hasn't been opened on this device, so there's nothing to show without a connection.\n\n\(message)")
        } actions: {
            Button("Try Again") {
                Task { await retry() }
            }
        }
    }
}

/// The note on a screen rendering its cached payload. A failed refresh over
/// readable data is worth a line, not an alert.
struct ActivityStaleNote: View {
    let fetchedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
            if let fetchedAt, fetchedAt > .distantPast {
                Text("Showing what we last saw, \(fetchedAt.formatted(.relative(presentation: .named))).")
            } else {
                Text("Showing what we last saw.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

// MARK: - Dates

/// Formatting for the activities dates, every one of which can be the server's
/// zero time. See `Date.isServerZero`.
enum ActivityDateText {

    /// One date, or `nil` when the server does not have one — which is what the
    /// web prints for it, and printing *Jan 1, 1* instead is the whole reason
    /// `isServerZero` exists.
    static func day(_ date: Date) -> String? {
        date.serverDate?.formatted(date: .abbreviated, time: .omitted)
    }

    /// A start/end pair. An event's end date is zero for the single-day case,
    /// which is the common one, so a range collapses to its start rather than
    /// reading as open-ended.
    static func range(from start: Date, to end: Date) -> String? {
        guard let start = start.serverDate else { return day(end) }
        guard let end = end.serverDate,
              !Calendar.current.isDate(start, inSameDayAs: end) else {
            return day(start)
        }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    /// When a performance happened. Falls back to the competition's start date,
    /// matching the backend's own `appearanceOrder`: "sometime that weekend" is
    /// a normal state for a competition schedule.
    static func occurred(_ appearance: AppearanceDTO, at event: EventSummaryDTO) -> String? {
        day(appearance.occurredAt) ?? day(event.startDate)
    }
}

// MARK: - People

/// Resolves the *server* person ids the activities payloads carry against the
/// people this device has pulled.
///
/// The same arrangement as `Milestone.photoRemoteIds`: the pairings are the
/// server's to own, and an id with nothing to resolve it renders as nothing
/// rather than as an error. A roster can name a child from a linked household
/// this device has never seen.
struct ActivityPeople {
    private let namesById: [Int: String]

    init(_ people: [Person]) {
        namesById = people.reduce(into: [Int: String]()) { result, person in
            if let remoteId = person.remoteId.flatMap(Int.init) {
                result[remoteId] = person.name
            }
        }
    }

    func name(_ personId: Int) -> String? {
        namesById[personId]
    }

    /// The names this device can resolve, in the order the server listed them.
    func names(_ personIds: [Int]) -> [String] {
        personIds.compactMap { namesById[$0] }
    }

    /// A roster line: the names that resolved, plus a count of the ones that did
    /// not, so a routine with a child from another household does not silently
    /// look like a smaller routine.
    func rosterText(_ personIds: [Int]) -> String? {
        guard !personIds.isEmpty else { return nil }
        let resolved = names(personIds)
        let unknown = personIds.count - resolved.count

        if resolved.isEmpty {
            return unknown == 1 ? "1 person" : "\(unknown) people"
        }
        if unknown == 0 {
            return resolved.formatted(.list(type: .and))
        }
        return "\(resolved.formatted(.list(type: .and))) + \(unknown) more"
    }
}

// MARK: - Results

/// One line off a results sheet.
///
/// The four kinds carry their meaning in different fields — a placement in
/// `rank`/`outOf`, a score in `score`, an adjudication or award in `label` — so
/// each is read out of the field it exists for and never defaulted. `rank` is
/// `nil` for "no placement", which is not the same as 1st.
struct ActivityResultRow: View {
    let result: ActivityResultDTO
    let people: ActivityPeople

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !result.notes.isEmpty {
                    Text(result.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch ActivityResultKind(rawValue: result.kind) {
        case .placement: return "trophy"
        case .adjudication: return "rosette"
        case .award: return "star"
        case .score: return "number"
        case nil: return "checkmark.seal"
        }
    }

    private var headline: String {
        switch ActivityResultKind(rawValue: result.kind) {
        case .placement:
            return ActivityResultText.placement(rank: result.rank, outOf: result.outOf, label: result.label)
        case .score:
            return ActivityResultText.score(result.score, label: result.label)
        case .adjudication, .award, nil:
            // An unrecognized kind still has a label worth reading; the backend
            // rejects unknown kinds on write, so this is a newer client's row.
            return result.label.isEmpty ? result.kind.capitalized : result.label
        }
    }

    /// The category the result was given in, plus the one person it names when
    /// it narrows an award to a single dancer in a group.
    private var detail: String? {
        var parts: [String] = []
        if !result.category.isEmpty {
            parts.append(result.category)
        }
        if let personId = result.personId, let name = people.name(personId) {
            parts.append(name)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum ActivityResultText {

    /// "1st of 14", "1st", or the label alone when there is no rank — which the
    /// backend does not allow on write, but an older row may hold.
    static func placement(rank: Int?, outOf: Int?, label: String) -> String {
        guard let rank else {
            return label.isEmpty ? "Placement" : label
        }
        var text = ordinal(rank)
        if let outOf {
            text += " of \(outOf)"
        }
        if !label.isEmpty {
            text += " · \(label)"
        }
        return text
    }

    static func score(_ score: Double?, label: String) -> String {
        guard let score else {
            return label.isEmpty ? "Score" : label
        }
        let text = number(score)
        return label.isEmpty ? text : "\(text) · \(label)"
    }

    /// Trailing zeros dropped: a score of 92 was written as 92, and "92.000" is
    /// a precision the sheet never claimed.
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }

    static func ordinal(_ value: Int) -> String {
        ordinalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}

// MARK: - Photos

/// The photos attached to a performance or a competition.
///
/// Rendered straight from *server* ids with `RemotePhotoView`, with no local
/// `Photo` record required: `visiblePhotoIds` filters per caller and the ids may
/// point at photos this device has never pulled.
struct ActivityPhotoStrip: View {
    let photoIds: [Int]

    var body: some View {
        if !photoIds.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photoIds, id: \.self) { photoId in
                        RemotePhotoView(remoteId: photoId, size: .thumb)
                            .frame(width: 88, height: 88)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

// MARK: - Appearance rows

/// What a performance row leads with, since the caller already knows one half of
/// the pair: the routine view knows the routine, the competition view knows the
/// competition.
enum AppearanceRowTitle {
    /// Lead with the entry — for a competition's running order.
    case entry
    /// Lead with the event — for a routine's history and a person's season.
    case event
}

/// One performance: what it was, where, when, how it went, and the photos of it.
///
/// `AppearanceDetail` carries both parents on purpose, so this one row renders a
/// performance in the competition view, the routine view and a person's season
/// alike.
struct AppearanceDetailRow: View {
    let detail: AppearanceDetailDTO
    let people: ActivityPeople
    let title: AppearanceRowTitle
    /// Set when the caller has wrapped the row in a `NavigationLink`, so the
    /// title reads as one.
    var showsChevron: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(titleText)
                        .font(.headline)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if detail.results.isEmpty {
                Text("No results recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.results) { result in
                    ActivityResultRow(result: result, people: people)
                }
            }

            if !detail.appearance.notes.isEmpty {
                Text(detail.appearance.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ActivityPhotoStrip(photoIds: detail.photoIds)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var titleText: String {
        switch title {
        case .entry: return detail.entry.name
        case .event: return detail.event.name
        }
    }

    /// The other half of the pair, plus when it happened. No vocabulary here on
    /// purpose: the label pack belongs in the section headers, and the free-text
    /// descriptors this reads are already the family's own words.
    private var subtitle: String? {
        var parts: [String] = []

        switch title {
        case .entry:
            let descriptors = ActivityEntryText.descriptors(detail.entry)
            if !descriptors.isEmpty {
                parts.append(descriptors)
            }
        case .event:
            if !detail.event.host.isEmpty {
                parts.append(detail.event.host)
            } else if !detail.event.location.isEmpty {
                parts.append(detail.event.location)
            }
        }

        if let when = ActivityDateText.occurred(detail.appearance, at: detail.event) {
            parts.append(when)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum ActivityEntryText {
    /// Format, style, division and level, in that order, skipping the ones this
    /// family does not use. All four are free text by design — competitions do
    /// not agree on what a division is called — so there is nothing to map.
    static func descriptors(_ entry: ActivityEntryDTO) -> String {
        [entry.format, entry.style, entry.division, entry.level]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
