import SwiftUI
import SwiftData

struct MilestoneRowView: View {
    let milestone: Milestone
    /// When set, the detail sheet offers editing and photo attachment. Views
    /// that show milestones for a person they don't own pass nil.
    var personId: UUID? = nil

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
                    .accessibilityLabel("\(milestone.photoRemoteIds.count) photos attached")
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
            MilestoneDetailSheetView(milestone: milestone, personId: personId)
        }
    }
}

private struct MilestoneDetailSheetView: View {
    let milestone: Milestone
    let personId: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingPhotoPicker = false

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

                    if personId != nil {
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label(
                                milestone.photoRemoteIds.isEmpty ? "Attach Photos" : "Change Photos",
                                systemImage: "photo.badge.plus"
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Milestone")
            .toolbar {
                if let personId {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit") { showingEdit = true }
                            .accessibilityHint("Edit this milestone")
                            .id(personId)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEdit) {
                if let personId {
                    AddMilestoneView(editing: milestone, personId: personId)
                }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                MilestonePhotoPickerView(milestone: milestone)
            }
        }
    }
}
