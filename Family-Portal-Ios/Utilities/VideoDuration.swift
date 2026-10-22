import Foundation

/// A video's length as the play badge shows it: `m:ss`, or `h:mm:ss` from an hour. A port of `formatDuration` in frontend/lib/videoFiles.ts, so both clients print the same thing.
nonisolated enum VideoDuration {
    static func format(milliseconds: Int) -> String {
        let total = max(0, Int((Double(milliseconds) / 1000).rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
