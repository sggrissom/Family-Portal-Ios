import Foundation
import OSLog

/// Downloads everything result entry at one competition needs, so results can be entered there with no connection: the competition with its performances, the season's routines and rosters, the activity's vocabulary, and whether this account may add results. The reads land in `ActivitySnapshotCache` like any other; the performances are also merged into `ActivityLocalStore` as the baseline local edits build on.
///
/// What arrived is recorded part by part (`PreparedCompetition`), so a download cut short shows as incomplete rather than as a competition with no results.
@MainActor
struct CompetitionPreparation {

    let service: ActivityService
    let store: ActivityLocalStore

    enum Outcome: Equatable {
        case complete
        /// Some reads failed; what did arrive is kept and recorded.
        case incomplete
        /// The competition itself could not be read, so nothing is recorded.
        case failed(String)
    }

    func prepare(eventId: Int, userId: Int, access: FamilyAccess, now: () -> Date = Date.init) async -> Outcome {
        let readStartedAt = now()
        let detail: GetEventDetailResponseDTO
        do {
            detail = try await service.eventDetail(eventId: eventId).live()
        } catch {
            AppLog.activities.error("Preparing a competition failed: \(String(describing: error), privacy: .public)")
            return .failed(error.localizedDescription)
        }

        var overview: GetSeasonOverviewResponseDTO?
        do {
            overview = try await service.seasonOverview(seasonId: detail.season.id).live()
        } catch {
            AppLog.activities.error("Preparing a season failed: \(String(describing: error), privacy: .public)")
        }

        var hasVocabulary = false
        if let activityId = overview?.activity.id {
            do {
                _ = try await service.vocabulary(activityId: activityId).live()
                hasVocabulary = true
            } catch {
                AppLog.activities.error("Preparing an activity's vocabulary failed: \(String(describing: error), privacy: .public)")
            }
        }

        do {
            try store.mergeServerPerformances(
                detail.appearances,
                eventId: eventId,
                userId: userId,
                readStartedAt: readStartedAt
            )
            try store.recordPreparation(eventId: eventId, userId: userId) { record in
                record.familyId = detail.event.familyId
                record.seasonId = detail.season.id
                record.activityId = overview?.activity.id ?? record.activityId
                record.hasEventDetail = true
                // A failed read this time leaves what an earlier download brought: the cached copy is still on the phone.
                record.hasSeasonOverview = record.hasSeasonOverview || overview != nil
                record.hasVocabulary = record.hasVocabulary || hasVocabulary
                record.canContribute = access.canContribute(detail.event.familyId)
                record.lastAttemptAt = now()
                if overview != nil && hasVocabulary {
                    record.preparedAt = now()
                }
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        let record = store.preparedCompetition(eventId: eventId, userId: userId)
        return record?.isComplete == true ? .complete : .incomplete
    }
}
