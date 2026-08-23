import SwiftUI

/// Shown instead of the whole app when the server reports `update_required`.
/// Deliberately offers no way past it — that's the point of the status.
struct UpdateRequiredView: View {
    @Environment(\.openURL) private var openURL
    let message: String
    let updateURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .accessibilityHidden(true)
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Update Required")
                .font(.title2.bold())

            Text(displayMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let updateURL {
                Button {
                    openURL(updateURL)
                } label: {
                    Text("Update Now")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayMessage: String {
        message.isEmpty
            ? "This version of \(AppConstants.appName) is no longer supported. Please update to continue."
            : message
    }
}

#Preview("With store link") {
    UpdateRequiredView(
        message: "",
        updateURL: URL(string: "https://apps.apple.com/app/id000000000")
    )
}

#Preview("Operator message, no link") {
    UpdateRequiredView(
        message: "We've moved to a new sync engine. Please grab the latest build from TestFlight.",
        updateURL: nil
    )
}
