import SwiftUI

struct PhotoThumbnailView: View {
    let imageData: Data?
    let title: String
    var remoteId: String? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
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
                    // Drawn over the image, which is already labelled with the
                    // same words. Left visible it would be announced twice.
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // One element, so a grid reads as a list of photos rather than as a
        // stack of layers per cell.
        .accessibilityElement(children: .combine)
    }
}
