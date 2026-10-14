# Global search (iOS)

The app's side of global search. The design, the backend `Search` proc and the
query rules are in `Family-Portal/docs/plans/global-search.md`. This file only
covers what differs on iOS. Web is the design reference, so wording, groups,
order and chips match it.

## Entry point

The tab bar is full (Home · Photos · + · Growth · More), and a sixth item would
push into the overflow. Search goes in the **top bar of every tab root**, as a
`magnifyingglass` `ToolbarItem(placement: .topBarTrailing)` next to
`AccountMenuButton`. That places it beside the account button the same way the
web places 🔍 beside the account initial. Both are added by one shared toolbar
modifier, so no root can forget one.

Tapping it pushes `.search` onto the current tab's stack through
`AppNavigator`, not a sheet, for the same reason web uses a route: open a
result, go back, and the results are still there. The field is focused on
appear.

## Screen: `SearchView`

- `.searchable(text:placement: .navigationBarDrawer(displayMode: .always))`
  with `.searchFocused`, so the keyboard is up immediately.
- 250 ms debounce (longer than web, since it's cellular). The previous `Task`
  is cancelled on each keystroke, so stale responses never render.
- Understood chips under the field, each with an ×. Removing one re-sends with
  `ignore`.
- Empty query: person chips from the local `Person` mirror, plus recent
  searches (last 8, `UserDefaults`).
- Sections in the web's fixed order, empty ones hidden:
  - **People.** `PersonRowView`, with quick links to Moments / Photos / Growth.
  - **Moments.** The same row the History list uses, interview answers
    folded the same way.
  - **Photos.** Horizontal thumbnails. Ids are resolved against the local
    mirror first, with the server image as fallback, like `PhotoSearchResults`
    does. "See all" opens the gallery in search mode with the same query and
    people.
  - **Tags, Places, Activities, Books.** Plain rows. Each pushes the existing
    native screen. Places push the gallery filtered by place, and a book pushes
    `BookReaderView`.
- Matched words highlighted with `AttributedString` runs.
- `searchMode == "text"` shows the same "matching words only" footnote the
  gallery shows.

## Offline

The server does the real search (semantic, access rules, activities, books).
Offline, the screen falls back to a **local pass** over the SwiftData mirror:
people by name prefix, and moments and photo titles/descriptions by
prefix-of-word, every term required. A banner reads "Offline: searching what's
on this phone". This needs the same query parser on the device.

## Shared logic (pure, tested)

- `SearchQuery.swift`: Swift port of `parseSearchQuery`, used only for the
  offline pass and for keeping chips stable while a request is in flight. Its
  test table is a copy of the Go table in `search_query_test.go`. When one
  changes, change both (note it in both PR descriptions).
- `SearchText.swift`: folding (case, diacritics), prefix-of-word matching, and
  highlight ranges.
- `RecentSearches.swift`.

`nonisolated` only where nothing MainActor is touched. Category mapping uses
`MilestoneCategory`, which is MainActor, so the parser stays MainActor (see the
memory note on default isolation).

## Plumbing

- `RPCMethod.search`, plus `SearchRequestDTO` / `SearchResponseDTO` (and
  `ActivityHitDTO`) in `APIDTOs.swift`. Optional fields are decoded leniently
  so a newer server adding a group doesn't break older builds.
- `AppNavigator` route `.search(query: String?)`.
- `Copy.search` wording, kept in sync with web `copy.search`. People see
  "Moment".
- A `/search?q=` universal link isn't claimed: no one shares a search, and
  claiming it would send web users into the app.

## Tests

- `SearchQueryTests`: the mirrored parse table.
- `SearchTextTests`: folding, prefix matching, highlight ranges.
- `SearchResultsTests`: DTO decoding (including missing optional groups),
  photo id resolution against the mirror, and stale-response dropping.

No Swift toolchain here. CI's macOS build/test is the first compile, and
screens are not run in a simulator before review.

## Phases

1. DTOs, RPC, parser and text helpers, with tests.
2. `SearchView` and the toolbar entry point on every tab root.
3. Offline local pass and recent searches.

Start after the web phases 1–3 are on staging.
