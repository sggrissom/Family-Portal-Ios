import SwiftUI
import SwiftData

/// A measurement's share preview: the card as it will be sent, which comparisons go with it, then copy text or the share sheet. Built from what is on the phone, so it works straight after a save while sync is pending.
struct MeasurementShareSheet: View {
    let measurements: [GrowthData]

    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]
    @Environment(\.dismiss) private var dismiss

    @State private var omitted: Set<String> = []
    @State private var file: URL?
    @State private var renderError: String?

    private var full: MeasurementShare? {
        MeasurementShare(measurements: measurements, people: people, relations: relations)
    }

    private var isPendingSync: Bool {
        measurements.contains { $0.remoteId == nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let full {
                    content(full)
                } else {
                    ContentUnavailableView(Copy.share.renderFailed, systemImage: "square.and.arrow.up")
                }
            }
            .navigationTitle(Copy.share.previewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { ShareRendering.clearOldFiles() }
        .task(id: omitted) { render() }
    }

    private func content(_ full: MeasurementShare) -> some View {
        let share = full.omitting(omitted)
        return List {
            Section {
                MeasurementShareCard(share: share)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.3)))
                    .environment(\.colorScheme, .light)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if isPendingSync {
                        Text(Copy.share.pendingSync)
                    }
                    if let renderError {
                        Text(renderError)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                comparisonToggles(full)
            } header: {
                Text(Copy.share.comparisons)
            } footer: {
                Text(Copy.share.forwarding)
            }
        }
        .safeAreaInset(edge: .bottom) {
            ShareActionsBar(text: share.text, file: file, fileLabel: Copy.share.shareImage, isEnabled: true)
        }
    }

    @ViewBuilder
    private func comparisonToggles(_ full: MeasurementShare) -> some View {
        let ids = full.rowIds
        if ids.isEmpty {
            Text(Copy.share.noComparisons)
                .foregroundStyle(.secondary)
        } else {
            Toggle(Copy.share.allComparisons, isOn: Binding(
                get: { omitted.isDisjoint(with: ids) },
                set: { omitted = $0 ? [] : Set(ids) }
            ))
            ForEach(full.sections) { section in
                ForEach(section.rows) { row in
                    Toggle(isOn: Binding(
                        get: { !omitted.contains(row.id) },
                        set: { included in
                            if included { omitted.remove(row.id) } else { omitted.insert(row.id) }
                        }
                    )) {
                        Text(full.sections.count > 1 ? "\(section.type.label): \(row.heading)" : row.heading)
                    }
                }
            }
        }
    }

    private func render() {
        guard let share = full?.omitting(omitted) else { return }
        let types = share.sections.map(\.type.label).joined(separator: " and ")
        do {
            file = try ShareRendering.png(MeasurementShareCard(share: share), named: "\(share.personName) \(types)")
            renderError = nil
        } catch {
            file = nil
            renderError = error.localizedDescription
        }
    }
}

/// The image that goes out: who, when, each value, and the comparisons left in.
struct MeasurementShareCard: View {
    let share: MeasurementShare

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(share.personName)
                    .font(.title2.bold())
                Text([share.dateText, share.ageText].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(share.sections) { section in
                sectionView(section)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private func sectionView(_ section: MeasurementShare.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(section.type.label, systemImage: section.type.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(section.type.color)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.value)
                    .font(.largeTitle.bold())
                if let alternate = section.alternate {
                    Text(alternate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                if let group = row.group, index == 0 || section.rows[index - 1].group != group {
                    Text(group)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 4)
                }
                rowView(row, tint: section.type.color)
            }
        }
    }

    private func rowView(_ row: MeasurementShare.Row, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.heading)
                .font(.subheadline.weight(.semibold))
            ForEach(Array(row.lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.title)
                        .font(.subheadline)
                    if let detail = line.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
