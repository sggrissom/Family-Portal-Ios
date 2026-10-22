import SwiftUI

/// The play mark on a video's poster, with its length when the server knows it — the web's `VideoBadge`. Drawn over the thumbnail, so it carries its own dark backing to read on any frame.
struct VideoBadge: View {
    let durationMs: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill")
            if durationMs > 0 {
                Text(VideoDuration.format(milliseconds: durationMs))
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(durationMs > 0 ? Copy.video.badgeLabel(VideoDuration.format(milliseconds: durationMs)) : Copy.video.badge)
    }
}

extension Photo {
    /// What a thumbnail needs to badge this as a video, or nil for a photo.
    var videoBadgeDuration: Int? { isVideo ? durationMs : nil }
}
