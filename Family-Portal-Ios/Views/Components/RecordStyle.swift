import SwiftUI

/// The glyph and tint a milestone category or a measurement type is drawn with, wherever it appears — a list row, a timeline row, a detail sheet.
/// One copy, because the same two switches had grown independently in three views and had already started to drift.

extension MilestoneCategory {
    var icon: String {
        switch self {
        case .development: "leaf.fill"
        case .behavior: "face.smiling.fill"
        case .health: "heart.fill"
        case .achievement: "trophy.fill"
        case .first: "star.fill"
        case .other: "note.text"
        }
    }

    var color: Color {
        switch self {
        case .development: .green
        case .behavior: .orange
        case .health: .red
        case .achievement: .yellow
        case .first: .purple
        case .other: .gray
        }
    }

    var label: String { rawValue.capitalized }
}

extension MeasurementType {
    var icon: String {
        switch self {
        case .height: "ruler"
        case .weight: "scalemass"
        }
    }

    var color: Color {
        switch self {
        case .height: .blue
        case .weight: .teal
        }
    }

    var label: String { rawValue.capitalized }
}
