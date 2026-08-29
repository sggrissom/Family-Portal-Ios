import Foundation
import OSLog
import UIKit

/// Two layers: a `URLCache` on this class's own session, which honors the server's ETag and `max-age` so a reprocessed photo cannot go stale, and an `NSCache` of decoded images on top, since decoding is the expensive half. Requests for the same variant are coalesced.
@MainActor
final class PhotoImageCache {

    static let shared = PhotoImageCache()

    /// What a fetch produced. `processing` is not a failure, and is the one outcome worth asking about again.
    enum Outcome {
        case image(UIImage)
        case processing
        case unavailable
    }

    private let apiClient: APIClient
    private let session: URLSession
    /// Held directly rather than through `session.configuration`, which hands back a copy on every access.
    private let httpCache: URLCache?
    private let decoded = NSCache<NSString, UIImage>()

    /// One task per key while a fetch is in flight, so N askers share one download. The outcome is read back from `decoded` and `lastOutcome` rather than carried, keeping `UIImage` off an isolation boundary.
    private var inFlight: [String: Task<Void, Never>] = [:]

    private var lastOutcome: [String: Outcome] = [:]
    private static let maxRememberedOutcomes = 512

    init(apiClient: APIClient = .shared, session: URLSession? = nil) {
        self.apiClient = apiClient
        let session = session ?? Self.makeSession()
        self.session = session
        self.httpCache = session.configuration.urlCache

        decoded.totalCostLimit = 64 * 1024 * 1024
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            directory: cacheDirectory()
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }

    private static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PhotoImages", isDirectory: true)
    }

    // MARK: - Reads

    func cachedImage(remoteId: Int, size: PhotoSizeVariant) -> UIImage? {
        decoded.object(forKey: Self.key(remoteId, size) as NSString)
    }

    func image(remoteId: Int, size: PhotoSizeVariant) async -> Outcome {
        let key = Self.key(remoteId, size)
        if let cached = decoded.object(forKey: key as NSString) {
            return .image(cached)
        }

        if let existing = inFlight[key] {
            await existing.value
        } else {
            // A previous failure must not answer this ask: a photo that failed in a lift has to load when the signal comes back.
            lastOutcome[key] = nil

            let task = Task { [self] in
                let outcome = await load(remoteId: remoteId, size: size)
                if case .image(let image) = outcome {
                    decoded.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
                } else {
                    // Deliberately not cached: a processing placeholder is worth asking about again, and so is a photo that failed to arrive.
                    rememberOutcome(outcome, for: key)
                }
                inFlight[key] = nil
            }
            inFlight[key] = task
            await task.value
        }

        if let image = decoded.object(forKey: key as NSString) {
            return .image(image)
        }
        return lastOutcome[key] ?? .unavailable
    }

    private func rememberOutcome(_ outcome: Outcome, for key: String) {
        if lastOutcome.count >= Self.maxRememberedOutcomes {
            lastOutcome.removeAll(keepingCapacity: true)
        }
        lastOutcome[key] = outcome
    }

    // MARK: - Invalidation

    func removeAll() {
        decoded.removeAllObjects()
        lastOutcome.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        httpCache?.removeAllCachedResponses()
    }

    // MARK: - Internals

    private static func key(_ remoteId: Int, _ size: PhotoSizeVariant) -> String {
        "\(remoteId)-\(size.rawValue)"
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1024 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private func load(remoteId: Int, size: PhotoSizeVariant) async -> Outcome {
        let service = PhotoSyncService(apiClient: apiClient)
        guard let url = await service.photoURL(remoteId: remoteId, size: size) else {
            return .unavailable
        }

        // Photos are fetched with the raw token rather than through `APIClient.request`, so the proactive refresh and the retry-on-401 have to be asked for here.
        await apiClient.ensureFreshAccessToken()

        var outcome = await fetch(url)
        if case .unauthorized = outcome {
            // A 401 despite the check above means the token went stale inside the margin. One forced refresh and retry.
            try? await apiClient.refreshAccessToken()
            outcome = await fetch(url)
        }

        switch outcome {
        case .decoded(let image):
            return .image(image)
        case .processing:
            return .processing
        case .unauthorized, .failed:
            return .unavailable
        }
    }

    private enum FetchOutcome {
        case decoded(UIImage)
        case processing
        case unauthorized
        case failed
    }

    private func fetch(_ url: URL) async -> FetchOutcome {
        var request = URLRequest(url: url)
        if let token = await apiClient.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // The server varies on Accept, so send a constant value rather than splitting the cache per header the system happens to send.
        request.setValue("image/webp,image/jpeg,*/*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failed }

            if httpResponse.statusCode == 401 { return .unauthorized }
            guard (200...299).contains(httpResponse.statusCode) else { return .failed }

            // A photo whose variants are not generated yet answers 200 with an animated SVG placeholder. `UIImage(data:)` cannot read SVG, so this is not a failure to cache.
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            if contentType.hasPrefix("image/svg") { return .processing }

            guard let image = UIImage(data: data) else { return .failed }
            return .decoded(await image.byPreparingForDisplay() ?? image)
        } catch {
            AppLog.ui.error(
                "Photo fetch failed: \(String(describing: error), privacy: .public)"
            )
            return .failed
        }
    }
}
