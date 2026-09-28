# Family Portal iOS — UI Redesign

The web app has been redesigned around three jobs: **putting data in fast**,
**seeing it in context** ("what were the others like at this age?"), and
**finding something remembered**. The design and its reasoning are in
`Family-Portal/docs/plans/ui-redesign.md`. All seven web phases are built on
`main`.

That plan makes the web the reference design and the app a native
implementation of it: the same destinations, the same add sheet, the same page
layouts and the same wording. This plan covers the iOS side. It follows the web
as it was **built**, not the plan text alone. Where the two differ, the built
version wins, and the difference is noted. The one intentional difference
between the app and the web is that Chat is not a top-level destination in the
app, though it is on the web.

---

## 1. Where the app stands

| Area | iOS today | Web now |
| --- | --- | --- |
| Tabs | Family · Timeline · Photos · Activities · Settings (chat badge on Settings) | Phone: Home · Photos · **+** · Growth · Chat. Desktop adds History. Account menu holds History, Activities, Tags, Face review, Settings, and more |
| Add | `QuickAddMenu` `+` on Family and Timeline; single-purpose `+` on Photos and Activities; person `+` on `PersonDetailView` | One add sheet from **+** anywhere: person chips, then Photos · Measurement · Milestone · up to two open-event Result shortcuts (`ListOpenEvents`) |
| Home | none (Family roster is the landing tab) | `GetDashboard`: family strip, up to two dismissible nudges, In season, On this day, Recent |
| Person | `PersonDetailView`: stacked sections linking out to measurement, milestone and photo lists; activities through `PersonSeasonView` | Header, then **Story · Photos · Growth · Activities** tabs. Story is grouped into age chapters with a "Grew …" line and an at-this-age strip |
| Timeline | `TimelineView`: flat filtered list | **History**: month sections, year jump, person chips + More (type/tags), milestone search, day summaries (photo mosaic, one checkup row, birthday dividers, event cards) |
| Compare | none | **Same age** page (`GetSameAge`), with strips on the measurement, photo and milestone detail pages |
| Growth | `GrowthChartView` per person | Family **Growth** page: height/weight toggle, avatar chips, percentile bands, tap a point to open it, drag to zoom, Measure button |
| Measurement entry | One type per save; **Save and Add Another** keeps person and date | One checkup: height and weight together, last value as helper text, lands on a result page with **Add another measurement** / **Done** |
| Dates | `DateEntryPicker` segmented Today / Date / Age; sends `inputType: "today"` | "Today ▾" menu: Today, Yesterday, Pick a date…, By age…. Always sends the device's local date with `inputType: "date"` |
| Photos | `PhotosPicker` → `PhotoImporter` → queue. EXIF missing means "now" silently. From a person `+`, photos are tagged with that person | Upload first, then optional who/caption/tags, with a per-photo date and its source. Global add starts untagged |

Already done on iOS and reusable: `FamilyGroups`/`RelationGraph` (the web's
`familyGroups`/`relations`), `GrowthComparison`, `GrowthPercentiles`,
`AgeCalculator`, `QuickAddDefaults`, `PhotoImporter`, `DetailSheetComponents`,
`RecordStyle`, `ActivitySnapshotCache`, and the whole activities stack.

---

## 2. Rules that carry over

These come from the web plan's "iOS parity" section and the web phases' Status
notes. They apply to every phase.

- **Share behavior, not pixels.** Use native `TabView`, sheets with detents,
  `Menu`, `DatePicker`, `PhotosPicker` and Swift Charts. Keep the destinations,
  labels and outcomes identical.
- **One copy list.** Port `frontend/lib/copy.ts` to `Utilities/Copy.swift`,
  keeping the same nesting (`Copy.nav.home`, `Copy.home.turned(name:age:)`).
  Views don't inline user-facing strings for anything the web has words for.
  When the web copy changes, this file changes in the same week.
- **Domain rules live on the server.** Age windows, nudges, and which events
  count as open come from `GetDashboard`, `GetSameAge` and `ListOpenEvents`. The
  app renders their results and never re-derives them.
- **Presentation grouping is ported, with the web's fixtures.** The web groups
  records client-side in pure functions with vitest coverage. Each one is
  ported to `Utilities/` with a Swift Testing suite built from the same fixture
  cases, so the two clients group the same records the same way. The functions:
  `when`, `checkup`, `daySummary`, `story`, `history`, `sameAge` (age steps and
  titles only), `ageChart`, `familyStrip`, `appNav` (as `DeepLink`), and
  `familyGroups.chipOrder`.
