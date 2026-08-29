import Foundation
import SwiftData

/// One label in a family's own vocabulary — `Tag` in backend/tags.go. Named `FamilyTag` because a bare `Tag` collides with `View.tag(_:)` in SwiftUI files.
/// Held locally because the ids are all a photo or milestone carries; without the matching name and colour a record's tags render as nothing.
@Model
final class FamilyTag {
    var id: UUID
    var remoteId: String?
    var name: String

    /// The hex string the web wrote, e.g. `#4A90D9`. Never validated server-side, so it can be empty or malformed; `TagColor` falls back rather than refusing to draw.
    var colorHex: String

    /// The owning family. Not used for filtering: `ListTags` already returns only what the user can see.
    var familyId: Int

    init(name: String, colorHex: String, familyId: Int) {
        self.id = UUID()
        self.remoteId = nil
        self.name = name
        self.colorHex = colorHex
        self.familyId = familyId
    }
}
