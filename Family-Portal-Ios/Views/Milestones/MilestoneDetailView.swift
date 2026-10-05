import SwiftData
import SwiftUI

/// The whole milestone, shown when a row is tapped. This is the ordinary way into a milestone; editing is one
/// step further in, behind the Edit button, because a milestone is read many times and changed almost never.
/// Shared by the milestone list, the person screen and the timeline, with the complete description and attached photos.
struct MilestoneDetailSheetView: View {
    let milestone: Milestone

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService: AuthService?
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            MilestoneDetailContent(milestone: milestone)
                .navigationTitle(milestone.category.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // A view-only member reads the milestone and nothing more.
                    if authService.access.canContribute(to: milestone) {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Edit") {
                                isEditing = true
                            }
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
    @Environment(AuthService.self) private var authService: AuthService?

    @State private var selectedPhoto: AttachedPhotoSelection?
    @State private var showsRelatedMemories = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    if let person = milestone.person {
                        Text(person.name)
                            .font(.headline)
                    }

                    Text(milestone.displayText)
                        .font(milestone.category == .quote ? .title2 : .title3)
                        .italic(milestone.category == .quote)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(milestone.date.displayDay().formatted(date: .long, time: .omitted))
                        if let age = milestone.person?.age(on: milestone.date) {
                            Text("Age \(age)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if !milestone.context.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Copy.person.contextLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(milestone.context)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !milestone.photoRemoteIds.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photos · Tap to expand")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(milestone.photoRemoteIds, id: \.self) { photoId in
                                    Button {
                                        selectedPhoto = AttachedPhotoSelection(id: photoId)
                                    } label: {
                                        RemotePhotoView(remoteId: photoId, size: .medium, contentMode: .fit)
                                            .frame(width: 160, height: 160)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(alignment: .bottomTrailing) {
                                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                    .font(.caption.weight(.semibold))
                                                    .padding(8)
                                                    .background(.regularMaterial, in: Circle())
                                                    .padding(6)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Open attached photo \((milestone.photoRemoteIds.firstIndex(of: photoId) ?? 0) + 1) of \(milestone.photoRemoteIds.count)")
                                    .accessibilityHint("Opens a full-screen photo you can zoom")
                                }
                            }
                        }
                    }
                }

                // Keep tags separate from the memory and its context.
                TagChipsView(tagRemoteIds: milestone.tagRemoteIds, title: "Tags")

                // The one edit that stays on this screen: tags are the part people reach for from a view, and
                // the picker saves on its own rather than through the milestone editor.
                if authService.access.canContribute(to: milestone) {
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

                if milestone.remoteId != nil || milestone.person?.remoteId != nil {
                    Divider()
                    DisclosureGroup("Related family memories", isExpanded: $showsRelatedMemories) {
                        if showsRelatedMemories {
                            VStack(alignment: .leading, spacing: 20) {
                                MilestoneMatchesSection(milestone: milestone)
                                PersonSameAgeStrip(person: milestone.person, date: milestone.date)
                            }
                            .padding(.top, 12)
                        }
                    }
                    .font(.subheadline)
                }
            }
            .padding()
        }
        .fullScreenCover(item: $selectedPhoto) { selection in
            MilestonePhotoViewer(photoIds: milestone.photoRemoteIds, initialPhotoId: selection.id)
        }
    }
}

private struct AttachedPhotoSelection: Identifiable {
    let id: Int
}

/// Reads attached IDs directly, including photos that haven't been mirrored into the local store.
private struct MilestonePhotoViewer: View {
    let photoIds: [Int]
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(photoIds: [Int], initialPhotoId: Int) {
        self.photoIds = photoIds
        _index = State(initialValue: photoIds.firstIndex(of: initialPhotoId) ?? 0)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if photoIds.indices.contains(index) {
                    ZoomableView {
                        RemotePhotoView(remoteId: photoIds[index], size: .xlarge, contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .id(photoIds[index])
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                } else {
                    ContentUnavailableView("Photo unavailable", systemImage: "photo")
                }
            }
            .background(.black)
            .navigationTitle("Photo \(index + 1) of \(photoIds.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if photoIds.count > 1 {
                        Button { index -= 1 } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }
                        .disabled(index == 0)
                        .accessibilityLabel("Previous photo")
                    }
                    Spacer()
                    Text("Pinch to zoom")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if photoIds.count > 1 {
                        Button { index += 1 } label: {
                            Image(systemName: "chevron.right").frame(width: 44, height: 44)
                        }
                        .disabled(index >= photoIds.count - 1)
                        .accessibilityLabel("Next photo")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .preferredColorScheme(.dark)
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
                ContextSection(Copy.milestoneDetail.matchesTitle, kind: .milestoneMatches) {
                    matchRows
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

    private var matchRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(matches, id: \.milestone.id) { match in
                if let local = localMilestone(remoteId: match.milestone.id) {
                    NavigationLink {
                        MilestoneDetailContent(milestone: local)
                            .navigationTitle(local.category.label)
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
