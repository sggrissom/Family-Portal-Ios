# Widget redesign plan

Status: proposed; documentation only. The first widget implementation is working, but the presentation and content need a second pass.
Updated: October 11, 2026. Reviewed against iOS main `3c4c137` and the current widget layouts.

This redesign is the next widget work. The original delivery plan below is retained as historical context; its catalogue and prospective implementation notes are superseded where this section differs. Keep the existing snapshot architecture, account reset behavior, filters, rotation and deep links.

## What needs to change

- **Large Memory wastes its canvas on text.** A short milestone appears beneath a header, a prominent shuffle button, and almost an entire empty card. `MemoryView` reuses `OnThisDayView`; `WidgetTimeline.memory` supplies one item, and `LargeMomentView` renders it as a two-line footnote followed by a spacer. Its larger text fallback runs only when there are no captions, so this ordinary text-only case never reaches it.
- **Family Ages silently leaves people out.** `FamilyAgesView` takes the first four rows when a birthday exists (five otherwise), while only offering a small Home Screen size. A six-person family cannot fit, and the birthday sentence can truncate. This is a content/size mismatch, not a request for smaller fonts.
- **The Quote direction is good.** One readable quote with attribution is a useful small widget. Improve its hierarchy and long-text behavior without turning it into a dashboard.
- **Layouts must work with the actual content and appearance.** Translucent/tinted appearance needs readable hierarchy without relying on a colored background, and a photo-first layout needs an intentional text-only fallback.

## Product direction and size contract

Make each widget answer one question: what memory can I enjoy, what happened around this date, what did someone say, or how is my family growing? Larger sizes should offer a richer composition, not simply stretch the small card.

| Widget | Small | Medium | Large | Lock Screen / StandBy / CarPlay |
| --- | --- | --- | --- | --- |
| Memory | One photo with a short caption, or a prominent quote/milestone | Photo and its own context side by side; text-only gets the full width | One featured memory: a dominant image with context, or an intentionally composed text card | Keep existing small-surface support; verify background removal and tinted rendering |
| On This Day | One dated memory | Featured image/text with truthful date context | Up to four available photos with their own captions, or a text-led composition when photos are absent | Keep rectangular text presentation and small-surface support |
| Quote | Quote first, person/date second | More room for the quote and attribution, not more unrelated records | Do not add a large size in this pass | Keep rectangular support; prioritize legibility |
| Family Ages (gallery name: Family) | Selected person, otherwise birthday/family spotlight; never a partial roster labeled as the whole family | Family overview: two columns of three people, with a separate birthday area | More generous overview with room for additional family members and birthday context | Inline/rectangular show one person or birthday, not a chopped-off roster |

Keep existing widget kind identifiers and configuration values so installed widgets survive the redesign. A gallery display-name change must not create a replacement widget kind. Existing Family Ages person selections remain selected; unfiltered small widgets adopt the explicit spotlight behavior below.

## 1. Memory: let the content determine the composition

- **Photo or illustrated milestone:** let the image occupy most of a large card, with a compact caption area for the person's name, the memory's title and date. Use the milestone's attached photo where available (the builder already resolves `photoRemoteIds`). Do not add an unrelated portrait as though it illustrated the event. Artwork should fit rather than crop when cropping would remove the work.
- **Text-only milestone:** use a substantial, readable headline as the focal point, with person and date as secondary context. A short milestone belongs in the central body of the card rather than a tiny row along the top. Reserve a quiet footer for the date and shuffle. A longer description may use the body area and a clear continuation cue; tap opens the complete record.
- **Quote:** reuse the Quote widget's typography and attribution rules at the appropriate size. Keep the quote intact when it fits; use a readable excerpt when it does not. Avoid duplicating decorative quotation marks already in the stored text.
- **No layout padding with unrelated content.** Memory remains one memory per entry. Do not fill a large card with arbitrary other milestones, repeat the same image, or require a photo for text records to be eligible. Intentional breathing room is fine; a footnote-sized record stranded above a blank canvas is not.
- Move shuffle into a consistently positioned, secondary footer control on medium/large, with reserved space so it cannot cover text. Retain an accessible label and adequate tap target. Hide/disable it when the filtered pool has fewer than two items. Keep the current shared-offset behavior in this pass and document that shuffle affects Memory widgets; per-instance shuffle can be separate work.
- Missing/corrupt cached image files must choose the text composition, not an empty image rectangle. `hasImage` currently only checks for a filename; rendering must also account for load failure. An untitled photo with no usable image should use an honest unavailable/refresh state or another eligible item, not a fabricated description.

