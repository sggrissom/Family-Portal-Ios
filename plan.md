# Widgets plan: Home Screen, Lock Screen, StandBy and CarPlay

Status: Phase 0 done; Phases 1–4 implemented (`widgets/1-on-this-day` … `widgets/4-memory`).
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
