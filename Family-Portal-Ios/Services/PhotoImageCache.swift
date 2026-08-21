import Foundation
import OSLog
import UIKit

/// Fetches a photo variant once and keeps it.
///
/// `RemotePhotoView` used to issue a fresh authenticated `URLSession` request
/// every time it appeared. A photo grid re-downloaded its whole page on every
/// scroll back, an avatar re-downloaded itself in every row it appeared in, and
/// the same bytes crossed the network dozens of times per session. The server
/// bounds that at 600 photo reads per five minutes — a limit a real gallery can
/// reach, entirely on repeats.
///
/// Two layers, because they solve different halves:
///
///   - A `URLCache` on this class's own session honors the server's headers.
///     Photo responses are `private, max-age=300, must-revalidate` with an ETag
///     covering id, variant, creation time and processing status, so five
///     minutes of free reuse are followed by a conditional request that returns
///     304 for an unchanged photo and fresh bytes for a reprocessed one. Getting
///     this from HTTP rather than from a hand-rolled expiry is why a reprocessed
///     photo cannot go stale here.
///   - An `NSCache` of decoded images on top, because the expensive part of
///     showing the same thumbnail again is decoding it, not fetching it. It is
///     memory-only and evicted under pressure.
///
/// Requests for the same variant are coalesced: a grid that scrolls a cell in
/// and out and back in again does not start three downloads for one image.
@MainActor
final class PhotoImageCache {

    static let shared = PhotoImageCache()

    /// What a fetch produced. `processing` is not a failure and is deliberately
    /// distinct from `unavailable`: it is the one outcome worth asking about
    /// again.
    enum Outcome {
        case image(UIImage)
        /// The server is still generating this photo's variants and answered
        /// with its placeholder. Ask again shortly.
        case processing
        /// Gone, forbidden, undecodable, or the network is down. Asking again
        /// will not help until something else changes.
        case unavailable
    }

    private let apiClient: APIClient
    private let session: URLSession
    /// Held directly rather than reached through `session.configuration`, which
    /// hands back a copy of the configuration on every access.
    private let httpCache: URLCache?
    private let decoded = NSCache<NSString, UIImage>()

    /// One task per key while a fetch is in flight, so N simultaneous askers
    /// share one download. `Task<Void, Never>` rather than a task carrying the
    /// outcome: the result is read back from `decoded` and `lastOutcome` below,
    /// which keeps a `UIImage` from having to cross an isolation boundary it has
    /// no business crossing.
    private var inFlight: [String: Task<Void, Never>] = [:]

    /// What the last completed fetch for a key produced, for the outcomes that
    /// leave nothing in `decoded` — a photo still processing, or one that could
    /// not be fetched. Bounded, and dropped wholesale by `removeAll`.
    private var lastOutcome: [String: Outcome] = [:]
    private static let maxRememberedOutcomes = 512

