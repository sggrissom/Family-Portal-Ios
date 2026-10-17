import Foundation

/// How global search compares words — `foldText`, `searchTerms` and `termsMatch` in backend/search.go, and `highlightRanges` in frontend/lib/search.ts — so the offline pass matches what the server would, and highlights land on the same letters as on the web.
/// Matching is prefix-of-word with every term required, after folding case and accents: `walk` finds "Walked", `cafe` finds "Café".
nonisolated enum SearchText {

    /// Dropped from the free text before matching (`searchFillerWords`).
    static let fillerWords: Set<String> = [
        "a", "an", "the", "and", "at", "in", "on", "of", "with", "to", "for",
        "photo", "photos", "picture", "pictures", "when", "was", "old",
    ]

    /// Lowercased, with accents removed: decomposed, then every non-spacing mark dropped.
    static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars
        where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar)
        }
        return String(scalars).lowercased()
    }

    /// A letter or a digit. Everything else separates words.
    static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
            return true
        default:
            return false
        }
    }

    /// The folded words of every field, in order.
    static func words(_ fields: String...) -> [String] {
        words(of: fields)
    }

    static func words(of fields: [String]) -> [String] {
        var out: [String] = []
        for field in fields {
            var word = String.UnicodeScalarView()
            for scalar in fold(field).unicodeScalars {
                if isWordScalar(scalar) {
                    word.append(scalar)
                } else if !word.isEmpty {
                    out.append(String(word))
                    word = String.UnicodeScalarView()
                }
            }
            if !word.isEmpty {
                out.append(String(word))
            }
        }
        return out
    }

    /// The free text of a search as folded words, without filler.
    static func terms(_ text: String) -> [String] {
        words(text).filter { !fillerWords.contains($0) }
    }

    /// Whether `term` starts `word`. Compared by scalar, since both are folded.
    static func isPrefix(_ term: String, of word: String) -> Bool {
        word.unicodeScalars.starts(with: term.unicodeScalars)
    }

    /// Whether every term starts some word. No terms matches nothing.
    static func matches(_ terms: [String], words: [String]) -> Bool {
        guard !terms.isEmpty else { return false }
        return terms.allSatisfy { term in words.contains { isPrefix(term, of: $0) } }
    }

    /// Where a term starts a word of `text`, as ranges of the original text, in order. Each covers as much of its word as the longest matching term does, so `caf` marks "Caf" of "Café".
    static func highlightRanges(in text: String, terms: [String]) -> [Range<String.Index>] {
        guard !terms.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard isWordCharacter(text[index]) else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, isWordCharacter(text[index]) {
                index = text.index(after: index)
            }
            let word = text[start..<index]
            let folded = fold(String(word))
            let longest = terms
                .filter { isPrefix($0, of: folded) }
                .map(\.unicodeScalars.count)
                .max() ?? 0
            guard longest > 0 else { continue }

            var end = start
            var length = 0
            while end < index, length < longest {
                length += fold(String(text[end])).unicodeScalars.count
                end = text.index(after: end)
            }
            ranges.append(start..<end)
        }
        return ranges
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.first.map(isWordScalar) ?? false
    }
}
