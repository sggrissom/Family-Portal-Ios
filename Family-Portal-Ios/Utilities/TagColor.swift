import SwiftUI

/// Turns a `FamilyTag.colorHex` into something drawable.
///
/// The colour is whatever the web's `<input type="color">` wrote — `CreateTag`
/// and `UpdateTag` (backend/tags.go) validate the name and never the colour, so
/// an empty string, a legacy value or an outright typo all reach the phone. A
/// tag with an unreadable colour is still a tag the user put on the record, so
/// every malformed value falls back to a neutral swatch rather than dropping the
/// chip — the web does the same thing by handing the string straight to CSS and
/// letting an invalid one inherit.
nonisolated enum TagColor {

    /// What an empty or malformed hex string draws as.
    static let fallback = Color.secondary

    static func color(forHex hex: String) -> Color {
        guard let components = components(forHex: hex) else { return fallback }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    /// The parse itself, kept separate from `Color` so it can be asserted on
    /// without rendering anything.
    ///
    /// Accepts `#RRGGBB` and the three-digit `#RGB` shorthand, with or without
    /// the leading `#`, in either case. Anything else — including the `rgb(…)`
    /// and named-colour forms CSS would take — is a miss.
    static func components(forHex hex: String) -> (red: Double, green: Double, blue: Double)? {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }

        guard digits.count == 3 || digits.count == 6 else { return nil }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        // `#4a9` is `#44aa99`, the same expansion CSS applies.
        let expanded = digits.count == 3 ? String(digits.flatMap { [$0, $0] }) : digits
        guard let value = UInt32(expanded, radix: 16) else { return nil }

        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
