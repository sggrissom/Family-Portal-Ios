import Foundation
import ImageIO
import OSLog
import Photos
import UIKit
import Vision

/// The library finder's reads from PhotoKit and Vision. Everything here happens on the device: thumbnails are read, looked at and dropped, and nothing is sent anywhere.
/// The decisions — moments, sampling, scoring — are `LibraryFinder`'s.
nonisolated enum LibraryScanner {

    /// The earliest photo's date, so ages from before the library begins aren't offered.
    @concurrent
    static func libraryStart() async -> Date? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 1
        return PHAsset.fetchAssets(with: .image, options: options).firstObject?.creationDate?.localWallClock()
    }

    /// The library's photos inside `window`, oldest first. Screenshots are left out; a burst is already one asset, since PhotoKit returns only its pick.
    /// The fetch is widened by a day on each side because PhotoKit compares instants, and the window is in wall-clock time; the exact cut is made after converting.
    @concurrent
    static func assets(in window: LibraryFinder.AgeWindow) async -> [LibraryFinder.Asset] {
        let day: TimeInterval = 86_400
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            window.from.addingTimeInterval(-day) as NSDate,
            window.to.addingTimeInterval(day) as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)

        var assets: [LibraryFinder.Asset] = []
        assets.reserveCapacity(result.count)
        for index in 0..<result.count {
            let asset = result.object(at: index)
            guard !asset.mediaSubtypes.contains(.photoScreenshot), let created = asset.creationDate else { continue }
            let date = created.localWallClock()
            guard date >= window.from, date < window.to else { continue }
            assets.append(LibraryFinder.Asset(
                id: asset.localIdentifier,
                date: date,
                isFavorite: asset.isFavorite,
                latitude: asset.location?.coordinate.latitude,
                longitude: asset.location?.coordinate.longitude
            ))
        }
        return assets
    }

    /// How many library photos fall in `window`: a count PhotoKit answers without loading them, so the ages list can show every window's. Screenshots are counted too — leaving them out would mean reading each asset.
    @concurrent
    static func count(in window: LibraryFinder.AgeWindow) async -> Int {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            LibraryFinder.instant(fromWallClock: window.from) as NSDate,
            LibraryFinder.instant(fromWallClock: window.to) as NSDate
        )
        return PHAsset.fetchAssets(with: .image, options: options).count
    }

    /// Faces and aesthetics for one photo, from a small thumbnail. Nil when the photo can't be read, which the finder treats as not worth suggesting.
    @concurrent
    static func analyze(_ assetId: String) async -> LibraryFinder.Analysis? {
        guard let image = await thumbnail(assetId, side: 512), let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        var analysis = LibraryFinder.Analysis()

        // Detection only: Vision finds where faces are and how well each was captured. Nothing identifies anyone.
        let rectangles = VNDetectFaceRectanglesRequest()
        let quality = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        do {
            try handler.perform([rectangles])
            let faces = rectangles.results ?? []
            analysis.faceCount = faces.count
            analysis.largestFaceArea = faces.map { Float($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
            if !faces.isEmpty {
                quality.inputFaceObservations = faces
                try handler.perform([quality])
                analysis.bestFaceQuality = (quality.results ?? []).compactMap(\.faceCaptureQuality).max() ?? 0
            }
        } catch {
            AppLog.ui.error("Face detection failed: \(String(describing: error), privacy: .public)")
        }

        if let scores = try? await CalculateImageAestheticsScoresRequest().perform(on: cgImage, orientation: orientation) {
            analysis.aesthetics = scores.overallScore
            analysis.isUtility = scores.isUtility
        }
        return analysis
    }

    /// A square-bounded thumbnail of a library photo. Allowed to come from iCloud: small renditions download quickly, and a library on "Optimize Storage" keeps few originals.
    @concurrent
    static func thumbnail(_ assetId: String, side: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        // One callback, not a degraded one first, so the continuation resumes exactly once.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// A library photo's original bytes, as stored (often HEIC), and its date in Photos. Nil when it can't be read — usually an iCloud original that wouldn't download.
    @concurrent
    static func original(_ assetId: String) async -> (data: Data, captureDate: Date?)? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let data: Data? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        return (data, asset.creationDate)
    }
}

private extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
