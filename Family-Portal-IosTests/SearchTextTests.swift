import Foundation
import Testing
@testable import Family_Portal_Ios

/// `foldText`/`termsMatch` in backend/search.go and `highlightRanges` in frontend/lib/search.ts.
@Suite("Search text")
struct SearchTextTests {

    private func marked(_ text: String, _ query: String) -> [String] {
        SearchText.highlightRanges(in: text, terms: SearchText.terms(query)).map { String(text[$0]) }
    }

    @Test("Folding lowercases and drops accents")
    func folding() {
        #expect(SearchText.fold("Café ZOË Ñandú") == "cafe zoe nandu")
        #expect(SearchText.fold("Cafe\u{301}") == "cafe")
    }

    @Test("Words split on anything that isn't a letter or a digit")
    func words() {
        #expect(SearchText.words("Ada's first-steps, 2024!") == ["ada", "s", "first", "steps", "2024"])
        #expect(SearchText.words("Beach", "Lake  day") == ["beach", "lake", "day"])
        #expect(SearchText.words("") == [])
    }

    @Test("Terms leave out filler words")
    func terms() {
        #expect(SearchText.terms("photos of the beach") == ["beach"])
        #expect(SearchText.terms("Walk to the park") == ["walk", "park"])
    }

    @Test("Every term must start some word")
    func prefixMatching() {
        let words = SearchText.words("Walked to the café with Grandma")
        #expect(SearchText.matches(["walk"], words: words))
        #expect(SearchText.matches(["cafe", "grand"], words: words))
        #expect(!SearchText.matches(["alked"], words: words))
        #expect(!SearchText.matches(["walk", "beach"], words: words))
        #expect(!SearchText.matches([], words: words))
    }

    @Test("Highlights cover the matched start of each word")
    func highlights() {
        #expect(marked("Walked to the park, walking home", "walk") == ["Walk", "walk"])
        #expect(marked("First steps at the café", "caf step") == ["step", "caf"])
        #expect(marked("Lunch at Café Rouge", "cafe") == ["Café"])
        #expect(marked("Nothing here", "beach") == [])
        #expect(marked("Anything", "") == [])
    }

    @Test("The longest matching term decides how much is marked")
    func longestTerm() {
        #expect(marked("Grandmother visited", "gran grandmo") == ["Grandmo"])
    }

    @Test("A decomposed accent stays with its letter")
    func decomposedAccent() {
        let text = "Cafe\u{301} trip"
        let ranges = SearchText.highlightRanges(in: text, terms: ["cafe"])
        #expect(ranges.map { String(text[$0]) } == ["Cafe\u{301}"])
    }
}
