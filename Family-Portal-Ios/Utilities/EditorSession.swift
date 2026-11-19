import Foundation

/// One presentation of an editor sheet, held in the editor's `@State` so every opening — including another opening of the same routine — gets its own.
/// A write outlives the sheet that started it: Cancel closes the editor at once, but the request keeps going and the server may still commit it. The sheet's `dismiss` is not tied to the presentation that captured it — called late, it closes whichever sheet now fills the same slot. So a completion dismisses only through `finish`, which does nothing once this presentation has been closed.
@MainActor
final class EditorSession {

    private(set) var isOpen = true

    /// The person closed this editor themselves; anything still running for it must leave the screen alone.
    func close() {
        isOpen = false
    }

    /// Closes the editor with `dismiss` when it is still this presentation on screen. Returns whether it did, so a caller can skip UI updates for an editor that is already gone.
    @discardableResult
    func finish(_ dismiss: () -> Void) -> Bool {
        guard isOpen else { return false }
        isOpen = false
        dismiss()
        return true
    }
}
