import SwiftUI

struct MilestoneRowView: View {
    let milestone: Milestone
    var showsPerson = false
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if showsPerson, let person = milestone.person {
                    Text(person.name)
                        .font(.subheadline.weight(.semibold))
                }

                Text(milestone.displayText)
                    .font(.body)
                    .italic(milestone.category == .quote)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                FlowLayout(spacing: 8) {
                    Label(milestone.category.label, systemImage: milestone.category.icon)
                        .foregroundStyle(milestone.category.color)
                    Text(milestone.date.localDay().formatted(date: .abbreviated, time: .omitted))
                    if !milestone.photoRemoteIds.isEmpty {
                        Label(
                            milestone.photoRemoteIds.count == 1 ? "1 photo" : "\(milestone.photoRemoteIds.count) photos",
                            systemImage: "photo.on.rectangle"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens milestone details and attached photos")
        .sheet(isPresented: $showingDetail) {
            MilestoneDetailSheetView(milestone: milestone)
        }
    }
}
