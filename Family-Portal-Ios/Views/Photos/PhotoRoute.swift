import Foundation

struct PhotoRoute: Hashable {
    let id: UUID
    /// The person whose page the photo was opened from — the anchor for its Same age strip.
    var openedFrom: UUID? = nil
}