## 2. On This Day: richer without misleading associations

- Keep its multi-item behavior separate from Memory's single-record composition. Use a dominant image for one photo; balanced layouts for two to four. Do not reserve empty grid cells.
- If there are no photos, feature one milestone/quote prominently and add at most two clearly separated, dated text records when there is room. With only one record, use the same intentional text composition as Memory.
- Captions must identify the record they describe. The current medium layout can choose another text item from the day's pool, and the large layout can pull captions from other years; do not present that text as the featured photo's caption. Show another record in a distinct block with its own person/date and destination.
- The snapshot includes a ±2-day anniversary window. Only exact-day matches should say “On this day” in the card; nearby records should say “Around this day” with the actual date. Memory fallback must say “A memory,” not imply an anniversary. Preserve the current selection window.
- Every separately displayed record in medium/large should open its own photo or milestone using supported widget links. A one-record composition uses that record as the whole-widget destination. Keep shuffle isolated from navigation.

## 3. Family: useful for six people and larger households

### Overview sizes

- Add `systemMedium` and `systemLarge` to the existing Family Ages widget. Medium is the recommended family-overview size in gallery copy.
- Medium baseline: a compact “Family” heading, six readable name/age cells in two columns of three, and a dedicated birthday footer. Large uses a roomier two-column roster, targeting eight people at standard text size, plus birthday context. Optional portraits are deferred; names and ages should carry the design.
- Offer an optional **People** selection for the overview so a household with parents, children, and linked relatives can choose the intended roster explicitly. Unset means the existing ordered family set; do not infer “children” from the youngest generation. Preserve the existing single-Person setting for compatibility and spotlight use; a nonempty People selection takes precedence, otherwise Person, otherwise the existing family set. Explain this precedence in configuration copy.
- Use stable identity and order. Do not rotate a partial list and imply everyone is visible. If the selected set exceeds capacity, reserve a visible “+N more · Open family” indicator; capacity includes the indicator and birthday area. Count every omitted member. Larger text may reduce capacity, but omissions must remain explicit.
- Ages should use existing app formatting (including infant and pregnancy summaries). Missing ages should be explicit when a selected person cannot supply an age, rather than silently dropping that selection. Do not show yesterday's age or birthday as current beyond the snapshot horizon.

### Small and accessory sizes

- A selected person gets their name and age as the focus, plus birthday context if relevant.
- With no person selection, lead with the next birthday within the existing 14-day window. Use separate lines such as name, “Turns 12,” and “In 4 days”; on the day use “12 today!” Keep the essential age/countdown visible instead of ending at “in…”.
- If no birthday is near, show one person's name/age, explicitly labeled “Family spotlight,” and cycle fairly through the effective people set on daily timeline entries. This is a spotlight, never a purported complete family roster. Daily rotation must reach every eligible person.
- Handle same-day birthdays without silently favoring the first person: show two names when they fit, otherwise one plus an explicit additional-birthday count. Overview sizes show more birthday details within their reserved area.
- Accessory sizes use concise one-person/birthday copy. Keep privacy-sensitive text handling. Preserve the dashboard destination unless a person destination is verified through the existing router.

## 4. Shared visual and content rules