- **Local-first stays.** The app renders from SwiftData before the network
  answers, and the redesign must not break that. Anything built from synced
  records (History, Story, the person's Photos and Growth tabs, the Growth page)
  renders from the store. The aggregate procs (Home, Same age, open events) are
  cached per family, following `ActivitySnapshotCache`: the last good response
  shows immediately, marked stale when offline, and is replaced when a fetch
  lands. None of them are queued, since they're read-only.
- **Explicit context, never silent inheritance.** A person is preselected
  only from the screen you're standing on or an explicit chip tap, and it is
  always visible and removable. Photos opened from the global **+** start with
  no one tagged.
- **Dates are the device's.** Every write sends the local calendar date with
  `inputType: "date"` (or `"age"`), never `"today"`. The server's "today" is a
  UTC day and can be off by one for the family.

---

## 3. Backend prerequisites

Nothing new is needed server-side. All of this already exists:

- `GetDashboard { today }`, `ListOpenEvents { today }` (`backend/dashboard.go`)
- `GetSameAge` (`backend/same_age.go`), where `ageMonths` null means the
  person's current age and 0 means birth
- `GetFamilyTimeline { from, to, includeActivities }` → `years`, `appearances`
- `UpdatePhoto` with `inputType: "keep"`

The web plan requires every contract the app depends on to be in
`Family-Portal/docs/mobile-api.md` first. So far only `includeActivities` and
`keep` are documented there. **Document `GetDashboard`, `ListOpenEvents` and
`GetSameAge` before the phase that calls them.** That work is in the web repo,
and it is the first commit of phases 4 and 5 below.

`ComparePeople` has no iOS caller, so the web's cleanup phase can remove it
without waiting on an app release.

---

## 4. Phase 0 — foundations (no visible change)

1. `Copy.swift`, ported from `copy.ts`.
2. Ports with tests: `WhenEntry` (from `when.ts`: modes, validation, request
   building), `Checkup` (from `checkup.ts`: two-field validation and unit
   prefs), `AgeSteps` (from `sameAge.ts`: `ageStep`, `nextAge`, `prevAge`,
   `ageTitle`, `monthsOld`), and `FamilyGroups.chipOrder`.
3. Switch `DateEntryPicker`'s writes from `"today"` to a local `"date"`. This
   is a correctness fix that can ship alone.
4. DTOs and `RPCMethod` cases for `GetDashboard`, `ListOpenEvents` and
   `GetSameAge`, plus decoding tests against JSON captured from the local server.
   `GetFamilyTimeline` request gains `includeActivities`, and its response
   gains `years` and `appearances`, both via `decodeIfPresent`.

---

## 5. Phase 1 — shell

**Tabs:** **Home · Photos · + · Growth**. This is the web's phone bar
without Chat. This is a deliberate difference from the web: on the app, Chat is
not a top-level destination.

- `+` sits in the centre of the bar but is an action, not a tab. Selecting it
  presents the add sheet and leaves the previous tab selected. Implement it as a
  tab that intercepts its own selection, or as an overlay button; pick
  whichever keeps VoiceOver announcing "Add" as a button.
- An **account button** (the user's initial) sits in the top-right toolbar on
  every tab root. It opens a menu with History, Chat, Activities, Settings and
  Log out, using the web's wording.
- **Chat** moves out of Settings into the account menu. The unread count shows
  on the menu's Chat row and as a badge on the account button, so an unread
  message is still visible from every tab root. Chat push notifications and
  `/chat` links still open the chat screen directly, pushed onto the current
  tab's stack. Tags and Face review are
  web-only on iOS, so they appear as links that open the web page, with the
  face count badge (from `GetFaceReview`). If that feels wrong in the app, drop
  them; don't build native screens for them in this plan.
- History, Chat and Activities are pushed onto the current tab's stack from
  the account menu. They are not tabs.
- The Family roster (`FamilyMembersView`) stops being a destination. Home's
  family strip replaces it in phase 5; until then, Home is the roster with a
  new title. `FamilyManagementView` in Settings stays the full directory.

**Deep links.** `DeepLink` gains `home` (`/dashboard`), `history`
(`/history`), `growth` (`/growth`), `sameAge(ageMonths:from:)` (`/same-age`),
and `person(remoteId:tab:)` (`/profile/<id>?tab=`). The legacy paths
`/family-timeline`, `/family-chart`, `/compare` and `/person-activities/<id>`
map to their replacements, as `appNav.legacyRedirect` does. Keep this list
identical to `backend/universal_links.go`, and update that file in the same
change. Each link is added in the phase that ships its screen.

**Removes:** `QuickAddMenu`, the `.quickAdd(people:)` modifier, and the
single-purpose `+` on Photos and Activities. The person-page `+` stays as the
contextual add; it now opens the same sheet with that person chosen.

---

## 6. Phase 2 — fast entry

### The add sheet

A `.sheet` at `.medium` detent, presented from the shell (so it is one
instance app-wide, like `ErrorPresenter`):

- **Who is this for?** is a horizontal chip row in `chipOrder`. It is
  preselected from the screen underneath (a person page, or a photo/record's
  person), otherwise from `QuickAddDefaults`' remembered person. Tapping the
  selected chip clears it. The choice is written back as the remembered person,
  the way the web writes `last-person-id`.
- Options: **Photos**, **Measurement**, **Milestone**, then up to two
  **Result — {event}** rows from `ListOpenEvents`, each with its day label. A
  Result row pushes that event's `ResultsEditorView`. Backfilling older events
  goes through Activities.
- Measurement and Milestone are disabled with no people, as now.
- The sheet dismisses before presenting the form, and each form records its
  origin so **Done** returns there.

### Shared controls

- `PersonChips`: the chip row above, used by the sheet and all three forms.
- `WhenControl`: a `Menu` labelled with the current choice ("Today ▾") offering
  Today, Yesterday, Pick a date… (inline `DatePicker`), and By age… (the existing
  steppers). It replaces `DateEntryPicker`. It is keyed by `.id(person?.id)`
  for the reason `DateEntryPicker` is.

### Measurement: one checkup

Rebuild `AddMeasurementView` on `Checkup`:

- One person (chips, single select), their age on the chosen date, then
  `WhenControl`.
- Height and weight fields together. Either can be blank, but at least one is
  required. Keep `PoundsAndOuncesFields` and ft/in entry.
- Units are remembered per person, falling back to the family's last choice. This
  extends `QuickAddDefaults`, whose rule that a unit is only used for a type it
  can measure still holds.
- The last value and its date appear as persistent helper text under each
  field.
- Save queues one `AddGrowthData` per filled field, then pushes a **result
  screen**. It shows both values with percentiles and the family comparison
  (`GrowthComparison`), each marked *Saved* or *Waiting to sync* from the queue.
  The screen has **Add another measurement** (the same sheet, with the person
  cleared and the date kept) and **Done** (back to the origin). A queued op
  that is later discarded already reaches the user through
  `discardedChangeWarning`, so no new failure path is needed. A field whose
  enqueue fails is shown as not saved and can be retried on its own, without
  re-sending the other.
- **Save and Add Another** goes away. The result screen's **Add another
  measurement** replaces it.

### Milestone

- Chips, then the text field with focus ("What happened?", placeholder from
  `Copy`).
- Category is a wrapping row of six labelled chips (`FlowLayout`, tinted from
  `RecordStyle`), defaulting as now.
- `WhenControl`.
- **Add photos / tags** is a disclosure over the existing photo picker and
  `TagPickerView`.
- Save opens the milestone's detail. From there, Done returns to the origin.

### Photos: upload first

`PhotoImporter` already reads and queues on pick. What changes is what
happens after:

- The add sheet's Photos option opens the `PhotosPicker` directly.
- Once items are picked, a **Photos** form opens over the import. It shows
  **Who's in these?** (chips, multi-select, preselected only from the person
  page it was opened on), a **Caption**, **Tags**, and a list of the picked
  photos. Each row shows its thumbnail, its own date ("Taken …", or "No date in
  photo: using today" plus a **change** action), and its status (Uploading,
  Uploaded, Failed with Retry).
- Choices apply to the whole batch and are labelled that way. They are queued as
  `AddPeopleToPhoto`, `UpdatePhotoTags` and `UpdatePhoto` (with
  `inputType: "keep"` unless the date was changed) behind each photo's upload,
  using the queue's dependency gate as the person-tag path does now.
- **Done** closes the form and returns to the origin, leaving the uploads
  running. The existing bottom progress bar continues to show pending work.
  Closing the form never cancels or discards an upload.
- `PhotoImporter` must return the EXIF-missing flag rather than silently
  substituting "now", so the form can show it.
- Photos imported from the global **+** are no longer tagged with anyone
  automatically.

---

## 7. Phase 3 — person page and History

### Person page

Rebuild `PersonDetailView`:

- **Header:** avatar, name, age and "born …", a person switcher (a menu of the
  roster in `chipOrder`), and **+** where permitted.
- A segmented control directly under it: **Story · Photos · Growth ·
  Activities**. Switching person keeps the tab. The selected tab is part of
  the deep link.
- **Story:** a short overview (latest measurements with "Measured … ago",
  a compact active-season link, and at most one at-this-age strip from phase 4),
  then day summaries grouped into age chapters (`storyChapters`,
  `chapterTitle`, `grewLine`). It has a **Jump to age** menu, an
  **All / Milestones** toggle, milestone search, and an oldest/newest order.
  The empty state is `Copy.person.nothingYet`.
- **Photos:** the gallery grid scoped to this person (`PhotoFilter` with the
  person set), with date and tag filters, plus **Open in Photos →**.
- **Growth:** latest height and weight with their own dates and percentiles,
  the chart (`ageChart` port) with a height/weight toggle and optional faint
  sibling curves (**Show siblings**), the measurement list, and **Measure**.
- **Activities:** `PersonSeasonView`'s content, folded in. `/person-activities`
  links land here.

The separate `MeasurementListView`, `MilestoneListView` and `PersonPhotosView`
destinations become unused once each tab covers them. They are deleted in
phase 6.

### History (replaces `TimelineView`)

- Built from the store: `DaySummary` (port of `daySummary.ts`) groups each
  day. Milestones are full cards, height and weight for one person on one day
  are one checkup row (with a count if there are extra readings), the
  remaining photos form a mosaic ("12 photos · Clara, Jake") that opens that
  photo set, birthdays are "🎂 Jake turned 6" dividers, and events are one card
  each with the family's results. Photos attached to a visible milestone or
  event are not repeated in the mosaic.
- `history.ts` port: month sections with pinned headers
  (`LazyVStack(pinnedViews:)`), and a **Jump to year** menu from the timeline's
  `years`.
- Filters are one row: person chips, then a **More** menu with Show (types)
  and Tags, plus **Clear**. `.searchable` searches milestones and shows
  `Copy.history.resultsFor`.
- Activity appearances aren't in SwiftData. Fetch them with
  `GetFamilyTimeline { from, to, includeActivities: true }` for the visible
  years, and cache them next to the activity snapshots so History still shows
  events offline. Don't add them to the sync pull in this plan.
- As on the web, History only shows photos tagged with someone. Note this
  rather than fixing it in one client.

Opening a record from History or Story and coming back must keep the scroll
position and filters. Hold filter state above the `NavigationStack`, not in
the pushed view.

---

## 8. Phase 4 — Same age and Growth

**Same age** (new screen, `Views/SameAge/`):

- Title: **At {age}**, with **Younger** / **Older** buttons stepping on the
  `ageStep` grid, and direct entry (a years/months picker, or weeks for babies).
- One row per person who has reached that age, from `GetSameAge`. Each row
  shows the nearest photos, measurements and milestones, each with its actual
  age. People with no records collapse to one line ("no records at this age").
  Linked households are included, as on the web.
- Opened with a person and an age from a record, a person page, or a deep link.
  Opened directly, it uses the youngest own child's current age (`ageMonths:
  nil` with `from`).
- The response is cached per (anchor, age) for the session only. Offline with
  no cached response, the screen says so instead of showing empty rows.

**Strips in context.** A `SameAgeStrip` component, used by:

- the measurement result and detail screens, where it sits under the existing
  comparison and links to **See everything at this age →**
- photo detail, anchored on the person the photo was opened from. For a group
  photo opened from Photos, a chip row of the tagged people chooses the anchor,
  and none is picked invisibly.
- the milestone detail sheet (`Copy.milestoneDetail.atAge`)
- Story's overview, which is hidden for the oldest child

**Growth page** (replaces the per-person `GrowthChartView` as the family view):

- Swift Charts with one line per selected person, aligned by age. A
  segmented Height / Weight toggle.
- Avatar chips choose people, defaulting to the children.
- Percentile bands (Off / Girls / Boys) from `GrowthPercentiles`.
- Tapping a point opens its measurement detail. Drag-to-zoom follows
  `ageChart.ts`'s zoom model, with **Reset zoom**.
- A **Measure** toolbar button opens the measurement form.

---

## 9. Phase 5 — Home

A `HomeView` backed by `GetDashboard { today }` (cached, see §2):

1. **Family strip:** a horizontal row of avatars with name and current age
   (`familyStrip` port), plus a pregnancy countdown, linking to person pages.
   **Add family member** appears at the end.
2. **Nudges:** at most two, dismissible. Dismissed keys go in UserDefaults,
   capped at 100 as on the web. The server decides which nudges exist.
3. **In season:** a compact row per season, with the event and its timing
   (Today/Next/Last) and **Add photos** / **Add results** where
   `canAddResults`.
4. **On this day:** one group per `yearsAgo` ("1 year ago"), with photos and
   milestones.
5. **Recent:** grouped day summaries from `recent`, with **See all** →
   History. The empty state is `Copy.home.nothingRecent`.

Pull to refresh re-fetches the dashboard. A household with little history
should show the strip and Recent's empty state, not a screen of prompts.

---

## 10. Phase 6 — cleanup

Delete `TimelineView`, `QuickAddMenu`, `DateEntryPicker`,
`MeasurementListView`, `MilestoneListView`, `PersonPhotosView`, and the old
`GrowthChartView` once nothing links to them. Keep the legacy deep-link
mappings. Update `claude.md` (tabs, directory tree, "Adding records"). Mark
`adding-plan.md` as superseded where this plan changed its decisions: the
per-tab `+`, **Save and Add Another**, and auto-tagging photos from a person
`+` when the photos weren't added from that page.

---

## 11. Order and testing

Each phase is its own branch, stacked in order: each PR targets the branch
below it, and they merge bottom-up. Per the web plan,
each phase starts only after its web counterpart has been in use for a while.
All seven web phases are already built, so the gate is simply to use the web
version before copying it.

| Phase | Depends on | Tests |
| --- | --- | --- |
| 0 Foundations | — | Ports with the web's fixture cases; DTO decoding; `"today"` → `"date"` payloads |
| 1 Shell | 0 | `DeepLinkTests` for every new and legacy path |
| 2 Fast entry | 0, 1 | `CheckupTests` (one field, both, partial enqueue failure); photo batch metadata queuing order; no inherited person on global photos |
| 3 Person + History | 0 | `DaySummaryTests`, `StoryTests`, `HistoryTests`; appearance cache |
| 4 Same age + Growth | 0, docs | `SameAge` DTO/age-step tests; anchor selection for group photos |
| 5 Home | 0, docs | Dashboard decoding; nudge dismissal and cap; stale snapshot display |
| 6 Cleanup | all | Build with the deleted files gone |

Run the web's five journey checks on a device, not only unit tests: a
checkup for two children, a mixed photo batch spanning dates and children,
finding an old milestone and coming back, siblings at one age from a group
photo, and a competition with late results. Run them once in airplane mode as
well: entry should still work, History and Story should still render, and Home
and Same age should show their cached or offline states.

---

## 12. Out of scope

- New record types, or any change to what is stored.
- Native Tags vocabulary management and Face review (web-only; linked from the
  account menu).
- Import/Export and Admin.
- Chat internals, since it only moves into the account menu.
- iPad-specific layouts beyond what `TabView` and `NavigationStack` give for
  free.

---

## 13. Open questions

- **Tab set.** The web plan's text proposes Home · History · + · Photos ·
  Family with Chat secondary. The built web bar is Home · Photos · + · Growth ·
  Chat, with History in the account menu on phones. This plan follows the
  build except for Chat, which stays out of the app's tab bar either way. If
  the web moves to the plan's version, phase 1 changes to match; decide this
  before starting phase 1.
- **Activities as a tab.** The app has an Activities tab now, and results entry
  on iOS is the main way results get recorded. The add sheet's Result shortcuts
  cover open events. Check that moving Activities under the account menu
  doesn't make backfilling noticeably harder before removing the tab.
- **Nudge dismissal across devices.** Dismissals are per-browser on the web and
  would be per-device here. A nudge dismissed on the phone would come back on
  the web. That's acceptable for now, and a server-side dismissal would fix both.
- **Offline Home.** A cached dashboard shows yesterday's "today" (birthdays, open
  events). Decide whether a stale cache older than a day should hide those time-sensitive
  sections, or keep them with a stale marker.
