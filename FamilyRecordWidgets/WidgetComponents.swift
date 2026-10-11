import SwiftUI
import UIKit
import WidgetKit

/// A snapshot image, read from the App Group. It was downsampled by the app, so loading it whole stays inside the extension's memory limit.
struct SnapshotImage: View {
    let file: String?

    var body: some View {
        if let image = Self.load(file) {
            // Tinted rendering would otherwise draw a photo as a solid silhouette.
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFill()
        } else {
            Rectangle().fill(.quaternary)
        }
    }

    static func load(_ file: String?) -> UIImage? {
        guard let file, let store = WidgetStore.shared() else { return nil }
        return UIImage(contentsOfFile: store.imageURL(file).path)
    }
}

/// A picture filling its frame, cropped rather than letterboxed.
struct FilledImage: View {
    let file: String?

    var body: some View {
        GeometryReader { proxy in
            SnapshotImage(file: file)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }
}

/// The SF Symbol for an item that has only words.
extension WidgetItem.Kind {
    var symbol: String {
        switch self {
        case .photo: "photo"
        case .milestone: "star.fill"
        case .quote: "quote.opening"
        case .artwork: "paintpalette.fill"
        }
    }
}

/// The signed-out and empty states every size shares.
struct WidgetMessage: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Spacer(minLength: 0)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