- Use a consistent hierarchy: small context label, meaningful content as the focal point, quiet attribution/date, secondary action. Avoid repeating widget names and large decorative symbols at the expense of content.
- Favor readable semantic text sizes and wrapping; never solve the six-person layout by shrinking every label. Long names may truncate only after allowing appropriate space; birthday age/countdown must stay understandable. Long quotes/milestones may show an excerpt and open the complete record.
- Check full-color, tinted/accented and vibrant appearances, light/dark backgrounds, and removed widget backgrounds. Text must remain legible independently of photos or tint; use an appropriate scrim for text over photos in full color.
- Make signed-out, empty filter, no quotes, unavailable image and stale snapshot states deliberate at every supported size. Never broaden a person/content filter merely to fill space, or substitute another account's data.
- Gallery descriptions/previews should explain the sizes honestly and include realistic six-person, short-text and photo examples. Retain synthetic placeholders for signed-out previews.

## Implementation sequence

These are follow-up implementation PRs; this PR changes only this plan.

- [x] **A — Content-aware memory layouts.** Update `FamilyRecordWidgets/OnThisDayWidget.swift`, `MemoryWidget.swift`, `QuoteWidget.swift` and `WidgetComponents.swift`. Share small presentation components where useful, but separate single-memory and multi-record composition. Add missing-image handling, reserved shuffle space and truthful date captions. Reuse existing item metadata before expanding the snapshot.
- [ ] **B — Family overview and spotlight.** Update `FamilyAgesWidget.swift`, `WidgetIntents.swift`, `Shared/WidgetTimeline.swift` and `WidgetCopy.swift`; add medium/large layouts, optional People selection, visible overflow and explicit spotlight rules. Carry stable person IDs through `FamilyAges.Row` and structured birthday metadata (person ID, turning age, days remaining) instead of parsing display strings. Adjust `WidgetSnapshot.swift` and `WidgetSnapshotBuilder.swift` only as needed; retain existing family ordering and precomputed daily ages.
- [ ] **C — Compatibility and visual acceptance.** Add realistic previews, targeted selection/copy tests, simulator screenshots, and installed-widget upgrade checks. Verify the existing iOS 18 minimum and supported surfaces, including the original still-open CarPlay rendering check. CI must build the embedded extension and pass tests.

Keep the extension offline and file-only, preserve image downsampling/budgets, snapshot atomic writes and sign-out cleanup. For new snapshot fields, use backward-compatible optional decoding/defaults where safe; bump the version only when older readers would misinterpret data. Verify behavior with old snapshots and existing saved intents. No backend change is expected for this redesign; verify existing deep-link destinations before adding new ones.

## Acceptance checklist

- [ ] Render a synthetic short, photo-less milestone in a large widget: the memory is the visual focus, shuffle is secondary, and there is no unused photo-grid area.
- [ ] Memory previews cover short/long milestone, short/long quote, portrait/landscape photo, artwork, and unavailable image at each supported size.
- [ ] Six selected people all appear simultaneously in medium Family at standard text size, with a readable birthday footer. Test the full household and linked relatives separately; selection must make the intended roster explicit.
- [ ] Family fixtures cover 0, 1, 4, 6, 8 and 10 people, long/duplicate names, infant/pregnancy ages, missing birthday, same-day birthdays and larger text. Overflow counts are accurate and spotlight selection is fair.
- [ ] Birthday countdown is readable and correct today/tomorrow/within the window; local midnight and expired snapshots do not leave incorrect current-day copy.
- [ ] On This Day previews cover 0–4 photos, one text record, multiple years and nearby dates. No unrelated caption is presented as a photo's context; taps open the displayed record.
- [ ] Check signed-out, stale, empty-filter, offline and old-snapshot cases. Existing widget kinds, person selections, rotation choices and record links survive an upgrade.
- [ ] Capture Home Screen screenshots at small/medium/large, including a narrow iPhone layout and tinted mode; check accessory, StandBy and CarPlay presentations on supported simulators/devices. Verify VoiceOver order and shuffle labeling. Unit tests alone do not establish layout quality.

---

# Original delivery plan: Home Screen, Lock Screen, StandBy and CarPlay

Status: Phase 0 done; Phases 1–5 implemented as stacked PRs (`widgets/1-on-this-day` … `widgets/5-quote-ages`). The CarPlay Simulator check (risk 3) is still open.
Written: October 10, 2026, against iOS `ac6a533` and the Family Portal backend on local main.

