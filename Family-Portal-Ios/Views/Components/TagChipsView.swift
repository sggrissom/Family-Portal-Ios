import SwiftUI
import SwiftData

/// The tags on a photo or milestone, resolved from the ids the record carries.
///
/// Read-only, as the web's viewing surfaces are: tags are created and applied on
/// the web, and iOS shows what came back. A record stores ids alone, so a tag the
/// local vocabulary cannot resolve draws nothing at all — the same as
/// `view-photo.tsx`, which skips an id it has no `Tag` for. That happens whenever
/// a tag is created between two pulls, and it is why the whole section (heading
/// included) disappears when nothing resolves rather than leaving an empty
/// "Tags" header behind.
struct TagChipsView: View {
    let tagRemoteIds: [Int]
    /// A heading drawn above the chips, for surfaces with room for one.
    var title: String?

    /// The whole vocabulary: a family's tag list is short, and filtering it in a
    /// `#Predicate` against an array of ids isn't something SwiftData can do.
    @Query private var tags: [FamilyTag]

    /// Kept in the record's own order, which is the order the server reports the
    /// pairings in and what the web renders.
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

/// One tag: its colour as a dot and an outline, its name in the usual text
/// colour. The colour is arbitrary and user-chosen, so it is never asked to
/// carry the label — a pale tag on a light background would be unreadable, and
/// the same tag has to work in both appearances.
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
