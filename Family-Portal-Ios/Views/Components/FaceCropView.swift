import SwiftUI

/// Where to cut a face out of its photo: a square (in pixels) around the face box, padded by `padding` of the box's size on each side, as fractions of the photo. A port of the web's `faceCropLayout`, except that the web stretches the image to fit a square and this keeps its proportions.
nonisolated enum FaceCropLayout {
    static func cropRect(box: FaceBoxDTO, imageSize: CGSize, padding: Double = 0.35) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let faceWidth = (box.right - box.left) * imageSize.width
        let faceHeight = (box.bottom - box.top) * imageSize.height
        let side = max(faceWidth, faceHeight) * (1 + 2 * padding)
        let centerX = (box.left + box.right) / 2 * imageSize.width
        let centerY = (box.top + box.bottom) / 2 * imageSize.height
        return CGRect(
            x: (centerX - side / 2) / imageSize.width,
            y: (centerY - side / 2) / imageSize.height,
            width: side / imageSize.width,
            height: side / imageSize.height
        )
    }
}

/// A square crop of one face from a server photo — the web's `FaceCrop`. It loads the medium size so a small face stays sharp; a photo with no face box falls back to the plain thumbnail.
struct FaceCropView: View {
    let photoId: Int
    let box: FaceBoxDTO
    /// For a face from a video: the frame its box is relative to. The poster would put the box in the wrong place.
    var frameMs: Int? = nil
    var size: CGFloat = 88

    @State private var image: UIImage?

    var body: some View {
        Group {
            if !box.hasArea {
                RemotePhotoView(remoteId: photoId, size: .thumb)
            } else if let image {
                cropped(image)
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        // Clipping only limits drawing. The enlarged, offset image must not
        // receive taps outside the visible crop (including controls above it).
        .contentShape(Rectangle())
        .task(id: "\(photoId)-\(frameMs ?? -1)") {
            guard box.hasArea else { return }
            let cache = PhotoImageCache.shared
            if let frameMs {
                if let cached = cache.cachedFrame(remoteId: photoId, frameMs: frameMs) {
                    image = cached
                } else if case .image(let loaded) = await cache.frame(remoteId: photoId, frameMs: frameMs) {
                    image = loaded
                }
                return
            }
            if let cached = cache.cachedImage(remoteId: photoId, size: .medium) {
                image = cached
                return
            }
            if case .image(let loaded) = await cache.image(remoteId: photoId, size: .medium) {
                image = loaded
            }
        }
    }

    private func cropped(_ image: UIImage) -> some View {
        let rect = FaceCropLayout.cropRect(box: box, imageSize: image.size)
        let width = size / rect.width
        let height = size / rect.height
        return Image(uiImage: image)
            .resizable()
            .frame(width: width, height: height)
            .offset(x: -rect.minX * width, y: -rect.minY * height)
            .frame(width: size, height: size, alignment: .topLeading)
    }
}