## Goal

Bring the family record onto the surfaces people look at without opening the app:

- **On this day**: a photo or milestone from this date in an earlier year ("3 years ago · Clara took her first steps").
- **Memory**: a random photo, milestone or quote that rotates through the day, with optional filters.
- **CarPlay**: the same content, glanceable, on the car's dashboard.

Widgets must work when the app hasn't been opened for days, never leak one account's family to the next, and never need the network or the keychain to render.

## Findings

### CarPlay: a widget, not a CarPlay app

- A **CarPlay app is not an option.** CarPlay apps need an Apple-granted entitlement in a fixed category list (audio, communication, navigation, EV charging, parking, quick food ordering, fueling, driving task, and voice-based conversational apps since iOS 26.4). No category fits a family photo or memory app, and apps must use Apple's templates, which have no photo-browsing template.
- **iOS 26 brings WidgetKit widgets to every CarPlay car.** Any app's widget can appear there. It doesn't need to be a CarPlay app. The user adds it from iPhone Settings → General → CarPlay → the car → Widgets.
  - CarPlay uses the **`systemSmall` family**, rendered StandBy-style: large type, the background removable, and content possibly drawn in **accented mode** (tinted, on glass). To support CarPlay, ship a `systemSmall` widget that still reads well in that mode.
  - Opting out is per widget and family: `.disfavoredLocations([.carPlay], for: [.systemSmall])` (iOS 26+, so it goes behind `#available` with our 18.0 deployment target).
  - Because CarPlay shows the same `systemSmall` widget, the StandBy and CarPlay work is the same work.
- **Unverified (check in the CarPlay Simulator before we commit to a design):** how a full-color photo looks in CarPlay's accented mode, and whether `.widgetAccentedRenderingMode(.fullColor)` keeps it in color. If photos look bad there, the small widget's accented layout leads with text ("3 years ago today", the milestone, a name) and drops the photo or shows it desaturated.

### WidgetKit constraints that shape the design

- **Widgets render from a timeline.** iOS limits reloads to roughly 40–70 a day. Rotation should come from pre-computed timeline entries, not reloads.
- **Extensions get little memory** (around 30 MB). Images must be downsampled to widget size before they reach the extension. A full-resolution photo in a widget silently fails to render.
- **Interactive buttons** (`Button(intent:)`, iOS 17+) can drive a "shuffle" without opening the app.
- **Configuration** goes through `AppIntentConfiguration` (iOS 17+), for example picking a person or a content type, with `AppEntity` types whose options come from local data.

### What the app has today

| Need | What exists | Consequence |
| --- | --- | --- |
| On-this-day data | `GetDashboard` → `onThisDay: [DashboardYearDTO]`, rendered in `Views/Home/HomeView.swift:216`. Backend rule (`backend/dashboard.go:158`): 1–30 years back, the same calendar day **±2 days**, up to 8 photos per year, plus every milestone in the window. | The rule is simple to compute locally from SwiftData for **any** date, so the widget can be pre-filled for days ahead without the server. |
| Records | SwiftData holds every `Photo` (`photoDate`, `remoteId`, `taggedPeople`), `Milestone` (`date`, `category` including `.quote` and `.artwork`, `descriptionText`, `photoRemoteIds`) and `Person`. | Random-memory and person filters can be computed locally. |
| Image bytes | Usually not stored. `Photo.imageData` is nil for synced photos, which are fetched with a bearer token through `PhotoImageCache` (`Services/PhotoImageCache.swift`), variants `small/thumb/medium/large/xlarge`. | The **app** has to fetch and downsample the images and hand files to the widget. |
| Store location | `DataStore` uses a default `ModelConfiguration`, so the store sits in the app's private container. | The widget can't open it. Moving the store into an App Group means migrating every install's database: risky, and unnecessary (see the architecture below). |
| Tokens | `APIClient.storeToken` writes keychain items with no access group (`APIClient.swift:584`). | The widget can't authenticate. Again, the architecture below doesn't need it to. |
| Sign-out / account switch | `LocalDataReset.erase(.everything, …)` sweeps every cache (`Services/LocalDataReset.swift`). | The widget store must be added to this sweep, followed by `WidgetCenter.shared.reloadAllTimelines()`. |
| Deep links | `DeepLink` parses the paths in `backend/universal_links.go`. There is no photo or milestone destination. The web routes are `/view-photo/<id>` and `/milestone/<id>`. | Tapping a widget can open Home today. Opening the photo or milestone itself needs a new `DeepLink` case and the same paths added to the backend list (the two lists must match). |
| Background work | No `BGTaskScheduler` use, no `UIBackgroundModes`. | Needs adding so the widget refreshes when the app isn't opened. |
| Project | One app target and a test target, using Xcode 16 synchronized folders (`PBXFileSystemSynchronizedRootGroup`), team `7S5TBT3VAE`, bundle `com.familyrecord.ios`. CI runs `xcodebuild build test` on the simulator. | Adding an extension target means editing `project.pbxproj` and the developer portal (App Group, new App ID). |

