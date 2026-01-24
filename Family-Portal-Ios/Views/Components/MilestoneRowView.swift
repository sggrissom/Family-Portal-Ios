import SwiftUI

struct MilestoneRowView: View {
    let milestone: Milestone

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
    }
}
