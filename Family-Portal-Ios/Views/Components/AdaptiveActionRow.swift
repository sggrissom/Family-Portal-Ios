import SwiftUI

/// Keep related actions together without squeezing their labels to fit a row.
struct AdaptiveActionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                content
            }
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}