## Architecture: the app publishes a snapshot, the widget only reads it

```
SwiftData + PhotoImageCache (app)
        │  WidgetSnapshotBuilder: pick items, download + downsample images
        ▼
App Group container  group.com.familyrecord.ios/Widgets/
  ├── snapshot.json        (WidgetSnapshot, versioned)
  └── images/<remoteId>.jpg (≤ ~700 px long edge, JPEG q≈0.8)
        │  WidgetCenter.reloadAllTimelines()
        ▼
Widget extension: reads files only. No network, keychain or SwiftData.
```

Why this instead of letting the widget fetch:

- **Nothing to migrate.** The SwiftData store and keychain items stay where they are.
- **Account safety lives in one place.** A sign-out deletes one directory. A widget holding its own token could outlive the session.
- **Works offline and fits the memory limit.** Images are already small when they reach the extension.
- **It follows how the app already works**: local-first, with the server answers cached on disk.

### The snapshot

```swift
struct WidgetSnapshot: Codable {
    var version: Int                 // bump on format change; the widget treats unknown versions as empty
    var generatedAt: Date
    var ownerUserId: Int             // checked against nothing in the widget, but kept for diagnostics
    var people: [WidgetPerson]       // id, first name — for the configuration picker and captions
    var onThisDay: [String: [WidgetItem]]   // "YYYY-MM-DD" → items, for today + the next 13 days
    var pool: [WidgetItem]           // ~40 items for "Memory", weighted toward photos
}

struct WidgetItem: Codable, Identifiable {
    var id: String                   // "photo:123" / "milestone:45"
    var kind: Kind                   // photo, milestone, quote, artwork
    var date: String                 // record day
    var yearsAgo: Int?               // set for on-this-day items
    var title: String                // "First steps", the quote text, or the photo title
    var personIds: [Int]
    var imageFile: String?           // relative to images/, nil for text-only
    var link: String                 // site-relative path for widgetURL
}
```

- **Fourteen days of "on this day"** means the widget stays correct for two weeks with no app launch. After that it falls back to the pool with an "Open Family Record to refresh" footnote.
- **Image budget:** at most ~60 files (around 5 MB). Each publish deletes files no longer referenced. Item selection prefers photos already in `PhotoImageCache`'s disk cache, so a publish on cellular downloads little.
- **Item order is fixed when the app publishes**, and the widget walks it by time slot. Each timeline entry is `pool[(slot + seed) % count]`, so a reload doesn't reshuffle what's on screen.

### When the app publishes

1. At the end of `SyncService.performFullSync()`. This covers launch, foreground, sign-in and reconnect.
2. When the scene moves to `.background`, cheaply, only if older than 6 hours.
3. A **`BGAppRefreshTask`** (`com.familyrecord.ios.widget-refresh`), scheduled for after the next local midnight. It publishes from the local store, and pulls first if the network is up. iOS runs these opportunistically, which is why the 14-day horizon exists.
4. `LocalDataReset.erase(.everything)` deletes the directory and reloads all timelines, so a signed-out widget shows a neutral "Sign in to Family Record" state.

