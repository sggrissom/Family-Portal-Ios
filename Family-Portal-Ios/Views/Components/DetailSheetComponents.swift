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

/// What a record is compared against — the family, everyone at the same age, the same milestone elsewhere — under a heading that folds it away.
/// Each kind remembers being folded across every screen it appears on, so someone who only wants the record itself folds it once rather than scrolling past it each time.
/// Open until then: the comparisons are the point of most of these screens.
struct ContextSection<Accessory: View, Content: View>: View {
    let title: String
    @AppStorage private var isExpanded: Bool
    private let accessory: Accessory
    private let content: Content

    init(
        _ title: String,
        kind: ContextKind,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _isExpanded = AppStorage(wrappedValue: true, kind.storageKey)
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    withAnimation(.snappy) { isExpanded.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isExpanded ? "Hides this section" : "Shows this section")

                Spacer()

                // A link out (See all) only means something once the section is open.
                if isExpanded {
                    accessory
                }
            }

            if isExpanded {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ContextSection where Accessory == EmptyView {
    init(_ title: String, kind: ContextKind, @ViewBuilder content: () -> Content) {
        self.init(title, kind: kind, accessory: { EmptyView() }, content: content)
    }
}

/// The kinds of context a `ContextSection` folds, each remembered on its own.
enum ContextKind: String {
    case family
    case sameAge
    case milestoneMatches

    var storageKey: String { "contextSection.\(rawValue).expanded" }
}
