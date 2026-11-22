import SwiftUI

/// A competition's share preview: the whole recap as it will be sent, which routines go in, whether names show, then copy text or the share sheet. A short recap goes as one image, a long one as a PDF.
struct CompetitionShareSheet: View {
    let event: ActivityEventDTO
    let seasonName: String
    let routines: [CompetitionRoutine]
    let rosters: [Int: [Int]]
    let people: ActivityPeople
    let labels: ActivityLabels
    /// The phone is showing a copy that may be missing newer results.
    let mayBeIncomplete: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var options: CompetitionShare.Options
    @State private var file: URL?
    @State private var isPDF = false
    @State private var renderError: String?

    init(
        event: ActivityEventDTO,
        seasonName: String,
        routines: [CompetitionRoutine],
        rosters: [Int: [Int]],
        people: ActivityPeople,
        labels: ActivityLabels,
        mayBeIncomplete: Bool
    ) {
        self.event = event
        self.seasonName = seasonName
        self.routines = routines.filter { !$0.appearances.isEmpty }
        self.rosters = rosters
        self.people = people
        self.labels = labels
        self.mayBeIncomplete = mayBeIncomplete
        let unfinished = CompetitionShare.looksUnfinished(
            event: event,
            appearances: routines.flatMap(\.appearances),
            today: Date.now.localRecordDay().recordDayKey
        )
        _options = State(initialValue: CompetitionShare.Options(isSnapshot: unfinished))
    }

    private var share: CompetitionShare {
        CompetitionShare(
            event: event,
            seasonName: seasonName,
            routines: routines,
            rosters: rosters,
            people: people,
            options: options
        )
    }

    var body: some View {
        let current = share
        NavigationStack {
            List {
                Section {
                    CompetitionRecapView(share: current)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.3)))
                        .environment(\.colorScheme, .light)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if mayBeIncomplete {
                            Text(Copy.share.partial)
                        }
                        if current.routines.isEmpty {
                            Text(Copy.share.nothingIncluded)
                        }
                        if let renderError {
                            Text(renderError)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section(labels.entryPlural) {
                    ForEach(routines) { routine in
                        Toggle(routine.name, isOn: Binding(
                            get: { !options.omitted.contains(routine.entryId) },
                            set: { included in
                                if included {
                                    options.omitted.remove(routine.entryId)
                                } else {
                                    options.omitted.insert(routine.entryId)
                                }
                            }
                        ))
                    }
                }

                Section {
                    Toggle(Copy.share.showNames, isOn: $options.showsNames)
                    Toggle(Copy.share.resultsSoFar, isOn: $options.isSnapshot)
                } header: {
                    Text(Copy.share.include)
                } footer: {
                    Text(Copy.share.forwarding)
                }
            }
            .navigationTitle(Copy.share.previewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ShareActionsBar(
                    text: current.text,
                    file: file,
                    fileLabel: mayBeIncomplete ? Copy.share.shareAvailable : (isPDF ? Copy.share.sharePDF : Copy.share.shareImage),
                    isEnabled: !current.routines.isEmpty
                )
            }
        }
        .onAppear { ShareRendering.clearOldFiles() }
        .task(id: options) { render(current) }
    }

    private func render(_ share: CompetitionShare) {
        guard !share.routines.isEmpty else {
            file = nil
            return
        }
        let name = "\(share.eventName) results"
        do {
            let recap = CompetitionRecapView(share: share)
            if ShareRendering.height(of: recap, width: ShareRendering.imageWidth) <= ShareRendering.maxImageHeight {
                file = try ShareRendering.png(recap, named: name)
                isPDF = false
            } else {
                file = try ShareRendering.pdf(pages: Self.pages(share), named: name)
                isPDF = true
            }
            renderError = nil
        } catch {
            file = nil
            renderError = error.localizedDescription
        }
    }

    /// The header, then each routine kept to one page where it fits; a longer routine runs on a performance at a time.
    private static func pages(_ share: CompetitionShare) -> [AnyView] {
        var groups: [[AnyView]] = [[AnyView(RecapHeader(share: share))]]
        for routine in share.routines {
            var items: [AnyView] = []
            for (index, performance) in routine.performances.enumerated() {
                items.append(AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        if index == 0 {
                            Divider()
                            RecapRoutineHeading(routine: routine)
                        }
                        RecapPerformance(performance: performance)
                    }
                ))
            }
            if items.isEmpty {
                items.append(AnyView(VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    RecapRoutineHeading(routine: routine)
                }))
            }
            groups.append(items)
        }

        let width = ShareRendering.pageContentSize.width
        let heights = groups.map { $0.map { Double(ShareRendering.height(of: $0, width: width)) } }
        let plan = SharePagination.pages(
            groups: heights,
            pageHeight: Double(ShareRendering.pageContentSize.height),
            spacing: Double(ShareRendering.blockSpacing)
        )
        return plan.map { placements in
            AnyView(
                VStack(alignment: .leading, spacing: ShareRendering.blockSpacing) {
                    ForEach(Array(placements.enumerated()), id: \.offset) { _, placement in
                        ShareRendering.fitted(
                            groups[placement.group][placement.item],
                            height: CGFloat(heights[placement.group][placement.item])
                        )
                    }
                }
            )
        }
    }
}

/// The recap as one image: the event, then every included routine in the page's order.
struct CompetitionRecapView: View {
    let share: CompetitionShare

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RecapHeader(share: share)
            ForEach(share.routines) { routine in
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    RecapRoutineHeading(routine: routine)
                    ForEach(routine.performances) { performance in
                        RecapPerformance(performance: performance)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }
}

private struct RecapHeader: View {
    let share: CompetitionShare

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(share.eventName)
                .font(.title2.bold())
            let facts = [share.seasonName.isEmpty ? nil : share.seasonName, share.dates].compactMap { $0 }
            if !facts.isEmpty {
                Text(facts.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let place = share.place {
                Text(place)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let snapshot = share.snapshotLabel {
                Text(snapshot)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.orange)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecapRoutineHeading: View {
    let routine: CompetitionShare.Routine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(routine.name)
                .font(.headline)
            if let descriptors = routine.descriptors {
                Text(descriptors)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let roster = routine.roster {
                Text(roster)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let summary = routine.summary {
                Text(summary)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecapPerformance: View {
    let performance: CompetitionShare.Performance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let heading = [performance.when, performance.matchup].compactMap { $0 }
            if !heading.isEmpty {
                Text(heading.joined(separator: " · "))
                    .font(.subheadline.weight(.medium))
            }
            if performance.results.isEmpty && performance.matchup == nil {
                Text("No results recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(performance.results.enumerated()), id: \.offset) { _, result in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: ActivityResultText.icon(result.kind))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.text)
                            .font(.subheadline.weight(.medium))
                        if let detail = result.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
