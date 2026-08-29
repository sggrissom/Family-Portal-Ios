import SwiftUI

/// Turns a `FamilyTag.colorHex` into something drawable.
/// The colour is never validated server-side, so an empty string or an outright typo reaches the phone; a malformed value falls back to a neutral swatch rather than dropping the chip.
nonisolated enum TagColor {

    static let fallback = Color.secondary

    static func color(forHex hex: String) -> Color {
        guard let components = components(forHex: hex) else { return fallback }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    /// The parse itself, kept separate from `Color` so it can be asserted on without rendering. Accepts `#RRGGBB` and the three-digit shorthand, with or without the `#`.
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
