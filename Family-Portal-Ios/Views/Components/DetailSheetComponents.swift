import SwiftUI

/// The chrome the milestone and measurement "view" sheets share, so the two read as the same kind of screen
/// and a new fact can be dropped into either without either one inventing its own layout for it.

/// A record's headline: what kind of thing it is, in a tinted chip, above the record's own words.
struct DetailSheetHeader: View {
    let icon: String
    let tint: Color
    let badge: String
    let title: String
    /// `.title3` by default: a milestone's headline is its whole description, which can run to a sentence or two.
    var titleFont: Font = .title3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(badge, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.15), in: Capsule())

            Text(title)
                .font(titleFont)
                .fontWeight(.semibold)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One labelled fact: its name on the left, its value on the right.
struct DetailFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        // Otherwise VoiceOver reads the label and the value as two unrelated stops.
        .accessibilityElement(children: .combine)
    }
}

/// The box the rest of the app puts facts in, holding a stack of `DetailFieldRow`s.
/// Callers put a `Divider()` between rows themselves — a `ViewBuilder` can't interleave them.
struct DetailFieldGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
