import Foundation
import OSLog

/// The offline-analysis procs: suggestions, matches, insights. These are online reads and never queued — the server owns the answer, and a suggestion that arrives after the moment has passed is worth nothing. Every failure reads as "no suggestion", because the procs are designed to come back empty wherever the vision daemon isn't running.
/// Answers worth reusing within a session are cached in memory only, like `SameAgeCache`: a stale suggestion from yesterday is worse than none.
@MainActor
final class AnalysisService {
    static let shared = AnalysisService()

    let apiClient: APIClient
    private var milestoneMatches: [Int: GetMilestoneMatchesResponseDTO] = [:]
    private var personInsights: [Int: GetPersonPhotoInsightsResponseDTO] = [:]
    private var tagSuggestionReview: GetTagSuggestionsResponseDTO?

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func removeAll() {
        milestoneMatches = [:]
        personInsights = [:]
        tagSuggestionReview = nil
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

extension AnalysisService {

    // MARK: - People

    /// The last answer this session, for a first frame that doesn't wait on the network.
    func cachedPersonPhotoInsights(personId: Int) -> GetPersonPhotoInsightsResponseDTO? {
        personInsights[personId]
    }

    /// A fresh answer, stored for `cachedPersonPhotoInsights`. `nil` on failure, leaving the cached one alone.
    func refreshPersonPhotoInsights(personId: Int) async -> GetPersonPhotoInsightsResponseDTO? {
        do {
            let response: GetPersonPhotoInsightsResponseDTO = try await apiClient.callRPC(
                .getPersonPhotoInsights,
                payload: GetPersonPhotoInsightsRequestDTO(personId: personId)
            )
            personInsights[personId] = response
            return response
        } catch {
            AppLog.ui.error("Photo insights failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

extension AnalysisService {

    // MARK: - Photos

    /// The photo page's extras — place and pending tag suggestions. `nil` on failure.
    func photoDetails(photoId: Int) async -> GetPhotoResponseDTO? {
        do {
            return try await apiClient.callRPC(.getPhoto, payload: GetPhotoRequestDTO(id: photoId))
        } catch {
            AppLog.ui.error("GetPhoto failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Tag suggestions

    /// The review, and the badge count on the way to it. `nil` on failure.
    func tagSuggestions() async -> GetTagSuggestionsResponseDTO? {
        do {
            struct EmptyPayload: Encodable {}
            let response: GetTagSuggestionsResponseDTO = try await apiClient.callRPC(.getTagSuggestions, payload: EmptyPayload())
            tagSuggestionReview = response
            return response
        } catch {
            AppLog.ui.error("Tag suggestions failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The last review fetched this session, so the gallery's link can show before a fresh one answers.
    var cachedTagSuggestions: GetTagSuggestionsResponseDTO? {
        tagSuggestionReview
    }

    /// Tags the suggestions' photos. Throws, unlike the reads: the user asked for this and has to hear that it didn't happen.
    @discardableResult
    func acceptTagSuggestions(_ ids: [Int]) async throws -> Int {
        let response: SuggestionIdsResponseDTO = try await apiClient.callRPC(.acceptTagSuggestions, payload: SuggestionIdsRequestDTO(ids: ids))
        return response.updated
    }

    @discardableResult
    func rejectTagSuggestions(_ ids: [Int]) async throws -> Int {
        let response: SuggestionIdsResponseDTO = try await apiClient.callRPC(.rejectTagSuggestions, payload: SuggestionIdsRequestDTO(ids: ids))
        return response.updated
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