## Widget catalogue

| Widget | Families | Configuration | Notes |
| --- | --- | --- | --- |
| **On this day** | `systemSmall`, `systemMedium`, `systemLarge`, `accessoryRectangular` | Person filter (optional) | Small: one photo plus "N years ago". Medium: photo plus milestone text. Large: a 2×2 mosaic for the best year plus captions. Lock Screen: text only ("2 years ago: Clara's first tooth"). Falls back to Memory when today has nothing. **This is the CarPlay widget.** |
| **Memory** | `systemSmall`, `systemMedium`, `systemLarge` | Content: Everything / Photos / Milestones / Quotes. Person (optional). Rotate: hourly / every 6 hours / daily. | A Shuffle button (`Button(intent: ShuffleMemoryIntent())`) on medium and large advances a stored offset in the App Group and reloads that widget kind. |
| **Quote** *(optional)* | `systemSmall`, `systemMedium`, `accessoryRectangular` | Person | Text only, so it renders well in StandBy, CarPlay and on the Lock Screen. A cheap add-on once Memory exists. |
| **Family ages** *(later, optional)* | `accessoryRectangular`, `accessoryInline`, `systemSmall` | Person | "Clara · 3y 4m", "Theo's birthday in 5 days". Uses `FamilyStrip.compactAge`. Not a memory widget, but the most glanceable thing for CarPlay and the Lock Screen. |

Tapping any widget opens `widgetURL`, the item's `link`. Phase 1 uses `/dashboard`. Phase 3 adds `/view-photo/<id>` and `/milestone/<id>`.

Rendering rules for every widget:

- Read `@Environment(\.widgetRenderingMode)`. In `.accented` or `.vibrant`, lead with text and mark the photo `.widgetAccentedRenderingMode(...)`. Pick the mode after checking it in the CarPlay Simulator.
- `.containerBackground(for: .widget)` so StandBy and CarPlay can remove the background.
- `.privacySensitive()` on names and text in accessory families, so a locked phone can redact them.
- Fixed `.placeholder` content (no real photos) and a `getSnapshot` that shows real content when a snapshot is available. The widget gallery preview should show the family, not a stock photo.

## Delivery: stacked PRs

Each phase ships as its own PR based on the previous one, as with earlier plans. CI (simulator build + unit tests) is the gate.

### Phase 0: project setup (one-time manual step in Xcode)

Adding an extension target by hand-editing `project.pbxproj` is error-prone. It's quickest to do this part in Xcode and commit the result:

1. In the developer portal, create App Group `group.com.familyrecord.ios` and App ID `com.familyrecord.ios.widgets`. Enable the App Group on both App IDs.
2. In Xcode, File → New → Target → **Widget Extension**, named `FamilyRecordWidgets`, with no Live Activity and no configuration intent (we add our own). Embed it in the app.
3. Turn on the App Groups capability on both targets with the group above. Set the extension's deployment target to 18.0.
4. Create a `Shared/` synchronized folder that belongs to **both** targets, for the snapshot model and the store.
5. Confirm CI still builds: the scheme builds the embedded extension as a dependency.

Alternatively, I can attempt the `pbxproj` edit and let CI validate it, but the portal step still needs you.

### Phase 1: snapshot pipeline and "On this day"

- `Shared/WidgetSnapshot.swift` (model plus version) and `Shared/WidgetStore.swift` (atomic read/write in the App Group, reusing the atomic-write pattern the app already tests in `AtomicWriteTests`).
- `Utilities/OnThisDay.swift`: the backend rule as a pure function over plain values (1–30 years, ±2 days, ≤8 photos per year). **Leap days:** Go's `AddDate(-1, 0, 0)` on Feb 29 normalizes to Mar 1, but `Calendar.date(byAdding:)` gives Feb 28. Match Go so the widget and Home agree.
- `Services/WidgetSnapshotBuilder.swift`: SwiftData → items → downsample images (`CGImageSourceCreateThumbnailAtIndex`) → write → prune → `WidgetCenter.reloadAllTimelines()`.
- Hooks: after a full sync, on backgrounding, and in `LocalDataReset`.
- The extension's `OnThisDayWidget` (static configuration first), with `widgetURL("/dashboard")`.
- Tests: the on-this-day rule (window edges, year limits, leap day, the photo cap), the builder's selection and pruning (with a fake image source), and that a reset deletes the directory.

