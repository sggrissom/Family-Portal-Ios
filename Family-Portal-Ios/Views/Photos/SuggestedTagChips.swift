import SwiftUI

/// Pending tag suggestions on one photo, drawn as **dashed** chips after the real tags as on the web's photo page. Tapping one asks: add it, or not this. Nothing is tagged until the user says so.
struct SuggestedTagChips: View {
    let suggestions: [SuggestedTagDTO]
    let onAccept: (SuggestedTagDTO) -> Void
    let onReject: (SuggestedTagDTO) -> Void

    @State private var asking: SuggestedTagDTO?

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(Copy.tagSuggestions.onPhotoTitle)
                    .font(.headline)
                FlowLayout(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        chip(suggestion)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .confirmationDialog(
                asking?.label ?? "",
                isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                titleVisibility: .visible,
                presenting: asking
            ) { suggestion in
                Button(Copy.tagSuggestions.addTag(suggestion.label)) { onAccept(suggestion) }
                Button(Copy.tagSuggestions.notThis, role: .destructive) { onReject(suggestion) }
            }
        }
    }

    private func chip(_ suggestion: SuggestedTagDTO) -> some View {
        let color = TagColor.color(forHex: suggestion.color)
        return Button {
            asking = suggestion
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(suggestion.label)
                    .font(.subheadline)
                Image(systemName: "plus")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay {
                Capsule()
                    .strokeBorder(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.tagSuggestions.suggestedLabel(suggestion.label))
    }
}
