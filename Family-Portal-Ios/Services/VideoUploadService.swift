import Foundation
import OSLog

/// The video upload contract (docs/mobile-api.md § Video upload): begin, send the file exactly as instructed, complete. Online only and never queued — `BeginVideoUpload` reserves quota and hands out a URL that lapses in two hours, which a queue holding a gigabyte for later can't honour.
struct VideoUploadService {
    let apiClient: APIClient
    /// Before completion attempt `n` (from 1). Injected so tests don't wait.
    var retryDelay: @Sendable (Int) -> Duration = { .seconds($0) }

    static let completionAttempts = 4

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// Uploads one file and answers with the image the server made of it, still processing. People, a caption and tags are added afterwards, like a photo's.
    func upload(
        fileURL: URL,
        filename: String,
        contentType: String,
        size: Int,
        fallbackDate: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ImageDTO {
        let begun: BeginVideoUploadResponseDTO = try await apiClient.callRPC(.beginVideoUpload, payload: BeginVideoUploadRequestDTO(
            personIds: [],
            filename: filename,
            contentType: contentType,
            size: size,
            fallbackDate: fallbackDate
        ))

        do {
            try await apiClient.uploadMedia(fileURL: fileURL, instructions: begun.upload, progress: progress)
        } catch {
            // Releases the reservation now rather than when the session lapses. Best effort: the server sweeps it either way.
            let _: EmptyResponseDTO? = try? await apiClient.callRPC(.cancelVideoUpload, payload: VideoUploadIdRequestDTO(uploadId: begun.uploadId))
            throw error
        }

        return try await complete(uploadId: begun.uploadId)
    }

    /// Completion is idempotent, so a timeout or a dropped answer is simply asked again; an expired or unknown session is not, since asking again can't change it.
    func complete(uploadId: Int) async throws -> ImageDTO {
        var lastError: Error?
        for attempt in 0..<Self.completionAttempts {
            if attempt > 0 {
                try await Task.sleep(for: retryDelay(attempt))
            }
            do {
                let response: CompleteVideoUploadResponseDTO = try await apiClient.callRPC(.completeVideoUpload, payload: VideoUploadIdRequestDTO(uploadId: uploadId))
                return response.image
            } catch {
                lastError = error
                AppLog.sync.error("Video completion attempt \(attempt + 1) failed: \(String(describing: error), privacy: .public)")
                guard Self.isWorthRetrying(error) else { break }
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    static func isWorthRetrying(_ error: Error) -> Bool {
        let refusal = refusalSentence(error)
        return refusal != VideoUploadRefusal.expired && refusal != VideoUploadRefusal.notFound
    }

    /// The server's own sentence for a refused proc, if that is what this is.
    static func refusalSentence(_ error: Error) -> String? {
        guard case APIError.server(let statusCode, let message) = error else { return nil }
        return APIError.procSentence(statusCode: statusCode, message: message)
    }
}
