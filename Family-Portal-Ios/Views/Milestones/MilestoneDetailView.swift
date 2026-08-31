import SwiftUI

/// The whole milestone, shown when a row is tapped. This is the ordinary way into a milestone; editing is one
/// step further in, behind the Edit button, because a milestone is read many times and changed almost never.
/// Shared by the milestone list, the person screen and the timeline, whose rows all truncate the description.
struct MilestoneDetailSheetView: View {
    let milestone: Milestone

    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var syncService: SyncService?
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DetailSheetHeader(
                        icon: milestone.category.icon,
                        tint: milestone.category.color,
                        badge: milestone.category.label,
                        title: milestone.descriptionText
                    )

                    DetailFieldGroup {
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
