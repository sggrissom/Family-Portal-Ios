import Foundation
import SwiftData

/// One label in a family's own vocabulary — `Tag` in backend/tags.go.
///
/// Named `FamilyTag` rather than `Tag` because the chips that render it live in
/// SwiftUI files, where a bare `Tag` sits next to `View.tag(_:)` and the
/// selection tags of `Picker` and `TabView`; the longer name is also literally
/// true, since a tag belongs to exactly one family and `UpdatePhotoTags` refuses
/// a tag from any other.
///
/// Held locally rather than fetched per screen because the ids are all a photo
/// or milestone carries: `Photo.tagRemoteIds` renders as nothing at all without
/// the matching name and colour, and an offline launch has to show the same
/// pills as an online one.
@Model
final class FamilyTag {
    var id: UUID
    var remoteId: String?
    var name: String

    /// The hex string the web's colour input wrote, e.g. `#4A90D9`. Stored as
    /// the server sent it — `CreateTag` validates the name but never the colour,
    /// so this can be empty or malformed — and interpreted for display by
    /// `TagColor`, which falls back rather than refusing to draw the tag.
    var colorHex: String

    /// The owning family. Not used for filtering: `ListTags` already returns
    /// only what the user can see, including the tags of families that shared
    /// people in, and a photo can carry a tag from either.
    var familyId: Int

    init(name: String, colorHex: String, familyId: Int) {
        self.id = UUID()
        self.remoteId = nil
        self.name = name
        self.colorHex = colorHex
        self.familyId = familyId
    }
}
