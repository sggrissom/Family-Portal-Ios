import Foundation

/// What a player failure most likely means. A port of `classifyPlaybackError` in frontend/lib/videoPlayback.ts, with its test table.
nonisolated enum PlaybackProblem: Equatable, Sendable {
    /// The link lapsed or is refused: ask `GetVideoPlayback` for a new one and carry on from the same place.
    case expired
    /// The link still answers, so the file itself is what this device can't play.
    case unsupported
    /// Anything else: the connection.
    case network
}

nonisolated enum VideoPlayback {
    /// How close to `expiresAt` a failure counts as the link lapsing, without asking.
    static let expiryMargin: TimeInterval = 60
    /// Renewals in a row before a failure is shown rather than retried.
    static let maxRenewals = 3

    /// `isNetworkError` is the player's own reading (a URL-loading error underneath); `probeStatus` is a one-byte range request for the same link, `nil` when even that didn't answer.
    static func classify(isNetworkError: Bool, probeStatus: Int?, now: Date, expiresAt: Date?) -> PlaybackProblem {
        if let expiresAt, now >= expiresAt.addingTimeInterval(-expiryMargin) { return .expired }
        if let probeStatus, [400, 401, 403].contains(probeStatus) { return .expired }
        if let probeStatus, (200..<300).contains(probeStatus) {
            return isNetworkError ? .network : .unsupported
        }
        return .network
    }

    /// Whether an AVFoundation error has a URL-loading failure somewhere beneath it, which is what the web's `MEDIA_ERR_NETWORK` corresponds to.
    static func isNetworkError(_ error: Error?) -> Bool {
        var current = error.map { $0 as NSError }
        while let error = current {
            if error.domain == NSURLErrorDomain { return true }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
