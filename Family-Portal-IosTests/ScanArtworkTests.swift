import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Scanning artwork")
@MainActor
struct ScanArtworkTests {

    @Test("Bytes that aren't an image have nothing to lift")
    func liftingGarbage() async {
        #expect(await SubjectLift.lift(Data([0, 1, 2])) == nil)
    }

    @Test("Scanning artwork is its own add form")
    func scanFormIdentity() {
        let id = UUID()
        let forms: [AddForm] = [.milestone(personId: id), .quote(personId: id), .scannedArtwork(personId: id)]
        #expect(Set(forms.map(\.id)).count == 3)
    }
}
