import SwiftUI

/// The import's progress as a bottom `safeAreaInset`, not the full-screen overlay it replaced: photos land in the grid as they are read, and blocking the screen hid the one thing that showed the import working.
/// In `Components` because every host of the quick-add menu shows the same bar.
struct PhotoImportProgressBar: View {
    let progress: PhotoImporter.ImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.footnote)
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }
            ProgressView(value: Double(progress.settled), total: Double(max(progress.total, 1)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var label: String {
        progress.total == 1
            ? "Adding photo…"
            : "Adding photo \(min(progress.settled + 1, progress.total)) of \(progress.total)…"
    }
}
