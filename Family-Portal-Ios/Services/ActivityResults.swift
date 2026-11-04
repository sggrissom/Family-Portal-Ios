import Foundation

/// Ports of `frontend/lib/activityResults.ts`, so the app and the web sum up a performance in the same words.
nonisolated enum ActivityResults {

    /// A new dance program has no adjudications of its own yet.
    static let danceAdjudications = ["Platinum", "High Gold", "Gold"]

    /// The adjudications offered as one-tap rows: the family's own, else the common dance ones, else none.
    static func quickLabels(kind: String, used: [String]) -> [String] {
        let labels = used.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !labels.isEmpty { return Array(labels.prefix(6)) }
        return kind == ActivityKind.dance ? danceAdjudications : []
    }
}
