import SwiftUI

struct MilestoneRowView: View {
    let milestone: Milestone
    @State private var showingFullDescription = false

    private var categoryIcon: String {
        switch milestone.category {
        case .development: "leaf.fill"
        case .behavior: "face.smiling.fill"
        case .health: "heart.fill"
        case .achievement: "trophy.fill"
        case .first: "star.fill"
        case .other: "note.text"
        }
    }

    private var categoryColor: Color {
        switch milestone.category {
        case .development: .green
        case .behavior: .orange
        case .health: .red
        case .achievement: .yellow
        case .first: .purple
        case .other: .gray
        }
    }

    var body: some View {
        HStack {
            Label(milestone.category.rawValue.capitalized, systemImage: categoryIcon)
                .font(.caption)
                .foregroundStyle(categoryColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(categoryColor.opacity(0.15), in: Capsule())

            Text(milestone.descriptionText)
                .font(.body)
                .lineLimit(2)

            if !milestone.photoRemoteIds.isEmpty {
                Image(systemName: "photo.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        milestone.photoRemoteIds.count == 1
                            ? "1 photo"
                            : "\(milestone.photoRemoteIds.count) photos"
                    )
            }

            Spacer()

            Text(milestone.date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingFullDescription = true
        }
        .sheet(isPresented: $showingFullDescription) {
            MilestoneDetailSheetView(milestone: milestone)
        }
    }
}

private struct MilestoneDetailSheetView: View {
    let milestone: Milestone
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(milestone.descriptionText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        Label(milestone.category.rawValue.capitalized, systemImage: "tag.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(milestone.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Given a heading because the line above already shows the
                    // milestone's *category* behind a tag glyph — two different
                    // things one word apart, which a label keeps separate.
                    TagChipsView(tagRemoteIds: milestone.tagRemoteIds, title: "Tags")

                    NavigationLink {
                        TagPickerView(tagRemoteIds: milestone.tagRemoteIds) { tagRemoteIds in
                            guard let syncService else { return }
                            try await syncService.updateMilestoneTags(milestone, tagRemoteIds: tagRemoteIds)
                        }
                    } label: {
                        Label("Edit Tags", systemImage: "tag")
                    }

                    if !milestone.photoRemoteIds.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(milestone.photoRemoteIds, id: \.self) { photoId in
                                    RemotePhotoView(remoteId: photoId, size: .thumb)
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Milestone")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") {
                        isEditing = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
