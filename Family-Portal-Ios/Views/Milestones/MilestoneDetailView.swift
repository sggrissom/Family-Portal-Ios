import SwiftData
import SwiftUI

/// The whole milestone, shown when a row is tapped. This is the ordinary way into a milestone; editing is one
/// step further in, behind the Edit button, because a milestone is read many times and changed almost never.
/// Shared by the milestone list, the person screen and the timeline, whose rows all truncate the description.
struct MilestoneDetailSheetView: View {
    let milestone: Milestone

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            MilestoneDetailContent(milestone: milestone)
                .navigationTitle("Milestone")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .sheet(isPresented: $isEditing) {
                    EditMilestoneView(milestone: milestone)
                }
        }
    }
}

/// The milestone page itself, without the sheet's chrome, so a match can push another milestone onto the same stack.
struct MilestoneDetailContent: View {
    let milestone: Milestone

    @Environment(SyncService.self) private var syncService: SyncService?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailSheetHeader(
                    icon: milestone.category.icon,
                    tint: milestone.category.color,
                    badge: milestone.category.label,
                    title: milestone.displayText
                )

                DetailFieldGroup {
                    if !milestone.context.isEmpty {
                        DetailFieldRow(label: Copy.person.contextLabel, value: milestone.context)
                        Divider()
                    }

                    DetailFieldRow(
                        label: "Date",
                        value: milestone.date.formatted(date: .long, time: .omitted)
                    )

                    if let person = milestone.person {
                        Divider()
                        DetailFieldRow(label: "Person", value: person.name)

                        if let age = person.age(on: milestone.date) {
                            Divider()
                            DetailFieldRow(label: "Age", value: age)
                        }
                    }
                }

                if !milestone.photoRemoteIds.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photos")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(milestone.photoRemoteIds, id: \.self) { photoId in
                                    RemotePhotoView(remoteId: photoId, size: .thumb)
                                        .frame(width: 88, height: 88)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MilestoneMatchesSection(milestone: milestone)

                PersonSameAgeStrip(person: milestone.person, date: milestone.date)

                // Given a heading because the chip up top already shows the milestone's *category* behind a tag-shaped glyph.
                TagChipsView(tagRemoteIds: milestone.tagRemoteIds, title: "Tags")

                // The one edit that stays on this screen: tags are the part people reach for from a view, and
                // the picker saves on its own rather than through the milestone editor.
                NavigationLink {
                    TagPickerView(tagRemoteIds: milestone.tagRemoteIds) { tagRemoteIds in
                        guard let syncService else { return }
                        try await syncService.updateMilestoneTags(milestone, tagRemoteIds: tagRemoteIds)
                    }
                } label: {
                    Label("Edit Tags", systemImage: "tag")
                        .font(.subheadline)
                }
            }
            .padding()
        }
    }
}

/// "The same milestone in the family": a sibling's or cousin's matching milestone, from `GetMilestoneMatches`. Online only; hidden when there are none, when offline, and for a milestone still uploading.
struct MilestoneMatchesSection: View {
    let milestone: Milestone

    @Environment(NetworkMonitor.self) private var network: NetworkMonitor?
    @Environment(\.modelContext) private var modelContext
    @State private var matches: [MilestoneMatchDTO] = []

    var body: some View {
        // A container rather than a `Group`, so the `.task` runs before there is anything to show.
        VStack(alignment: .leading, spacing: 10) {
            if !matches.isEmpty {
                Text(Copy.milestoneDetail.matchesTitle)
                    .font(.headline)
                ForEach(matches, id: \.milestone.id) { match in
                    if let local = localMilestone(remoteId: match.milestone.id) {
                        NavigationLink {
                            MilestoneDetailContent(milestone: local)
                                .navigationTitle("Milestone")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            row(match)
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(match)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: milestone.remoteId) {
            guard let id = milestone.remoteId.flatMap(Int.init) else {
                matches = []
                return
            }
            let response = await AnalysisService.shared.milestoneMatches(milestoneId: id, isConnected: network?.isConnected ?? true)
            matches = response?.matches ?? []
        }
    }

    private func row(_ match: MilestoneMatchDTO) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Copy.milestoneDetail.match(name: match.person.name, ageMonths: match.ageMonths))
                .font(.subheadline.weight(.semibold))
            Text(match.milestone.displayText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func localMilestone(remoteId: Int) -> Milestone? {
        let key = String(remoteId)
        var descriptor = FetchDescriptor<Milestone>(predicate: #Predicate { $0.remoteId == key })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
