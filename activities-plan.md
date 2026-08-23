# Family Portal iOS — Competitive Activities

Plan for bringing the backend's **activities** feature (dance seasons: competitions,
routines, adjudications, placements, awards, photos) to the iOS app.

Reference repo: `../Family-Portal`. Backend claims below cite a file there. The
feature's own design doc is `../Family-Portal/docs/activities-plan.md`; this
document does not restate it, it decides what iOS does about it.

---

## Status — 23 August 2026

**Phases 1, 2 and 3 have landed.** A season entered on the web reads on the phone
in dance vocabulary and survives airplane mode; a routine can be added to a
competition and scored from a ballroom; and the whole program tree — activity,
season, competition, routine, roster, event photos — can be set up from the app.
The decisions asked for in §9 were taken as recommended: a fifth **Activities**
tab, phase 3 built last and plainly, and `ActivityEventDTO` over `CompetitionDTO`.

**Phase 4, offline writes, is deliberately not built.** It was optional from the
start, and §3 says why it should stay that way: every activity write is a
whole-set replace whose refusals — an entry from the wrong season, a result
naming someone off the roster, a rank past the size of its field — are ones the
device cannot predict, so a queued write replayed hours later would report a
success that never happened. Reads are cached; writes stay online. Revisit only
if the venue case proves to matter more than that.

Also still out of scope, as written in §2: activity import/export.

---

## 1. What exists on the server

Nine tables, all family-scoped, in `backend/activity.go`:

```
Activity   (a program: "Dance")           kind: dance | sport | generic
└── Season ("2025–26 Competition Season")
    ├── Event  (a competition: "Nuvo Nashville")
    └── Entry  (a routine: "Rise Up")     format/style/division/level, all free text
        └── EntryMember → Person          roster join

Appearance = Entry × Event                the hinge: this routine, at this competition
├── Result           adjudication | placement | award | score
└── AppearancePhoto → Photo
EventPhoto → Photo                        the weekend shots that aren't of one routine
```

The schema deliberately knows no dance vocabulary. "Routine", "Competition" and
"Performance" come from a label map keyed by `Activity.Kind`
(`frontend/pages/activities/labels.ts`), which iOS has to port — see §5.

### 26 procs, in four groups

| Group | Procs | File |
| --- | --- | --- |
| Structure CRUD | `ListActivities` `CreateActivity` `UpdateActivity` `DeleteActivity` `ListSeasons` `CreateSeason` `UpdateSeason` `DeleteSeason` `CreateEvent` `UpdateEvent` `DeleteEvent` `CreateEntry` `UpdateEntry` `DeleteEntry` `SetEntryRoster` | `backend/activity_procs.go` |
| Appearances & results | `CreateAppearance` `UpdateAppearance` `DeleteAppearance` `SetAppearanceResults` | `backend/activity_results.go` |
| Aggregate reads | `GetSeasonOverview` `GetEventDetail` `GetEntryHistory` `GetPersonSeason` `ListActivityVocabulary` | `backend/activity_views.go` |
| Photos | `SetAppearancePhotos` `SetEventPhotos` | `backend/activity_photos.go` |

The four aggregate reads are the important ones. Each returns everything one
screen needs in a single call — that is the stated reason `Appearance` is its own
table — so the client never fans out over ids it just received.

### Access

`ListActivities` / `ListSeasons` / `GetSeasonOverview` / `GetEventDetail` are
whole-family reads. `GetEntryHistory` and `GetPersonSeason` resolve through a
roster, so a linked household reaches exactly the routines its shared child is
in; those two return `SeasonSummary` / `EventSummary` rather than the full
records. Every write asks for `AccessContribute`, which a link never has.

iOS does not currently expose family links at all, so this distinction costs the
app nothing today — but `GetPersonSeason` is the one activities proc that is
*always* safe to call for any person the app can see, which matters for §7.

---

## 2. What iOS should ship — and what it shouldn't

The web already has 3,700 lines of activities UI across seven pages, including
full CRUD for the program tree, an import/export path, and a results editor.
Cloning that on a phone is the wrong target.

Two moments are worth having in a pocket, and they are the ones the web is
worst at:

1. **"How is her season going?"** — a kid's routines, their results, the photos.
   Read-only, one proc, no navigation tree. `GetPersonSeason`.
2. **Competition day.** You are in a convention-centre ballroom, you just watched
   the routine, you have the results sheet in your hand and a photo on your
   camera roll. Entering that *there* is the whole point of a phone client.
   `CreateAppearance` + `SetAppearanceResults` + `SetAppearancePhotos`.

Everything else — creating the program, naming the season, entering twelve
routines and their rosters in September — is annual setup work that belongs on a
keyboard. Ship it, but ship it last and ship it plain.

