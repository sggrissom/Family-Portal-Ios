import SwiftUI
import SwiftData

/// The tags on a photo or milestone, resolved from the ids the record carries. Read-only, as on the web.
/// An id the local vocabulary cannot resolve draws nothing, which happens whenever a tag is created between two pulls — so the whole section disappears when nothing resolves rather than leaving an empty header.
struct TagChipsView: View {
    let tagRemoteIds: [Int]
    var title: String?

    /// The whole vocabulary: a family's tag list is short, and SwiftData cannot filter an array of ids in a `#Predicate`.
    @Query private var tags: [FamilyTag]

    /// Kept in the record's own order, which is what the server reports and the web renders.
    private var resolvedTags: [FamilyTag] {
        var byRemoteId: [Int: FamilyTag] = [:]
        for tag in tags {
            if let remoteId = tag.remoteId.flatMap(Int.init) {
                byRemoteId[remoteId] = tag
            }
        }
        return tagRemoteIds.compactMap { byRemoteId[$0] }
    }

    var body: some View {
        if !resolvedTags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.headline)
                }

                FlowLayout(spacing: 8) {
                    ForEach(resolvedTags) { tag in
                        TagChipView(tag: tag)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One tag: its colour as a dot and an outline, its name in the usual text colour — a user-chosen colour is never asked to carry the label.
struct TagChipView: View {
    let tag: FamilyTag

    private var color: Color {
        TagColor.color(forHex: tag.colorHex)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(tag.name)
                .font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(
            Capsule()
                .stroke(color.opacity(0.7), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag: \(tag.name)")
    }
}
