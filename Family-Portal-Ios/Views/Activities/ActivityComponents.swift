import SwiftUI

// Shared pieces of the activities screens: the load states, the date and result formatting the server leaves to the client, and the rows that render a performance.

// MARK: - The screen container

struct ActivityScreen<Value: Sendable, Content: View>: View {
    let state: ActivityScreenState<Value>
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
            if state.isShowingCached, !state.isLoading, state.value != nil {
                ActivityStaleNote(fetchedAt: state.fetchedAt)
            }
        }
        .task { await state.load(read()) }
    }
}

// MARK: - Load states

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

/// Formatting for the activities dates, every one of which can be the server's zero time. See `Date.isServerZero`.
enum ActivityDateText {

    static func day(_ date: Date) -> String? {
        date.serverDate?.formatted(date: .abbreviated, time: .omitted)
    }

    static func range(from start: Date, to end: Date) -> String? {
        guard let start = start.serverDate else { return day(end) }
        guard let end = end.serverDate,
              !Calendar.current.isDate(start, inSameDayAs: end) else {
            return day(start)
        }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    static func occurred(_ appearance: AppearanceDTO, at event: EventSummaryDTO) -> String? {
        day(appearance.occurredAt) ?? day(event.startDate)
    }
}

// MARK: - People

/// Resolves the *server* person ids the activities payloads carry against the people this device has pulled. An id with nothing to resolve it renders as nothing.
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

    func names(_ personIds: [Int]) -> [String] {
        personIds.compactMap { namesById[$0] }
    }

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

/// One line off a results sheet. Each kind carries its meaning in a different field, so none is defaulted — a `nil` rank is "no placement", not 1st.
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
            return result.label.isEmpty ? result.kind.capitalized : result.label
        }
    }

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

/// The photos attached to a performance or a competition, rendered straight from *server* ids with no local `Photo` record required.
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

enum AppearanceRowTitle {
    case entry
    case event
}

struct AppearanceDetailRow: View {
    let detail: AppearanceDetailDTO
    let people: ActivityPeople
    let title: AppearanceRowTitle
    var showsChevron: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(titleText)
                        .font(.headline)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
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
    static func descriptors(_ entry: ActivityEntryDTO) -> String {
        [entry.format, entry.style, entry.division, entry.level]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
