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
                }
                .padding()
            }
            .navigationTitle("Milestone")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
