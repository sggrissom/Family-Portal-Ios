import Foundation

/// What a performance editor wrote, handed to the screen that opened it so the change shows at once rather than after another network read.
nonisolated enum PerformanceChange: Sendable {
    /// The server's copy of the performance as saved — created or replaced.
    case saved(AppearanceViewDTO)
    case deleted(appearanceId: Int)
}

/// Applying a performance write to a competition page already on screen. The refresh that follows confirms it; until then the page shows the server's own response rather than the stale read.
nonisolated enum EventPerformances {

    /// `entries` names the routine of a newly created performance, which the save response carries only by id. A change this page cannot place — another competition, or a routine it has no record of — leaves it as it was for the refresh to settle.
    static func applying(
        _ change: PerformanceChange,
        to response: GetEventDetailResponseDTO,
        entries: [ActivityEntryDTO]
    ) -> GetEventDetailResponseDTO {
        switch change {
        case .deleted(let appearanceId):
            return response.replacingAppearances(response.appearances.filter { $0.id != appearanceId })

        case .saved(let saved):
            guard saved.appearance.eventId == response.event.id else { return response }
            let existing = response.appearances.first { $0.id == saved.id }
            guard let entry = existing?.entry ?? entries.first(where: { $0.id == saved.appearance.entryId }) else {
                return response
            }
            let detail = AppearanceDetailDTO(
                view: saved,
                entry: entry,
                event: existing?.event ?? EventSummaryDTO(response.event)
            )
            var appearances = response.appearances.filter { $0.id != saved.id }
            appearances.append(detail)
            appearances.sort(by: order)
            return response.replacingAppearances(appearances)
        }
    }

    /// The server's `appearanceOrder`: by when it happened — the competition's start for a performance with no date of its own — then by id.
    static func order(_ a: AppearanceDetailDTO, _ b: AppearanceDetailDTO) -> Bool {
        let aWhen = a.appearance.occurredAt.serverDate ?? a.event.startDate
        let bWhen = b.appearance.occurredAt.serverDate ?? b.event.startDate
        if aWhen != bWhen { return aWhen < bWhen }
        return a.id < b.id
    }
}