### Phase 2: CarPlay and StandBy polish

- The accented and vibrant layouts for `systemSmall`, a `containerBackground` that can be removed, and a check in the CarPlay Simulator (Xcode → I/O → External Displays → CarPlay) and StandBy.
- `BGAppRefreshTask` registration (Info.plist `BGTaskSchedulerPermittedIdentifiers` plus `UIBackgroundModes: fetch`), scheduled for after local midnight. *As built, it publishes from the store without pulling first: a background launch has no restored session, so a pull would have to restore one outside the normal sign-in path.*
- The "stale" footnote once the snapshot's horizon has run out.

### Phase 3: deep links into the record

- `DeepLink.photo(remoteId:)` for `/view-photo/<id>` and `DeepLink.milestone(remoteId:)` for `/milestone/<id>`, routed through `DeepLinkRouter` → `AppNavigator` (resolve the server id to the local `UUID`, as `.person` does).
- **Backend PR:** add both paths to `universal_links.go`. Strictly speaking `widgetURL` doesn't need the association, but the "same list" rule in `DeepLink.swift` should hold, and push notifications can then use these destinations too.
- Tests in `DeepLinkTests`.

### Phase 4: "Memory" widget, configuration and shuffle

- `PersonEntity: AppEntity`, read from `snapshot.people`, plus `MemoryWidgetIntent: WidgetConfigurationIntent` (content type, person, rotation).
- The rotating timeline (24 h of entries at the chosen interval, `.after` at the end).
- `ShuffleMemoryIntent` for the interactive button.
- The person filter on "On this day" too.

### Phase 5 (optional): Quote and Family ages

These only need small additions to the snapshot. Add them if Phase 4 lands well.

## Risks and open questions

1. **Photos of the kids on a car screen** can be seen by passengers and anyone glancing in, and on a borrowed or rental car's display. Should "On this day" show photos in CarPlay at all, or text only there (`disfavoredLocations` on the photo widget plus a text-only widget for the car)? My recommendation is to allow photos, since the user adds the widget deliberately, and to offer the text-only Quote widget as the car-friendly option.
2. **Linked households.** The local store includes linked households' people and photos (`familyRemoteId`). Does the dashboard's `ListFamilyPhotos` include them? The local rule should match whatever Home shows. Verify against `backend/dashboard.go` and `ListFamilyPhotos` before Phase 1.
3. **Rendering in accented mode is unverified** (see Findings). It could push the CarPlay design toward text-first.
4. **Background refresh isn't guaranteed.** The 14-day horizon plus a refresh on every sync covers this. A user who never opens the app will see the stale footnote after two weeks.
5. **Phase 0 needs the developer portal** (App Group and a new App ID). Neither CI nor I can do that.

## Sources

- Apple, [What's new in widgets (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/278/): CarPlay uses `systemSmall` in a StandBy style, the `disfavoredLocations([.carPlay], …)` opt-out, accented rendering.
- Apple, [Turbocharge your app for CarPlay (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/216/).
- 9to5Mac, [iOS 26 adds CarPlay widgets](https://9to5mac.com/2025/10/30/ios-26-adds-carplay-widgets-a-major-new-feature-for-your-vehicle/): any iPhone widget, set up in iPhone Settings.
- 9to5Mac, [iOS 26.4 adds voice-based AI apps to CarPlay](https://9to5mac.com/2026/02/18/ios-26-4-adds-support-for-voice-based-ai-apps-to-carplay/): the CarPlay app categories.
- Local source: `backend/dashboard.go` (`onThisDay`), `backend/universal_links.go`, `frontend/main.tsx` (the web's photo and milestone routes).
