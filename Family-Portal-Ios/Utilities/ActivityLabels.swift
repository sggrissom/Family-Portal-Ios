import Foundation

/// Vocabulary for the activities UI, keyed by `Activity.kind`. A port of `frontend/pages/activities/labels.ts`.
/// Nothing in `backend/` knows the word "routine" or "competition", so this map is the only place the domain word comes back. The view layer must never hardcode one.
nonisolated struct ActivityLabels: Equatable, Sendable {
    let event: String
    let eventPlural: String
    let entry: String
    let entryPlural: String
    let appearance: String
    let appearancePlural: String
    let roster: String

    static let dance = ActivityLabels(
        event: "Competition",
        eventPlural: "Competitions",
        entry: "Routine",
        entryPlural: "Routines",
        appearance: "Performance",
        appearancePlural: "Performances",
        roster: "Dancers"
    )

    static let sport = ActivityLabels(
        event: "Game",
        eventPlural: "Games",
        entry: "Team",
        entryPlural: "Teams",
        appearance: "Game",
        appearancePlural: "Games",
        roster: "Players"
    )

    static let generic = ActivityLabels(
        event: "Event",
        eventPlural: "Events",
        entry: "Entry",
        entryPlural: "Entries",
        appearance: "Appearance",
        appearancePlural: "Appearances",
        roster: "Members"
    )

    /// Unknown kinds fall to generic, the same fallback `normalizeActivityKind` applies on write.
    static func forKind(_ kind: String) -> ActivityLabels {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case ActivityKind.dance: return .dance
        case ActivityKind.sport: return .sport
        default: return .generic
        }
    }
}

/// The `Activity.kind` values the backend normalizes to (`normalizeActivityKind`, backend/activity_procs.go).
nonisolated enum ActivityKind {
    static let dance = "dance"
    static let sport = "sport"
    static let generic = "generic"

    static let all = [dance, sport, generic]

    static func displayName(_ kind: String) -> String {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case dance: return "Dance"
        case sport: return "Sport"
        default: return "Other"
        }
    }
}
