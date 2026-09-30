import Foundation
import OSLog

/// The offline-analysis procs: suggestions, matches, insights. These are online reads and never queued — the server owns the answer, and a suggestion that arrives after the moment has passed is worth nothing. Every failure reads as "no suggestion", because the procs are designed to come back empty wherever the vision daemon isn't running.
/// Answers worth reusing within a session are cached in memory only, like `SameAgeCache`: a stale suggestion from yesterday is worse than none.
@MainActor
final class AnalysisService {
    static let shared = AnalysisService()

    private let apiClient: APIClient
    private var milestoneMatches: [Int: GetMilestoneMatchesResponseDTO] = [:]

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func removeAll() {
        milestoneMatches = [:]
    }

    // MARK: - Milestones

    /// A category for what the description says, or `nil`. The server wants at least three characters.
    func suggestMilestoneCategory(description: String, personId: Int?) async -> MilestoneCategory? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else { return nil }
        do {
            let response: SuggestMilestoneCategoryResponseDTO = try await apiClient.callRPC(
                .suggestMilestoneCategory,
                payload: SuggestMilestoneCategoryRequestDTO(description: text, personId: personId ?? 0)
            )
            return MilestoneCategory(rawValue: response.category)
        } catch {
            AppLog.ui.error("Category suggestion failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Server ids of photos of the person from around `date`, best first. Empty on any failure.
    func suggestMilestonePhotos(personId: Int, description: String, date: Date, excludeIds: [Int] = []) async -> [Int] {
        do {
            let response: SuggestMilestonePhotosResponseDTO = try await apiClient.callRPC(
                .suggestMilestonePhotos,
                payload: SuggestMilestonePhotosRequestDTO(
                    personId: personId,
                    description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                    inputType: "date",
                    milestoneDate: dateToAPIString(date),
                    excludeIds: excludeIds
                )
            )
            return response.photoIds
        } catch {
            AppLog.ui.error("Photo suggestion failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// The milestone's matches in the family, cached for the session. `nil` offline with nothing cached, or on failure.
    func milestoneMatches(milestoneId: Int, isConnected: Bool) async -> GetMilestoneMatchesResponseDTO? {
        if let cached = milestoneMatches[milestoneId] { return cached }
        guard isConnected else { return nil }
        do {
            let response: GetMilestoneMatchesResponseDTO = try await apiClient.callRPC(
                .getMilestoneMatches,
                payload: GetMilestoneMatchesRequestDTO(milestoneId: milestoneId)
            )
            milestoneMatches[milestoneId] = response
            return response
        } catch {
            AppLog.ui.error("Milestone matches failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

/// Server photo ids resolved to the photos this device holds, in the server's order. An id with no local row — not pulled yet, or not one of the eligible photos — is dropped.
enum RemotePhotoResolution {
    static func resolve(_ remoteIds: [Int], in photos: [Photo]) -> [Photo] {
        var byRemoteId: [Int: Photo] = [:]
        for photo in photos {
            if let id = photo.remoteId.flatMap(Int.init) { byRemoteId[id] = photo }
        }
        return remoteIds.compactMap { byRemoteId[$0] }
    }
}