**Explicitly out of scope:** activity import/export (`backend/activity_export.go`,
`activity_import.go`) — a bulk data-migration path with no phone use case.

---

## 3. Architecture: online-first with a snapshot cache

**Decision: activities do *not* go into SwiftData or `SyncQueue`.** They are read
online through the four aggregate procs, written online through the CRUD procs,
and the decoded response of each read is cached to disk so a screen that has been
opened once still renders offline.

### Why not local-first, like people/milestones/photos

- **The joins are already done.** `GetSeasonOverview` returns activity, season,
  events, entries-with-rosters and appearances-with-results in one payload.
  Modelling nine `@Model` classes and rebuilding those joins with `@Query` is
  rewriting work the server does in one index walk, and it buys a schema
  migration on `DataStore.container` for the trouble.
- **Every write is a whole-set replace with server-side cross-record
  validation.** `SetEntryRoster`, `SetAppearanceResults` and `SetAppearancePhotos`
  replace their whole set (`setEntryRosterTx`, `setAppearancePhotosTx`), and
  `CreateAppearance` refuses an entry from a different season than the event
  (`ErrEntryNotInSeason`), a result naming someone off the roster
  (`ErrResultPersonNotOnEntry`), a placement whose rank exceeds its field
  (`ErrResultRankOutOfRange`). These are exactly the refusals the device cannot
  predict — the same reason `FamilyMembershipService` is deliberately not queued:
  *a queued write replayed hours later reports a success that never happened.*
- **There is no delta protocol.** `GetFamilyTimeline` does not carry activities,
  so a queued activity write has nothing to reconcile against on the next pull.

### Why a cache at all, then

Because the venue has no signal. Arriving at a competition and finding the app
blank is the failure the offline story exists to prevent. But *reading* stale
data is safe in a way that replaying stale writes is not, so the two halves get
different answers.

### Shape

```
Services/ActivityService.swift      @Observable, @MainActor, init(apiClient:) like PhotoSyncService
Services/ActivityDTOs.swift         wire types (own file, like ChatDTOs.swift)
Services/ActivitySnapshotCache.swift
```

`ActivitySnapshotCache` stores the raw response `Data` per read, keyed by proc +
argument (`seasonOverview:41`, `personSeason:7:0`), in Application Support with a
fetched-at timestamp. A screen renders the cached payload immediately if it has
one, fires the live call, and replaces it. Failures leave the cache in place and
surface a "showing what we last saw" note rather than an error.

Two things this must not get wrong, both learned the hard way elsewhere in this
app:

- **`LocalDataReset.erase(.everything)` must drop the cache.** It is the same
  problem `LocalAccountOwner` exists for: a device that changes hands would
  otherwise show the previous account's season. Add the sweep alongside the
  `delete(FamilyTag.self, …)` calls.
- **A cache miss is not "no data".** Empty state and offline-with-nothing-cached
  are different screens; conflating them is how the chat history bug read as
  "this family has no messages".

### If offline writes are wanted later

The migration is additive and does not disturb any of the above: add
`SyncOperationType` cases for the appearance/results writes only (the
competition-day set), give them a `dependsOnLocalId` on the appearance's create,
and keep everything else online. Do not attempt it in the first pass — the
dependency chain for a queued `CreateAppearance` → `SetAppearanceResults` →
`SetAppearancePhotos` is three levels deep and every link can be refused for a
reason the device didn't check.

---

## 4. Wire layer

### 4.1 `RPCMethod`

All 26 names go into `Services/RPCMethod.swift` under new `// MARK:` groups, and
into `RPCMethodTests`. Every one of them matches its Go function name exactly —
there is no `…Proc` suffix anywhere in the activities registration
(`RegisterActivityMethods`, `RegisterActivityResultMethods`,
`RegisterActivityViewMethods`, `RegisterActivityPhotoMethods`), so the
`RemovePersonFromPhotoProc` trap does not recur here. Confirm against the four
`RegisterProc` blocks rather than against the TypeScript, which is generated.

### 4.2 DTO naming

Swift needs renames the wire does not:

| Go / TS | Swift | Why |
| --- | --- | --- |
| `Result` | `ActivityResultDTO` | `Result` is a Swift stdlib type; a bare one in a `throws` context is a genuine misreading hazard |
| `Event` | `CompetitionDTO` or `ActivityEventDTO` | Bare `Event` next to SwiftUI event handling reads badly |
| `Entry` | `ActivityEntryDTO` | — |
| `Activity`, `Season`, `Appearance` | `…DTO` suffix | — |

This is the `FamilyTag` precedent: the longer name is the correct one when the
short one sits next to something in the standard library.

Views: `EntryViewDTO` (entry + personIds), `AppearanceViewDTO` (appearance +
results + photoIds), `AppearanceDetailDTO` (+ entry + event summary),
`SeasonSummaryDTO`, `EventSummaryDTO`.

