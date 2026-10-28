import SwiftData
import SwiftUI

/// The whole milestone, shown when a row is tapped. This is the ordinary way into a milestone; editing is one
/// step further in, behind the Edit button, because a milestone is read many times and changed almost never.
/// Shared by the milestone list, the person screen and the timeline, with the complete description and attached photos.
struct MilestoneDetailSheetView: View {
    let milestone: Milestone

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService
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

/// A milestone pushed by local id — what a link to one opens. A milestone deleted since shows nothing rather than a stale page.
struct MilestoneRouteView: View {
    @Query private var milestones: [Milestone]

    init(milestoneId: UUID) {
        _milestones = Query(filter: #Predicate<Milestone> { $0.id == milestoneId })
    }

    var body: some View {
        if let milestone = milestones.first {
            MilestoneDetailContent(milestone: milestone)
                .navigationTitle(milestone.category.label)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(Copy.milestoneDetail.notFound, systemImage: "star.slash")
        }
    }
}

/// The milestone page itself, without the sheet's chrome, so a match can push another milestone onto the same stack.
struct MilestoneDetailContent: View {
    let milestone: Milestone

    @Environment(SyncService.self) private var syncService
    @Environment(AuthService.self) private var authService

    @State private var selectedPhoto: AttachedPhotoSelection?
    @State private var showsRelatedMemories = false

    private var isAnswer: Bool { milestone.interviewId > 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    if let person = milestone.person {
                        Text(person.name)
                            .font(.headline)
                    }

                    // An interview answer reads under the question it answers.
                    if isAnswer, !milestone.context.isEmpty {
                        Text(milestone.context)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

                if isAnswer {
                    NavigationLink {
                        InterviewView(interviewId: milestone.interviewId)
                    } label: {
                        Text(Copy.interview.answerOf(Interviews.fallbackTitle(
                            personName: milestone.person?.name ?? "",
                            birthday: milestone.person?.birthday,
                            date: milestone.date
                        )))
                        .font(.subheadline)
                    }
                } else if !milestone.context.isEmpty {
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
                                            .videoBadge(remoteId: photoId)
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
                                // An answer has no matches: the web asks for none, since its siblings' answers are the interview's own comparison.
                                if !isAnswer {
                                    MilestoneMatchesSection(milestone: milestone)
                                }
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

/// Reads attached IDs directly, including photos that haven't been mirrored into the local store. A video plays in place of its poster.
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
                    let photoId = photoIds[index]
                    MirroredPhoto(remoteId: photoId) { local in
                        RemoteMediaView(remoteId: photoId, local: local) {
                            ZoomableView {
                                RemotePhotoView(remoteId: photoId, size: .xlarge, contentMode: .fit)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                    }
                    .id(photoId)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    // The player's notes are secondary text, which needs the dark palette to read on black.
                    .environment(\.colorScheme, .dark)
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
                    if photoIds.indices.contains(index) {
                        MirroredPhoto(remoteId: photoIds[index]) { local in
                            // A video has the player's own controls instead.
                            if local?.isVideo != true {
                                Text("Pinch to zoom")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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

    @Environment(NetworkMonitor.self) private var network
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
            guard let id = milestone.serverId else {
                matches = []
                return
            }
            let response = await AnalysisService.shared.milestoneMatches(milestoneId: id, isConnected: network.isConnected)
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
