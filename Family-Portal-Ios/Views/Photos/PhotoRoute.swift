import Foundation

struct PhotoRoute: Hashable {
    let id: UUID
    /// The person whose page the photo was opened from — the anchor for its Same age strip.
    var openedFrom: UUID? = nil
    /// For a video: where to start, in milliseconds — the web's `?t=`, from a search match or a face's frame.
    var startMs: Int = 0
}
