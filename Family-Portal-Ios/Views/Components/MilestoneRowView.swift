import SwiftUI

struct MilestoneRowView: View {
    let milestone: Milestone
    @State private var showingDetail = false

    var body: some View {
        HStack {
            Label(milestone.category.label, systemImage: milestone.category.icon)
                .font(.caption)
                .foregroundStyle(milestone.category.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(milestone.category.color.opacity(0.15), in: Capsule())

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
        .accessibilityHint("Shows the full milestone")
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            MilestoneDetailSheetView(milestone: milestone)
        }
    }
}
