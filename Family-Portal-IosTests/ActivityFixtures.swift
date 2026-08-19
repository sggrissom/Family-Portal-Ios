import Foundation
@testable import Family_Portal_Ios

/// JSON bodies shaped like `json.Marshal` output for the types in
/// `../Family-Portal/backend/activity*.go`.
///
/// The defaults are deliberately the awkward ones: dates default to the Go zero
/// time, and the optional numbers on a result default to absent. Those are the
/// states the server produces constantly — "not known yet" is normal for a
/// season's dates, and "no placement" is normal for an adjudication — so a
/// fixture that had to opt into them would let a decoder that mishandles them
/// pass every test.
extension Fixture {

    /// What a non-pointer `time.Time` marshals to when nothing was ever set.
    static let unsetDate = "0001-01-01T00:00:00Z"

    // MARK: - Records

    static func activity(
        id: Int,
        familyId: Int = 7,
        name: String = "Dance",
        kind: String = "dance"
    ) -> [String: Any] {
        [
            "id": id,
            "familyId": familyId,
            "name": name,
            "kind": kind,
            "createdAt": "2025-08-01T12:00:00Z"
        ]
    }

    static func season(
        id: Int,
        activityId: Int = 1,
        familyId: Int = 7,
        name: String = "2025-26 Competition Season",
        startDate: String = unsetDate,
        endDate: String = unsetDate,
        notes: String = ""
    ) -> [String: Any] {
        [
            "id": id,
            "activityId": activityId,
            "familyId": familyId,
            "name": name,
            "startDate": startDate,
            "endDate": endDate,
            "notes": notes,
            "createdAt": "2025-08-01T12:00:00Z"
        ]
    }

    /// Go's `Event`.
    static func activityEvent(
        id: Int,
        seasonId: Int = 1,
        familyId: Int = 7,
        name: String = "Nuvo Nashville",
        host: String = "Nuvo",
        location: String = "Nashville, TN",
        startDate: String = unsetDate,
        endDate: String = unsetDate,
        notes: String = ""
    ) -> [String: Any] {
        [
            "id": id,
            "seasonId": seasonId,
            "familyId": familyId,
            "name": name,
            "host": host,
            "location": location,
            "startDate": startDate,
            "endDate": endDate,
            "notes": notes,
            "createdAt": "2025-08-01T12:00:00Z"
        ]
    }

    /// Go's `Entry`.
    static func activityEntry(
        id: Int,
        seasonId: Int = 1,
        familyId: Int = 7,
        name: String = "Rise Up",
        format: String = "group",
        style: String = "Lyrical",
        division: String = "Teen",
        level: String = "Elite",
        notes: String = ""
    ) -> [String: Any] {
        [
            "id": id,
            "seasonId": seasonId,
            "familyId": familyId,
            "name": name,
            "format": format,
            "style": style,
            "division": division,
            "level": level,
            "notes": notes,
            "createdAt": "2025-08-01T12:00:00Z"
        ]
    }

    static func appearance(
        id: Int,
        eventId: Int = 1,
        entryId: Int = 1,
        familyId: Int = 7,
        occurredAt: String = unsetDate,
        notes: String = ""
    ) -> [String: Any] {
        [
            "id": id,
            "eventId": eventId,
            "entryId": entryId,
            "familyId": familyId,
            "occurredAt": occurredAt,
            "notes": notes,
            "createdAt": "2025-08-01T12:00:00Z"
        ]
    }