### 4.3 The five encoding traps

**1. Absent dates arrive as year 1, not as null.** `Season.StartDate`,
`Event.EndDate` and `Appearance.OccurredAt` are non-pointer `time.Time` in Go, so
"not known yet" — an explicitly normal state, see `parseActivityDate` — marshals
as `"0001-01-01T00:00:00Z"`. `APIClient`'s ISO8601 decoder accepts that happily
and hands back a `Date` in the year 1. Every activities date needs an
`isUnsetDate` check before formatting, or the UI prints *Jan 1, 1* wherever the
web prints nothing. Add a `Date.isServerZero` helper next to `AgeCalculator` and
a decoding test that pins it.

**2. Optional numbers are omitted, not null.** `Rank`, `OutOf`, `Score`,
`PersonId` are `*T` with `omitempty` — `decodeIfPresent` / `encodeIfPresent` on
both sides. Do not substitute 0: the backend packs these through
`packOptionalInt` specifically so "no placement" stays distinguishable from
"1st".

**3. Proc errors arrive as HTTP 400 with a bare plain-text body.**
`vbeam.RespondError` writes `w.WriteHeader(400)` then `fmt.Fprintf(w, err.Error())`
— no JSON, no `success: false`. So `APIError.server(statusCode: 400, message:)`
already carries the exact user-facing sentence ("That entry is not in the same
season as this competition"), but `errorDescription` renders it as
`Server error (400): That entry is not…`.

This is the first iOS feature whose backend returns error strings actually meant
for a user, so it needs the unwrap: add a case that presents a 400 body verbatim
when it is short and non-empty, and fall back to the generic wording otherwise.
Everything else in `backend/activity_*.go` — `ErrNameRequired`,
`ErrEntryNotInSeason`, `ErrResultRankOutOfRange`, `ErrTooManyResults` — then
reaches `ErrorPresenter` as written.

(Related, and already true today: a proc-level auth failure is also a 400, not a
401, so it does not trip `retryOnAuthFailure`. `ensureFreshAccessToken` is what
keeps that from mattering.)

**4. `familyId: 0` means the caller's primary family.** Same convention as
`FamilyMembershipService`. Only `ListActivitiesRequest` and
`CreateActivityRequest` carry it; everything below activity level is reached by
its own id.

**5. Request dates are `*string` in `YYYY-MM-DD`, and nil clears.** `UpdateSeason`
and `UpdateEvent` assign whatever `parseActivityDate` returns unconditionally, so
omitting the key does **not** mean "leave it alone" — it means "set it to
unknown". Editors must always send the current value.

### 4.4 Server-side caps to mirror in the UI

`maxNameLength` 200, `maxLabelLength` 100, `maxNotesLength` 4000
(`activity_procs.go`), `maxResultsPerAppearance` 50 (`activity_results.go`),
`maxPhotosPerSubject` 200 (`activity_photos.go`). Over-length text is silently
*truncated*, not refused — so a text field that lets the user type 300 characters
will quietly lose 100 of them.

---

## 5. The label pack

Port `frontend/pages/activities/labels.ts` to `Utilities/ActivityLabels.swift`
verbatim: a struct with `event`/`eventPlural`, `entry`/`entryPlural`,
`appearance`/`appearancePlural`, `roster`, and the three packs (dance: Competition
/ Routine / Performance / Dancers; sport: Game / Team / Game / Players; generic:
Event / Entry / Appearance / Members). Unknown kinds fall to generic, matching
`normalizeActivityKind`.

Read the kind from `Activity.kind` where the response carries the activity, and
from `SeasonSummary.kind` where it doesn't — the backend added that field to
`SeasonSummary` for exactly this reason, because a season crossing a link
boundary without it renders as "Event", the one word the label map exists to
avoid.

No hardcoded "Routine" or "Competition" anywhere in the view layer. Getting this
wrong is invisible today (only dance ships) and expensive later.

---

## 6. Screens

| Screen | Proc | Notes |
| --- | --- | --- |
| `PersonSeasonView` | `GetPersonSeason(personId, seasonId: 0)` | The headline screen. Seasons → routines → performances with results. Pushed from `PersonDetailView`. |
| `SeasonView` | `GetSeasonOverview(seasonId)` | Competitions and routines side by side; join `appearances` on `entryId`/`eventId` locally, as the web does — the response ships each parent once on purpose. |
| `CompetitionView` | `GetEventDetail(eventId)` | The day: every performance in order, plus the event's own photos. |
| `RoutineView` | `GetEntryHistory(entryId)` | One routine across the season. |
| `ActivitiesRootView` | `ListActivities` → `ListSeasons` per activity | 1 + N calls, but N is ~1. There is no proc that lists seasons across activities. |
| `ResultsEditorView` | `SetAppearanceResults` | See below. |
| Structure editors | the CRUD procs | Activity, season, competition, routine + roster, appearance. Plain forms. |

### Navigation

Recommend a fifth root tab, **Activities** (`trophy`), in `ContentView.mainTabs`,
plus a "This season" row in `PersonDetailView` pushing `PersonSeasonView`. Five
tabs is fine on iPhone, and chat's demotion into Settings (`94e9c1d`
"De-emphasize chat navigation") shows the tab bar is not treated as full.

