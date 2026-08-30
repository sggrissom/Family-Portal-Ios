import SwiftUI

/// The other people a stated relationship probably also applies to — "also daughter of Ruth" — as toggles beside the statement itself.
/// Offers rather than infers. Treating a partner's child as your own would be silent and unrefusable, and step-families are exactly where that is wrong, so the second parent is a tick the user makes and an edge the server stores like any other.
struct CoAnchorPicker: View {
    let suggestions: [CoAnchorSuggestion]
    /// Everyone a suggestion could name, matched by server id.
    let people: [Person]
    /// The word that was picked — "daughter", "sister" — so each row reads as the sentence it will save.
    let relationLabel: String
    let disabled: Bool
    @Binding var selectedIds: [Int]

    var body: some View {
        if !suggestions.isEmpty {
            ForEach(suggestions) { suggestion in
                if let person = person(for: suggestion.anchorId) {
                    Toggle(isOn: binding(for: suggestion.anchorId)) {
                        Text("Also \(relationLabel) of \(person.name)")
                    }
                    .disabled(disabled)
                }
            }
        }
    }

    private func person(for anchorId: Int) -> Person? {
        people.first { $0.remoteId.flatMap(Int.init) == anchorId }
    }

    private func binding(for anchorId: Int) -> Binding<Bool> {
        Binding(
            get: { selectedIds.contains(anchorId) },
            set: { isOn in
                if isOn {
                    guard !selectedIds.contains(anchorId) else { return }
                    selectedIds.append(anchorId)
                } else {
                    selectedIds.removeAll { $0 == anchorId }
                }
            }
        )
    }
}

extension CoAnchorPicker {
    /// Identifies the question a selection was made against — the word, the anchor, and who was on offer.
    /// A tick survives a redraw but must not survive the question changing: left alone it would save a relationship nobody stated. Views watch this and reset when it moves, rather than resetting inside `body`, which would be a write during view evaluation.
    static func suggestionKey(stated: StatedRelation?, anchorId: Int, suggestions: [CoAnchorSuggestion]) -> String {
        let statedValue = stated?.rawValue ?? StatedRelation.none.rawValue
        let offered = suggestions.map { String($0.anchorId) }.joined(separator: ",")
        return "\(statedValue):\(anchorId):\(offered)"
    }

    /// The ones worth ticking without being asked — only the single-partner co-parent case earns that.
    static func defaultSelection(_ suggestions: [CoAnchorSuggestion]) -> [Int] {
        suggestions.filter(\.defaultChecked).map(\.anchorId)
    }
}