    /// Go's `Result`. `rank`, `outOf`, `score` and `personId` carry `omitempty`,
    /// so an unset one is an *absent key* — never `null` and never 0.
    static func activityResult(
        id: Int,
        appearanceId: Int = 1,
        familyId: Int = 7,
        kind: String = "adjudication",
        label: String = "High Gold",
        rank: Int? = nil,
        outOf: Int? = nil,
        category: String = "",
        score: Double? = nil,
        personId: Int? = nil,
        notes: String = "",
        sortOrder: Int = 0
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "appearanceId": appearanceId,
            "familyId": familyId,
            "kind": kind,
            "label": label,
            "category": category,
            "notes": notes,
            "sortOrder": sortOrder,
            "createdAt": "2025-08-01T12:00:00Z"
        ]
        if let rank { result["rank"] = rank }
        if let outOf { result["outOf"] = outOf }
        if let score { result["score"] = score }
        if let personId { result["personId"] = personId }
        return result
    }

    // MARK: - Views

    static func entryView(_ entry: [String: Any], personIds: [Int] = []) -> [String: Any] {
        ["entry": entry, "personIds": personIds]
    }

    static func appearanceView(
        _ appearance: [String: Any],
        results: [[String: Any]] = [],
        photoIds: [Int] = []
    ) -> [String: Any] {
        ["appearance": appearance, "results": results, "photoIds": photoIds]
    }

    static func appearanceDetail(
        _ appearance: [String: Any],
        results: [[String: Any]] = [],
        photoIds: [Int] = [],
        entry: [String: Any],
        event: [String: Any]
    ) -> [String: Any] {
        [
            "appearance": appearance,
            "results": results,
            "photoIds": photoIds,
            "entry": entry,
            "event": event
        ]
    }

    static func seasonSummary(
        id: Int,
        name: String = "2025-26 Competition Season",
        kind: String = "dance",
        startDate: String = unsetDate,
        endDate: String = unsetDate
    ) -> [String: Any] {
        ["id": id, "name": name, "kind": kind, "startDate": startDate, "endDate": endDate]
    }

    static func eventSummary(
        id: Int,
        name: String = "Nuvo Nashville",
        host: String = "Nuvo",
        location: String = "Nashville, TN",
        startDate: String = unsetDate,
        endDate: String = unsetDate
    ) -> [String: Any] {
        [
            "id": id, "name": name, "host": host, "location": location,
            "startDate": startDate, "endDate": endDate
        ]
    }

    // MARK: - Responses

    static func listActivities(_ activities: [[String: Any]], familyId: Int = 7) -> [String: Any] {
        ["familyId": familyId, "activities": activities]
    }

    static func listSeasons(_ seasons: [[String: Any]], activityId: Int = 1) -> [String: Any] {
        ["activityId": activityId, "seasons": seasons]
    }

    static func seasonOverview(
        activity: [String: Any],
        season: [String: Any],
        events: [[String: Any]] = [],
        entries: [[String: Any]] = [],
        appearances: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "activity": activity,
            "season": season,
            "events": events,
            "entries": entries,
            "appearances": appearances
        ]
    }

    static func eventDetail(
        event: [String: Any],
        season: [String: Any],
        photoIds: [Int] = [],
        appearances: [[String: Any]] = []
    ) -> [String: Any] {
        ["event": event, "season": season, "photoIds": photoIds, "appearances": appearances]
    }

    static func entryHistory(
        entry: [String: Any],
        season: [String: Any],
        appearances: [[String: Any]] = []
    ) -> [String: Any] {
        ["entry": entry, "season": season, "appearances": appearances]
    }

    static func personSeason(
        personId: Int,
        seasonId: Int = 0,
        seasons: [[String: Any]] = [],
        entries: [[String: Any]] = [],
        appearances: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "personId": personId,
            "seasonId": seasonId,
            "seasons": seasons,
            "entries": entries,
            "appearances": appearances
        ]
    }

    static func activityVocabulary(
        activityId: Int = 1,
        adjudications: [String] = [],
        awards: [String] = [],
        categories: [String] = [],
        styles: [String] = [],
        divisions: [String] = [],
        levels: [String] = [],
        formats: [String] = [],
        hosts: [String] = []
    ) -> [String: Any] {
        [
            "activityId": activityId,
            "adjudications": adjudications,
            "awards": awards,
            "categories": categories,
            "styles": styles,
            "divisions": divisions,
            "levels": levels,
            "formats": formats,
            "hosts": hosts
        ]
    }

    // MARK: - Encoding

    static func data(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