If you'd rather not spend a tab: put the root list behind a Family-tab row and
keep the person link. Say which — it changes the first phase's shape, not its
size.

### Results editor

Mirror `frontend/pages/activities/results-editor.tsx`. A results sheet is edited
as a list of rows and saved as one array — `ResultInput` carries no `SortOrder`
because array position *is* the order.

Validate on-device before sending, matching `activity_results.go` exactly, so the
user gets an inline error instead of a round-trip 400:

- adjudication / award → label required
- placement → rank required, `rank >= 1`, and `rank <= outOf` when `outOf` is set
- score → score required
- `personId`, when set, must be on the entry's roster (`EntryView.personIds`)

Autocomplete every free-text field from `ListActivityVocabulary(activityId)`.
This is not a nicety: adjudication labels are free text by design and nothing
normalizes them at write time, so without suggestions "High Gold" becomes "high
gold" and the season view cannot even *count*, let alone rank. Cache the
vocabulary response with the rest.

### Photos

`SetAppearancePhotos` / `SetEventPhotos` are whole-set writes over **remote**
photo ids. Reuse the `MilestonePhotoPickerView` pattern, filtered to
`remoteId != nil` — a photo still uploading cannot be attached, and since this
path is online-only there is nothing to resolve later.

Render attached photos with `RemotePhotoView(remoteId:)`. Do not require a local
`Photo` record: `visiblePhotoIds` filters per caller and the ids may point at
photos this device has never pulled — the same "server ids, resolve what you can"
arrangement as `Milestone.photoRemoteIds`.

---

## 7. Phases

**Phase 1 — read the season.** DTOs, `RPCMethod`, `ActivityService` reads, the
snapshot cache, the label pack, the 400-body unwrap. `PersonSeasonView` off
`PersonDetailView`, `SeasonView`, `CompetitionView`, `RoutineView`, and the root
list. No writes at all.

*Done when:* a season entered on the web is fully readable on the phone, in dance
vocabulary, with photos, and stays readable in airplane mode after one visit.

**Phase 2 — competition day.** `CreateAppearance` / `UpdateAppearance` /
`DeleteAppearance`, the results editor with vocabulary autocomplete and full
client-side validation, `SetAppearancePhotos`.

*Done when:* a routine can be added to a competition and scored from the phone,
and every backend refusal reaches the user as its own sentence.

**Phase 3 — setup.** Activity / season / competition / routine CRUD, roster
editing via `SetEntryRoster`, `SetEventPhotos`. Destructive actions confirm
loudly and name what goes with them: `deleteSeasonTx` cascades through every
competition, routine, appearance and result under it.

**Phase 4 (optional) — offline writes.** Only if phase 2 proves the venue case
matters more than the complexity. See §3.

---

## 8. Tests

Swift Testing, `Family-Portal-IosTests`, against `FakeHTTP`:

- **`ActivityDTODecodingTests`** — a fixture with `"0001-01-01T00:00:00Z"` in
  every date field, absent `rank`/`outOf`/`score`/`personId`, and empty arrays.
  This is the test that catches trap #1 before a user sees *Jan 1, 1*.
- **`ActivityErrorTests`** — a 400 with the bare body
  `That entry is not in the same season as this competition` presents that
  sentence and not `Server error (400): …`.
- **`ActivityLabelsTests`** — dance/sport/generic/unknown, and the
  `SeasonSummary.kind` path.
- **`ResultValidationTests`** — the five rules in §6, each refused locally.
- **`ActivitySnapshotCacheTests`** — a cached payload renders offline; a failed
  refresh keeps it; `LocalDataReset.erase(.everything)` removes it.

Add an `AppLog.activities` category; no `print` in the app target.

---

## 9. Decisions needed

1. **Fifth tab, or Family-tab entry point?** (§6) — recommend the tab.
2. **Is phase 3 worth building at all,** or is the phone a read-and-score client
   with setup left on the web? Recommend building it, last and plainly.
3. **DTO name for `Event`** — `CompetitionDTO` reads better in dance-only code
   but bakes in the vocabulary the label pack exists to keep out of the type
   layer; `ActivityEventDTO` is uglier and correct. Recommend
   `ActivityEventDTO`.

   I agree with your recommendations, go with those
