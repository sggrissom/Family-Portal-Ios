import SwiftUI

struct PhotoThumbnailView: View {
    let imageData: Data?
    let title: String
    var remoteId: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            if let imageData {
                LocalThumbnailImage(data: imageData)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .accessibilityLabel(title.isEmpty ? "Photo" : title)
            } else if let remoteId, let remoteInt = Int(remoteId) {
                RemotePhotoView(remoteId: remoteInt, size: .thumb)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .accessibilityLabel(title.isEmpty ? "Photo" : title)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Photo unavailable")
            }

            if !title.isEmpty {
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    // Drawn over the image, which is already labelled with the same words.
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // One element, so a grid reads as a list of photos rather than a stack of layers per cell.
        .accessibilityElement(children: .combine)
    }
}

/// A photo held as bytes locally — one picked but not yet uploaded — shrunk once to grid size. `UIImage(data:)` inside `body` would hand SwiftUI a full-resolution capture to decode on the main thread, and `body` runs again on every scroll, so a grid of fresh imports stutters.
private struct LocalThumbnailImage: View {
    let data: Data

    /// Generous enough for the widest cell on the largest screen at 3×, and still a fraction of a modern capture.
    private static let maxPixelSize: CGFloat = 600

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
            }
        }
        .task(id: data.count) {
            image = await Self.thumbnail(from: data)
        }
    }

    /// `byPreparingThumbnail` does the resize and the decode off the main thread. The target keeps the source's aspect ratio, since the caller crops to a square by filling rather than by squashing.
    private static func thumbnail(from data: Data) async -> UIImage? {
        guard let full = UIImage(data: data) else { return nil }

        let longestSide = max(full.size.width, full.size.height)
        guard longestSide > maxPixelSize, longestSide > 0 else {
            return await full.byPreparingForDisplay() ?? full
        }

        let ratio = maxPixelSize / longestSide
        let target = CGSize(width: full.size.width * ratio, height: full.size.height * ratio)
        return await full.byPreparingThumbnail(ofSize: target) ?? full
    }
}