    /// `session` is injectable for the same reason `APIClient`'s is: a test
    /// needs to answer these requests without a network and without touching
    /// the app's real cache directory.
    init(apiClient: APIClient = .shared, session: URLSession? = nil) {
        self.apiClient = apiClient
        let session = session ?? Self.makeSession()
        self.session = session
        self.httpCache = session.configuration.urlCache

        // Roughly forty full-screen images, or several hundred thumbnails.
        // NSCache evicts under memory pressure regardless; this keeps it from
        // growing without bound on a long gallery scroll in the meantime.
        decoded.totalCostLimit = 64 * 1024 * 1024
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            directory: cacheDirectory()
        )
        // The point of the whole arrangement: obey what the server said about
        // freshness rather than inventing a policy here.
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }

    private static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PhotoImages", isDirectory: true)
    }

    // MARK: - Reads

    /// The decoded image if one is already in memory. Synchronous, so a view can
    /// render a cached thumbnail in its first layout pass instead of flashing a
    /// spinner.
    func cachedImage(remoteId: Int, size: PhotoSizeVariant) -> UIImage? {
        decoded.object(forKey: Self.key(remoteId, size) as NSString)
    }

    /// Fetches the variant, or joins the fetch already running for it.
    func image(remoteId: Int, size: PhotoSizeVariant) async -> Outcome {
        let key = Self.key(remoteId, size)
        if let cached = decoded.object(forKey: key as NSString) {
            return .image(cached)
        }

        if let existing = inFlight[key] {
            await existing.value
        } else {
            // A previous failure must not answer this ask. A photo that failed
            // once in a lift has to be able to load when the signal comes back.
            lastOutcome[key] = nil

            let task = Task { [self] in
                let outcome = await load(remoteId: remoteId, size: size)
                if case .image(let image) = outcome {
                    decoded.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
                } else {
                    // Deliberately not cached: a processing placeholder is worth
                    // asking about again, and so is a photo that failed to
                    // arrive. This dictionary is how the awaiters find out
                    // which, not a cache of the answer.
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
            // These exist only to be read back by the askers waiting on the task
            // that just finished. Dropping the lot costs at most a redundant
            // fetch, and keeps a long session from accumulating a row per photo
            // the user scrolled past while offline.
            lastOutcome.removeAll(keepingCapacity: true)
        }
        lastOutcome[key] = outcome
    }

    // MARK: - Invalidation

    /// Drops every cached image and the HTTP cache under it.
    ///
    /// `LocalDataReset.erase(.everything)` calls this. Without it a device that
    /// changes hands could still answer from cache for up to the five minutes
    /// the server allowed — the new account cannot reach the old account's
    /// photos on the server, but this cache does not know that, because it
    /// caches by photo id and photo ids are global.
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

    /// Bytes the decoded bitmap occupies, which is what `totalCostLimit` counts.
    /// Falls back to a nominal value for an image with no backing bitmap rather
    /// than reporting zero, which would make it free to keep forever.
    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1024 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private func load(remoteId: Int, size: PhotoSizeVariant) async -> Outcome {
        let service = PhotoSyncService(apiClient: apiClient)
        guard let url = await service.photoURL(remoteId: remoteId, size: size) else {
            return .unavailable
        }

        // Photos are fetched with the raw token rather than through
        // `APIClient.request`, so they get neither its proactive refresh nor its
        // retry-on-401 unless asked for both here. Without the refresh, a
        // session that crosses the JWT expiry while the app stays foregrounded
        // renders every photo as a placeholder until the next relaunch.
        await apiClient.ensureFreshAccessToken()

        var outcome = await fetch(url)
        if case .unauthorized = outcome {
            // A 401 despite the check above means the token went stale inside
            // the margin. One forced refresh and retry, mirroring
            // `retryOnAuthFailure`.
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
        // The server negotiates format from Accept and varies on it. Sending a
        // constant value keeps the cache from splitting into one entry per
        // header the system happens to send.
        request.setValue("image/webp,image/jpeg,*/*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .failed }

            if httpResponse.statusCode == 401 { return .unauthorized }
            guard (200...299).contains(httpResponse.statusCode) else { return .failed }

            // A photo whose variants have not been generated yet answers 200
            // with an animated SVG placeholder, not with the photo. Treating
            // that as a failure is what left a freshly uploaded photo showing a
            // broken-image glyph forever: `UIImage(data:)` cannot read SVG, the
            // view cached the failure, and nothing ever asked again.
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            if contentType.hasPrefix("image/svg") { return .processing }

            guard let image = UIImage(data: data) else { return .failed }
            // Decoding is the expensive half of showing a thumbnail, and doing
            // it lazily means it lands on the main thread during a scroll.
            return .decoded(await image.byPreparingForDisplay() ?? image)
        } catch {
            AppLog.ui.error(
                "Photo fetch failed: \(String(describing: error), privacy: .public)"
            )
            return .failed
        }
    }
}
