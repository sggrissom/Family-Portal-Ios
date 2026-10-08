import Foundation
import Testing
@testable import Family_Portal_Ios

@MainActor
@Suite("Growing up preview")
struct GrowingUpPreviewTests {

    @Test("The preview spreads five faces across the whole timeline, first and last included")
    func spreadsAcrossTimeline() {
        #expect(GrowingUpPreview.spread(Array(0..<10)) == [0, 2, 5, 7, 9])
        #expect(GrowingUpPreview.spread(Array(0..<5)) == [0, 1, 2, 3, 4])
    }

    @Test("Fewer than five shows them all")
    func fewShowsAll() {
        #expect(GrowingUpPreview.spread([1, 2, 3]) == [1, 2, 3])
        #expect(GrowingUpPreview.spread([7]) == [7])
        #expect(GrowingUpPreview.spread([Int]()) == [])
    }
}
