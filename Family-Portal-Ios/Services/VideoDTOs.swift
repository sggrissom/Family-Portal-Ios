import Foundation

// Video (backend/video_uploads.go, backend/video_playback.go, backend/video_transcripts.go; the contract is docs/mobile-api.md § Video upload and Video playback). A video is an `ImageDTO` with `mediaKind` 1; these are only the procs that move its bytes. Every optional field reads as empty when missing.

/// The server's refusals that change what the client does next, worded exactly as backend/video_uploads.go words them.
nonisolated enum VideoUploadRefusal {
    static let disabled = "Video uploads are not turned on for this family."
    static let unavailable = "Video uploads are not available on this server right now."
    static let notFound = "That upload could not be found."
    /// Start again from `BeginVideoUpload`.
    static let expired = "This upload expired before it finished. Please try again."
    /// The bytes have not arrived: send them again, then complete.
    static let missing = "The video hasn't finished uploading yet."
}

nonisolated struct GetVideoSupportRequestDTO: Encodable, Sendable {
    /// 0 lets the server pick the caller's primary family.
    var familyId: Int = 0
}

/// Whether video can be added to a family, and the limits to check before starting. Video is off per family until an admin turns it on.
nonisolated struct GetVideoSupportResponseDTO: Decodable, Sendable, Equatable {
    @OrZero var enabled: Bool
    /// Why it is off, worded for showing as is.
    @OrZero var reason: String
    @OrZero var maxBytes: Int
    @OrZero var maxDurationSeconds: Int
    @OrZero var contentTypes: [String]
}

nonisolated struct BeginVideoUploadRequestDTO: Encodable, Sendable {
    var familyId: Int = 0
    let personIds: [Int]
    let filename: String
    /// `video/mp4`, `video/quicktime` or `video/x-m4v`.
    let contentType: String
    /// The exact byte count that will be sent.
    let size: Int
    var title: String = ""
    var description: String = ""
    /// The local day (`yyyy-MM-dd`) the video is dated when the file carries no creation date of its own.
    let fallbackDate: String
}

/// How to send the bytes: this method, these headers and no others, the raw file as the body, and **no** bearer token or cookies — the URL carries its own authority. A `url` starting with `/` is relative to the API origin.
nonisolated struct UploadInstructionsDTO: Decodable, Sendable, Equatable {
    let url: String
    let method: String
    @OrZero var headers: [String: String]
    let expiresAt: Date
}

nonisolated struct BeginVideoUploadResponseDTO: Decodable, Sendable {
    let uploadId: Int
    let upload: UploadInstructionsDTO
}

nonisolated struct VideoUploadIdRequestDTO: Encodable, Sendable {
    let uploadId: Int
}

/// Completion is idempotent: asking again answers with the same image rather than another one.
nonisolated struct CompleteVideoUploadResponseDTO: Decodable, Sendable {
    let image: ImageDTO
}

nonisolated struct GetVideoPlaybackRequestDTO: Encodable, Sendable {
    let id: Int
}

/// A viewing session's links, minted per request and never to be stored. Both last about six hours; ask again when one is refused.
nonisolated struct GetVideoPlaybackResponseDTO: Decodable, Sendable, Equatable {
    /// 0 ready, 1 processing, 2 failed.
    let status: Int
    /// Set only when `status` is 0: a progressive MP4 with its index at the front, which streams and seeks by range requests.
    @OrZero var playbackUrl: String
    /// With codecs, e.g. `video/mp4; codecs="hvc1.1.6.L93.B0, mp4a.40.2"`.
    @OrZero var mimeType: String
    /// The untouched original. Present whenever it is still kept, including for a video that failed processing; absent for one that was rejected.
    @OrZero var downloadUrl: String
    @OrZero var originalFilename: String
    var expiresAt: Date? = nil
    @OrZero var processingError: String
}

nonisolated struct GetVideoTranscriptRequestDTO: Encodable, Sendable {
    let id: Int
}

/// What was said in a video, line by line, from the server's speech worker or as a family member fixed it.
nonisolated struct GetVideoTranscriptResponseDTO: Decodable, Sendable, Equatable {
    /// backend/video_transcripts.go `TranscriptStatus`. Only `done` carries lines.
    enum Status {
        static let done = 0
        static let noSpeech = 1
        static let failed = 2
        static let removed = 3
    }

    /// Whether this server transcribes at all.
    @OrZero var available: Bool
    @OrZero var status: Int
    /// Not transcribed yet, and it will be.
    @OrZero var pending: Bool
    /// From the speech worker rather than fixed by hand, so it may hold mistakes.
    @OrZero var automatic: Bool
    @OrZero var language: String
    @OrZero var segments: [TranscriptSegmentDTO]
}

nonisolated struct TranscriptSegmentDTO: Decodable, Sendable, Equatable {
    let startMs: Int
    let endMs: Int
    let text: String
    /// 0–1 for an automatic line; meaningless once edited.
    @OrZero var confidence: Double
}

/// The transcript's pure parts, ported from frontend/components/VideoTranscript.tsx.
nonisolated enum VideoTranscript {
    /// Below this an automatic line is shown as unsure (`LOW_CONFIDENCE`).
    static let lowConfidence = 0.5

    /// The line playing at `seconds`, or nil between lines (`currentSegment`).
    static func currentSegment(_ segments: [TranscriptSegmentDTO], seconds: Double) -> Int? {
        let ms = seconds * 1000
        return segments.firstIndex { ms >= Double($0.startMs) && ms < Double($0.endMs) }
    }
}
