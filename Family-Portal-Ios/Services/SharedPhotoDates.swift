import CryptoKit
import Foundation
import ImageIO
import Photos

/// Recovers dates Photos keeps in its library for shares that arrived without a capture date.
nonisolated enum SharedPhotoDates {
    // Read a bounded number of local resources per share, even in a large library.
    private static let candidateLimit = 64

    @concurrent
    static func resolve(_ files: [URL]) async -> [URL: Date] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard !files.isEmpty, status == .authorized || status == .limited else { return [:] }

        var dates: [URL: Date] = [:]
        var matchesBySize: [Size: Matches] = [:]
        var remaining = candidateLimit
        for file in files {
            guard !Task.isCancelled else { break }
            // Older inbox entries may still carry an embedded date.
            guard CaptureDate.from(fileURL: file) == nil,
                  let size = Size(file),
                  let digest = digest(of: file) else { continue }
            if matchesBySize[size] == nil {
                let assets = size.fetchCandidates(limit: remaining + 1)
                if assets.count > remaining {
                    matchesBySize[size] = Matches()
                } else {
                    remaining -= assets.count
                    matchesBySize[size] = await readMatches(in: assets)
                }
            }
            dates[file] = matchesBySize[size]?.date(for: digest)
        }
        return dates
    }

    private static func readMatches(in assets: PHFetchResult<PHAsset>) async -> Matches {
        var matches = Matches()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false

        for index in 0..<assets.count {
            guard !Task.isCancelled else { return Matches() }
            let asset = assets.object(at: index)
            // A Live Photo has a separate paired video; only compare the still image.
            guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo })
            else { continue }
            defer { try? FileManager.default.removeItem(at: scratch) }
            do {
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: scratch, options: options)
                if let digest = digest(of: scratch) {
                    matches.add(digest, date: asset.creationDate)
                }
            } catch {
                // An original may only be available in iCloud. Continue with local originals.
                continue
            }
        }
        return matches
    }

    private static func digest(of url: URL) -> SHA256.Digest? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return SHA256.hash(data: data)
    }

    struct Matches {
        private var dates: [SHA256.Digest: Date] = [:]
        private var conflicts: Set<SHA256.Digest> = []

        mutating func add(_ digest: SHA256.Digest, date: Date?) {
            guard let date else {
                conflicts.insert(digest)
                return
            }
            if let previous = dates.updateValue(date, forKey: digest), previous != date {
                conflicts.insert(digest)
            }
        }

        func date(for digest: SHA256.Digest) -> Date? {
            conflicts.contains(digest) ? nil : dates[digest]
        }
    }

    private struct Size: Hashable {
        let shortSide: Int
        let longSide: Int

        init?(_ file: URL) {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
            shortSide = min(width, height)
            longSide = max(width, height)
        }

        func fetchCandidates(limit: Int) -> PHFetchResult<PHAsset> {
            let options = PHFetchOptions()
            // PhotoKit's dimensions may reflect orientation, unlike the encoded file.
            options.predicate = NSPredicate(
                format: "(pixelWidth == %@ AND pixelHeight == %@) OR (pixelWidth == %@ AND pixelHeight == %@)",
                argumentArray: [shortSide, longSide, longSide, shortSide]
            )
            options.fetchLimit = limit
            return PHAsset.fetchAssets(with: .image, options: options)
        }
    }
}
