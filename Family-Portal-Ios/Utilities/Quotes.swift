import Foundation

/// A quote is stored as the bare words and drawn inside quotation marks — the server's `unquote`, so a quote saved offline reads the same before and after it syncs.
enum Quotes {
    private static let marks: [Character: Character] = ["\"": "\"", "“": "”", "„": "“", "«": "»", "'": "'", "‘": "’"]

    static func unquote(_ text: String) -> String {
        guard text.count >= 2, let opening = text.first, let closing = marks[opening], text.last == closing else {
            return text
        }
        let inner = text.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        if inner.isEmpty || inner.contains(opening) || inner.contains(closing) {
            return text
        }
        return inner
    }

    static func display(_ text: String, category: MilestoneCategory) -> String {
        category == .quote ? "“\(text)”" : text
    }
}

extension Milestone {
    var displayText: String { Quotes.display(descriptionText, category: category) }

    /// What the add and edit forms typed, as stored: trimmed, a quote without quotation marks around it, and context kept only for a quote. Set `category` first.
    func setEntry(_ text: String, context: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionText = category == .quote ? Quotes.unquote(text) : text
        self.context = category == .quote ? context.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}

extension MilestoneDTO {
    var displayText: String {
        Quotes.display(descriptionText, category: MilestoneCategory(rawValue: category) ?? .other)
    }
}
