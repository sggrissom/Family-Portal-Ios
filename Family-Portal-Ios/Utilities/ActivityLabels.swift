import Foundation

/// Vocabulary for the activities UI, keyed by `Activity.kind`.
///
/// A port of `frontend/pages/activities/labels.ts`. Nothing in `backend/` knows
/// the word "routine" or "competition" — the schema is deliberately
/// activity-agnostic (Event, Entry, Appearance) — so this map is the only place
/// the domain word comes back, and shipping a sport label pack is a second
/// entry here rather than a second set of screens.
///
/// The view layer must never hardcode "Routine" or "Competition". Getting that
/// wrong is invisible today, because only dance ships, and expensive later.
nonisolated struct ActivityLabels: Equatable, Sendable {
    /// A season's competitions / games / meets.
    let event: String
    let eventPlural: String
    /// The recurring competitive unit: a routine, a team, a swim event.
    let entry: String
    let entryPlural: String
    /// One entry at one event.
    let appearance: String
    let appearancePlural: String
    /// What the people on an entry are called collectively.
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

    /// Unknown kinds fall to generic, which is the same fallback
    /// `normalizeActivityKind` applies on write — so the default branch is not
    /// dead code, it is what a record written by an older or newer client
    /// renders as. Trimming and lowercasing first matches that normalizer
    /// exactly.
    static func forKind(_ kind: String) -> ActivityLabels {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case ActivityKind.dance: return .dance
        case ActivityKind.sport: return .sport
        default: return .generic
        }
    }
}

/// The `Activity.kind` values the backend normalizes to
/// (`normalizeActivityKind`, backend/activity_procs.go).
nonisolated enum ActivityKind {
    static let dance = "dance"
    static let sport = "sport"
    static let generic = "generic"

    /// Every kind a picker may offer, in the order the web offers them.
    static let all = [dance, sport, generic]

    /// The kind's own name, for a form that is choosing one — as opposed to
    /// `ActivityLabels`, which is the vocabulary a chosen kind produces.
    static func displayName(_ kind: String) -> String {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case dance: return "Dance"
        case sport: return "Sport"
        default: return "Other"
        }
    }
}
