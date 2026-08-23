# Family Portal iOS — Pre-Release Improvement Plan

Scope: no new product ideas. Everything here is a bug in what exists, a piece of
backend/website functionality the app was clearly meant to use, or a gap that
blocks an App Store submission.

Reference repo: `../Family-Portal` (Go backend + React frontend). All backend
claims below are cited to a file in that repo.

---

## Status — 23 August 2026

Every item now carries a status line under its heading. The original analysis is
left as written: it is the record of what the bug *was*, and several of them were
only findable once.

**Every item in this plan is closed.** Thirty-eight were fixed; two — §22 and §29
— are closed by decision, and the decision is written down under each of them
rather than left as an absence.

The last four to land:

| | Item | How it closed |
| --- | --- | --- |
| §40 | Age string vs. the server's | The two did **not** agree. `AgeCalculator` used `Calendar.dateComponents`, which clamps "31 March plus one month" to 30 April and calls it a month where the server compares day numbers and calls it none — so every month-end birthday read differently on one day of every month. Due dates were not handled at all. The server's arithmetic is ported and its answers are the tests. |
| §18 | `IPHONEOS_DEPLOYMENT_TARGET` | Now `18.0`. Nothing in the target needs more: no `@available`, no `#available`, no iOS 26 API anywhere in the source. 18 rather than the 17 the code implies, because the extra major only buys devices nobody will test on. |
| §33 | `SyncQueue` in `UserDefaults` | Moved to `SyncQueue.json` in Application Support, written atomically, with a one-time migration that adopts whatever an older build left behind — a pending operation is a change the server has never heard about, so dropping it would lose data that exists nowhere else. |
| §36 | `TimelineView` filters in memory | Person and year pushed into `@Query` predicates via `TimelineResultsView`; search debounced; the year chips memoised instead of recomputed per render. |

Two things arrived that this plan did not name, because the backend grew them
after it was written:

- **Activities.** Read, score and set up a dance season from the phone. Its own
  plan is `activities-plan.md`; phases 1–3 have landed. Phase 4, offline
  writes, was optional from the start and is not built — activity writes stay
  online because their refusals are ones a device cannot predict.
- **Deep links.** Every push payload carries a `destination` naming the web
  route for its content, and the server publishes an app-site association
  claiming exactly the paths this app has a screen for. Both halves are wired:
  a tapped notification and a followed `familyrecord.app` link open the same
  screen.

What is left before a submission is no longer in this repository. Push has been
tested on a real device in both APNs environments. Still outstanding: `IOS_APP_ID`
being set on the server, so the app-site association file is published at all —
without it the deep links resolve to the website — and the App Store listing
itself. The contract the app is built against is written down in
`../Family-Portal/docs/mobile-api.md`.

---

## P0 — Correctness bugs that break shipped features

### 1. Chat message decoding uses the wrong key names (silently)

> **Done.** `ChatMessageDTO` decodes camelCase.

`Services/ChatDTOs.swift` decodes `ChatMessageDTO` with snake_case keys
(`family_id`, `user_id`, `user_name`, `created_at`, `client_message_id`).
The Go type emits camelCase (`backend/chat.go`, `type ChatMessage`):

```go
Id int `json:"id"`; FamilyId int `json:"familyId"`; UserId int `json:"userId"`
UserName string `json:"userName"`; CreatedAt time.Time `json:"createdAt"`
ClientMessageId string `json:"clientMessageId"`
```

Every mismatched field is read with `decodeIfPresent(...) ?? default`, so
decoding **succeeds** and produces garbage instead of throwing:

- `userId == 0` for every message → `MessageBubbleView` aligns every message as
  if it were someone else's, including your own.
- `userName == ""` → no author names anywhere in the room.
- `createdAt == Date()` → every message timestamps as "now"; `DateSeparatorView`
  collapses the entire history into today.
- `clientMessageId == ""` → optimistic-echo dedup falls through to the fuzzy
  5-second content match in `ChatService.didReceiveMessage`.

Fix: switch `ChatMessageDTO` to camelCase keys. This is the single highest-value
change in the app.

### 2. `DeleteMessage` sends the wrong parameter name

> **Done.** `DeleteMessageRequestDTO` maps `messageId` to `id`.

`DeleteMessageRequestDTO` encodes `message_id`; `backend/chat.go`
`DeleteMessageRequest` reads `id`. The server always receives `id: 0`, so no
delete ever lands. The client deletes locally and swallows the failure
(`ChatService.deleteMessage` only `print`s), so the message reappears on the
next device/pull.

### 3. `SendMessage` sends `client_message_id`, server reads `clientMessageId`

> **Done.** The key is `clientMessageId`, and the fuzzy content match is back to being a safety net rather than the mechanism.

`backend/chat.go` `SendMessageRequest.ClientMessageId` is `json:"clientMessageId"`.
The server therefore persists an empty client id and broadcasts it back empty,
which is exactly the case the fragile fallback in `didReceiveMessage` exists to
paper over. Fix the key and the fallback becomes a true safety net.

### 4. WebSocket protocol names don't match the server

> **Done.** `WSMessageType` and the payload keys are the server's, including `user_online` / `user_offline`, which had no case at all.

`backend/websocket_chat.go` defines:

| Server constant | Wire value | iOS `WSMessageType` |
|---|---|---|
| `WSMsgTypeNewMessage` | `new_message` | ✅ `new_message` |
| `WSMsgTypeDeleteMessage` | `delete_message` | ❌ listens for `message_deleted` |
| `WSMsgTypeUserTyping` | `user_typing` | ❌ listens for `typing`, sends `start_typing`/`stop_typing` |
| `WSMsgTypeUserOnline` | `user_online` | ❌ no case — `ChatService.onlineUsers` is permanently empty |
| `WSMsgTypeUserOffline` | `user_offline` | ❌ no case |
| `WSMsgTypeHeartbeat` | `heartbeat` | ❌ client sends ping frames only |

Consequences: remote deletes never disappear; typing indicators never show in
either direction (`Client.handleIncomingMessage` only handles `user_typing`, so
the app's outgoing typing events are dropped too); `TypingIndicatorView` and the
online-user state in `ConnectionStatusView` are dead code.

The payload field names are wrong in the same way — server `WSTypingPayload` and
`WSDeleteMessagePayload` use `userId`/`userName`/`isTyping`/`messageId`; iOS
declares `user_id`/`user_name`/`is_typing`/`message_id`.

### 5. WebSocket date decoding will still fail after #1–#4

> **Done.** `ChatWebSocketService` decodes through `APIClient.decode`, so there is one tolerant decoder rather than two.

`ChatWebSocketService.handleIncomingMessage` uses
`decoder.dateDecodingStrategy = .iso8601`, which rejects fractional seconds. Go
`time.Time` marshals RFC3339 with nanoseconds. Reuse the tolerant custom
strategy already written in `APIClient.sharedDecoder` (fractional → plain ISO →
date-only) rather than maintaining two decoders.

### 6. Photo title/description edits are silently discarded

> **Done.** `SyncOperationType.updatePhoto` exists and the editor commits through it.

`PhotoDetailView` binds `TextField`s straight to `@Bindable photo.title` /
`photo.descriptionText`, and nothing enqueues a sync operation — there is no
`updatePhoto` case in `SyncOperationType` at all. The next `pullFamilyData` runs
`applyPhotoDTO`, which overwrites both fields from the server. The user's typing
disappears on the next sync.

The backend proc exists: `UpdatePhoto` in `backend/photos.go`. Add
`SyncOperationType.updatePhoto` + `SyncService.updatePhoto(_:)` and call it on
commit (not on every keystroke).

### 7. Deleting a person does nothing durable

> **Done — by removing the affordance.** The backend still has no `DeletePerson`, so the button is gone rather than pretending; the reasoning is written down at the toolbar in `PersonDetailView`.

`PersonDetailView` and `FamilyManagementView` call `modelContext.delete(person)`
directly. There is no `deletePerson` sync operation — and no `DeletePerson` proc
on the backend either (`backend/person.go` exposes `AddPerson`, `UpdatePerson`,
`MergePeople`, `SetProfilePhoto`, …). The person vanishes locally, then
`pullFamilyData` recreates them on the next sync.

Pick one before release:
- add a `DeletePerson` proc to the backend and a matching queued operation, or
- remove the delete affordance from both views and offer `MergePeople` instead.

Doing neither ships a button that appears to work and then undoes itself.

### 8. Queued deletes read a deleted SwiftData object

> **Done.** The local and remote ids are captured before the delete.

`SyncService.deleteGrowthData` / `deleteMilestone` / `deletePhoto` all do:

```swift
modelContext.delete(data)
try modelContext.save()
try await enqueueOperation(..., localId: data.id.uuidString, ...)
```

`data.id` is read *after* the model has been deleted and the context saved.
Capture `let localId = data.id.uuidString` (and the remote id) before the delete.

### 9. Photo library access without a usage description

> **Done — by dropping `PHAsset`.** The capture date is read from the picked data's EXIF, so the app never needs photo-library authorization at all. Better than adding the usage string.

`PhotoGalleryView.photoDate(from:)` calls `PHAsset.fetchAssets(withLocalIdentifiers:)`.
That is PhotoKit, not the sandboxed picker, and it requires photo-library
authorization — but `Info.plist` has no `NSPhotoLibraryUsageDescription`. Add
the key (and request authorization, or drop to the picker's own metadata) before
submission; missing usage strings are both a crash risk and a review rejection.

### 10. Verify the refresh-token lifecycle end to end

> **Done.** The token the server issues is captured and kept; `APIClientRefreshTests` pins the 401 retry, the proactive refresh, and the single decision that ends a session. The server now also accepts the refresh token in the request body, so a native client no longer depends on `URLSession`'s cookie jar (`Family-Portal#86`).

`AuthService.login` calls `setTokens(accessToken: token, refreshToken: nil)` —
the refresh token is only ever obtained opportunistically from a `Set-Cookie`
header in `APIClient.captureTokens`. If `/api/login` doesn't set that cookie on
the native path, every session dies 24h later with no way back except
re-entering credentials. Worth an explicit test against
`backend/refresh_tokens.go` before release rather than after.

---

## P1 — Release-readiness gaps

### 11. There is no auth gate

> **Done.** `ContentView` gates on `authService.isAuthenticated`, behind the version gate.

`ContentView` renders all five tabs unconditionally. Signed out, a first-time
user sees three empty tabs, a Chat tab wired to a nil `ChatService`, and a
sign-in link buried in Settings. Present `LoginView` as a `fullScreenCover` (or
switch the root view) on `!authService.isAuthenticated`.

### 12. A new user cannot start on iOS at all

> **Done.** `CreateAccountView` and `ForgotPasswordView`.

The backend has `CreateAccount` (`backend/users.go`) and
`RequestPasswordReset` / `ValidatePasswordResetToken` / `ResetPassword`
(`backend/password_reset.go`); the website has `auth/create-account.tsx` and
`auth/reset-password.tsx`. The app has neither. Sign-up and forgot-password are
table stakes for a standalone App Store listing.

### 13. No family create/join flow

> **Done.** `FamilyInfoView` and `FamilyMembershipView`, with invite codes.

`backend/users.go` exposes `GetFamilyInfo` and `JoinFamily` (invite code). The
iOS `Family` model even has an `inviteCode` field — but `Family` is never
inserted, synced, or read by any code path outside `PreviewData`. A user who
signs in without a family sees an empty app and no route forward. Same for
`Models/User.swift`, which is dead.

### 14. Wire up the mobile version gate the backend already built for this app

> **Done.** Checked at launch, ahead of auth; `UpdateRequiredView` blocks on `update_required`.

`backend/mobile_version.go` ships `GET /api/mobile-version?platform=ios&appVersion=x.y.z`
(deliberately pre-auth, cached 300s) plus a `CheckMobileVersion` proc, returning
`ok` / `update_available` / `update_required` with `updateUrl` and
`updateMessage`. Nothing in the app calls it. Implement the check at launch and
a blocking screen on `update_required`.

Note: it rejects anything that isn't strict `major.minor.patch` — see #15.

### 15. Version numbers are wrong in two places

> **Done.** `MARKETING_VERSION = 1.0.0`, and Settings reads `CFBundleShortVersionString` + `CFBundleVersion` through `AppConstants.displayVersion`.

- `MARKETING_VERSION = 1.0` in `project.pbxproj` — not valid semver, so the
  version endpoint above returns HTTP 400. Set `1.0.0`.
- `SettingsView` hardcodes `Text("1.0.0")`. Read
  `CFBundleShortVersionString` + `CFBundleVersion` from the bundle so it can
  never drift.

### 16. No push notifications

> **Done.** Registration after login, deregistration before logout, and — since `Family-Portal-Ios#54` — a tapped notification opens the screen its `destination` names.

`backend/push_notifications.go` exposes `RegisterPushDevice` /
`UnregisterPushDevice` (APNs token, platform, sandbox/production environment,
bundle id), and `backend/chat.go:369` already calls `QueuePushNotification` on
every new message. The app never registers for remote notifications, so that
entire server-side path is dark. Add `UNUserNotificationCenter` registration
after login, `RegisterPushDevice` on token receipt, and `UnregisterPushDevice`
on logout.

### 17. Missing privacy manifest

> **Done.** `PrivacyInfo.xcprivacy`, and the privacy policy is linked from Settings.

No `PrivacyInfo.xcprivacy` in the target. The app uses `UserDefaults`
(`SyncQueue.storageKey`), which is a declared-reason API. Required for App Store
submission. Also add the privacy-policy link the listing will need.

### 18. Bundle identifier and deployment target

> **Done.** The bundle id is `com.familyrecord.ios`, matching the keychain namespace, and iPad is dropped (`TARGETED_DEVICE_FAMILY = 1`) rather than claimed and unbuilt. `IPHONEOS_DEPLOYMENT_TARGET` is `18.0`: there is no `@available`, no `#available` and no iOS 26 API in the target, so the floor the code actually implies is 17 — 18 is one major of headroom over that, and the difference is devices nobody would test on.

- `PRODUCT_BUNDLE_IDENTIFIER = grissom.Family-Portal-Ios` — not reverse-DNS, and
  inconsistent with the `com.familyrecord.*` keychain namespace. It is immutable
  after the first App Store Connect upload; decide now.
- `IPHONEOS_DEPLOYMENT_TARGET = 26.2` limits the app to a single point release.
  Lower it to the oldest OS you're willing to support.
- `TARGETED_DEVICE_FAMILY = "1,2"` claims iPad support, but every screen is a
  phone-shaped `TabView` with no split-view layout. Either adapt or drop iPad.

### 19. No tests, and CI only builds

> **Done.** 33 test files, and CI runs `build test` against a simulator.

There is no test target in the project, and `.github/workflows/build.yml` runs a
Debug simulator build with no `test` action. The website repo has a `_test.go`
beside nearly every source file — the asymmetry is why bugs #1–#4 went
unnoticed.

Highest-value first tests:
- Decode fixtures captured from the Go structs (`ChatMessage`, `PersonDTO`,
  `GrowthDataDTO`, `MilestoneDTO`, `ImageDTO`) — catches every bug in P0.
- `SyncQueue` merge/cancel logic (add-then-remove tagging, update coalescing,
  retry cap) — the most intricate untested code in the app.
- `SyncMappers` enum ↔ int/string round-trips and `dateToAPIString` timezone
  behavior.
- `AgeCalculator` boundaries.

Then add `-destination 'platform=iOS Simulator,name=iPhone 17' test` to CI.

---

## P2 — Functionality the website has and the app doesn't

### 20. No edit for milestones or measurements

> **Done.** `EditMeasurementView` and `EditMilestoneView`.

`SyncService.updateGrowthData` and `updateMilestone` are fully implemented and
unreachable — there is no edit UI. The website has `milestones/edit-milestone.tsx`
and `growth/GrowthForm.tsx`. Add edit sheets from `MeasurementListView` and
`MilestoneListView`.

### 21. No "today" / "age" date entry

> **Done.** `DateEntryPicker`. Note what the contract doc says about the third option: never send `inputType: "today"` — the server evaluates it against its own clock in its own zone, so a phone at 8pm can file a record under tomorrow.

`backend/growth.go` and `backend/milestone.go` accept
`inputType: "today" | "date" | "age"` with `ageYears`/`ageMonths`. iOS hardcodes
`inputType: "date"` in `SyncService` and `AddGrowthDataRequestDTO`. Entering "at
14 months" is materially easier on a phone than scrolling a date picker back two
years.

### 22. Photo upload collects no metadata

> **Open, by decision.** Import stays a batch: pick many, upload immediately, edit after. A post-pick sheet per photo is the wrong shape for forty holiday photos out of iCloud, and everything it would have collected is now editable afterwards — title and description in `PhotoDetailView` (§6), people in `TagPeopleView`, tags in the picker. Revisit if testers say otherwise.

`PhotoGalleryView` inserts `Photo(title: "", descriptionText: "", ...)` and
uploads immediately. The website's `photos/add-photo.tsx` (615 lines) collects
title, description, date, people, and a crop. At minimum: a post-pick sheet for
title/description/tagged people before the upload is enqueued.

### 23. Profile photos are display-only

> **Done.** `ProfilePhotoPickerView` sets one, and the crop is carried rather than dropped.

`PersonDTO` carries `profilePhotoId`, `profileCropX/Y/Scale`; `SyncMappers`
reads only `profilePhotoId` and drops the crop. `backend/person.go` exposes
`SetProfilePhoto`, and the website has `CropSelector.tsx`. The app can show an
avatar it can never set.

### 24. Milestone ↔ photo links are synced but invisible

> **Done.** `MilestonePhotoPickerView`, and `AddMilestoneRequestDTO` carries `photoIds`.

`Milestone.photoRemoteIds` is populated by `applyMilestoneDTO` and never
rendered. `AddMilestoneRequest.PhotoIds` exists on the backend and
`AddMilestoneRequestDTO` doesn't include it. The most recent commit in this repo
is literally "add milestone photos" — finish it.

### 25. Growth chart plots mixed units on one axis

> **Done.** `MeasurementConversion.normalized` converts before anything reaches a mark, and the axis is labelled with the unit it is actually in, with a toggle. The chart opens in whatever the family measured in most recently.

`GrowthChartView` labels the Y axis with `sortedMeasurements.first?.unit` and
plots raw `value`s. A person with some measurements in `in` and some in `cm`
gets a chart that is wrong rather than merely unlabeled. Normalize to a single
unit (with a display-unit toggle) before charting.

Related, lower priority: the website has a family-wide comparison chart
(`growth/family-chart.tsx`) and a `ComparePeople` proc backing `/compare`;
neither exists on iOS.

### 26. No tags

> **Done, and further than read-only.** `FamilyTag`, `TagPickerView`, `TagChipsView`, and editing.

`backend/tags.go` (`ListTags`/`CreateTag`/`UpdateTag`/`DeleteTag`) plus
`UpdateMilestoneTags` and `UpdatePhotoTags`; the website has a manage-tags page.
The iOS models have no tag concept at all. Read-only tag display on milestones
and photos would be a cheap first step.

### 27. Timeline omits photos

> **Done.** `TimelineItem` has a `.photo` case.

`TimelineView.TimelineItem` is `milestone | growthData`. The website's
`family-timeline.tsx` includes photos, and `pullFamilyData` already fetches them
per person. Adding a `.photo` case is small and closes an obvious gap.

### 28. Photo processing status is ignored

> **Done.** The SVG placeholder is its own outcome rather than a decode failure, is never cached, and is retried on a widening delay.

`servePhotoHandler` serves a placeholder while `image.Status == 1` and 404s on
`status == 2`; `GetPhotoStatus` exists to poll. `ImageDTO.status` is already
decoded by iOS and never used — `RemotePhotoView` caches the placeholder result
and never retries, so a freshly uploaded photo can stay blank indefinitely.

### 29. Multi-family is not modeled

> **Partly, by decision.** Membership and family links are exposed (`FamilyMembershipService`, `FamilyInfoView`), and `familyId: 0` means the primary family throughout — which is the convention the server documents. There is still no family switcher, and export/import stays out of scope for a phone.

Recent backend work (`family_link.go`, `membership.go`, `person_family.go`, and
optional `familyId` on chat/photo/timeline requests) supports belonging to and
linking multiple families. iOS assumes one implicit primary family everywhere
and has no family switcher. Decide whether v1 explicitly scopes to the primary
family — and if so, make sure `removeOrphans` can't delete data belonging to a
second family.

Also unimplemented from the website: export/import
(`ExportData`, `/api/export-bundle`, `settings/import.tsx`).

---

## P3 — Quality, performance, polish

### 30. `RemotePhotoView` has no cache

> **Done.** `PhotoImageCache`: a `URLCache` honoring the server's `max-age=300` plus ETag revalidation, an `NSCache` of decoded images over it, and one download shared between simultaneous askers. Grids already asked for `.thumb`.

Every appearance issues a fresh authenticated `URLSession` request. Scrolling the
gallery re-downloads everything, repeatedly. Add a shared `NSCache`/`URLCache`
layer and confirm grids request `thumb`/`small` rather than larger variants.

### 31. Local photo blobs are never released

> **Done.** `imageData` is cleared once the upload returns, which also stops the photo being exempt from `removeOrphans`.

`Photo.imageData` holds the full-resolution image via `.externalStorage` and is
never cleared after a successful upload (`removeOrphans` even skips photos with
`imageData` to protect them). Local storage grows without bound. Clear the blob
once `remoteId` is set and the server copy is confirmed serving.

### 32. Chat history is unbounded and unpaginated

> **Done.** `GetChatMessages` is paged with `offset`.

`ChatService.loadMessages` only ever fetches the newest 50; `GetChatMessages`
supports `offset` and the UI has no "load older". Meanwhile every message ever
received is retained in SwiftData forever. Add pagination up, and pruning down.

### 33. `SyncQueue` persistence

> **Done.** `SyncQueueStore` keeps the queue in Application Support as `SyncQueue.json`, written atomically — a torn write is not one lost operation, it is an array that will not decode. Not SwiftData, the other option named here: the queue is read and written as a whole array, so per-record storage buys nothing and would cost a schema migration on the very container it exists to push. `load()` adopts a queue left in `UserDefaults` by an older build and clears the key, once.

The entire pending-operation queue — including base64 payloads — is a single
JSON blob in `UserDefaults`, rewritten on every mutation. Move it to a file or
SwiftData store before people accumulate a real backlog offline.

### 34. Errors are printed, not surfaced

> **Done.** No `print` remains in the app target; `AppLog` categories for diagnostics and `ErrorPresenter` for anything the user acted on.

~20 `print("Failed to sync ...")` sites across the views swallow real failures.
`AddMeasurementView`, `AddMilestoneView`, `TagPeopleView`, and `PhotoDetailView`
all report nothing to the user. Adopt `os.Logger` for diagnostics and show an
inline error where the user acted.

### 35. Sheet dismissal waits on the network

> **Done by construction.** `enqueueOperation` writes to the queue and kicks the processor off in a detached task, so the `await` a sheet sees is a local write. Nothing waits on the network to dismiss.

`AddMeasurementView.save()` and `AddMilestoneView.save()` `await` the sync call
before `dismiss()`. On a slow connection the sheet just sits there, even though
the write already succeeded locally and the queue guarantees delivery. Dismiss
immediately.

### 36. `TimelineView` filtering cost

> **Done.** `TimelineResultsView` builds its `@Query` predicates in `init`, so person and year are the store's work; the merge and sort run over what it returns. Category and measurement type stay in memory — they only ever see records the type filter already singled out — and search, which has to match a person's name across a relationship, is debounced 250ms. The year chips are recomputed when the data changes rather than on every render.

Every keystroke rebuilds and re-sorts the merged milestone+growth array over the
full dataset. Push person/type/year filters into the `@Query` predicates and
debounce `searchText`.

### 37. `PreviewData` omits `ChatMessage`

> **Done.** One `DataStore.makeSchema()` for the app, the previews, and the tests.

`DataStore`'s schema includes `ChatMessage`; `PreviewData.container` does not.
Any preview touching chat models crashes. Keep the two schemas in one place.

### 38. Duplicated family-list code

> **Done.** `FamilyRosterSections`, with the ordering rules pinned by tests.

`FamilyMembersView` and `FamilyManagementView` carry byte-identical
parents/children partition-and-sort logic. Extract it (a `Person` sort
comparator plus a shared section view).

### 39. Accessibility pass

> **Done.** Icon-only controls have names; decoration is hidden. The avatar is hidden rather than labelled, because every place it appears already shows the name beside it.

Toolbar buttons are bare `Image(systemName:)` with no label; avatars, photo
thumbnails, and chart content have no accessibility text. Cheap to fix, visible
in review, and required for a decent VoiceOver experience.

### 40. Age string may disagree with the website

> **Done — and they disagreed.** `Calendar.dateComponents` resolves "31 March plus one month" by clamping to 30 April and calling it a whole month; the server compares day numbers and calls it none. So every month-end birthday read differently on one day of every month, and a leap-day child was a year old here and eleven months old there. Due dates were not handled at all — the server renders gestational age in weeks. `AgeCalculator` now ports the server's arithmetic, `isPregnancy` travels from the DTO through the model, and the tests are the server's own answers. The app still computes the string rather than adopting `PersonDTO.age`: a stored string goes stale the moment a birthday passes, and a person created offline has no server answer at all.

`PersonDTO.age` is a server-computed display string that `SyncMappers` discards
in favor of the local `AgeCalculator`. Confirm the two produce identical text,
or adopt the server's, so the app and the website never disagree on a child's
age.

---

## Suggested sequencing

Kept as written, for the record. It was followed, and the ordering held up:
turning on the test target after P0 and P1 is what stopped the chat wire bugs
from coming back.

1. **P0 #1–#5** (chat wire protocol) — one focused pass over `ChatDTOs.swift` and
   `ChatWebSocketService`; fixes the most visibly broken feature in the app.
2. **P0 #6–#9** (data-loss and crash risks) + **P1 #11** (auth gate).
3. **P1 #19** (test target + fixture decoding tests) — lock in 1 and 2, then
   turn on `test` in CI.
4. **P1 #12–#18** — the actual submission checklist: signup/reset, family join,
   version gate, push, privacy manifest, bundle id, versions.
5. **P2** in the order listed; #20, #21, #24, #27 are the cheapest wins.
6. **P3** opportunistically, with #30–#32 before any wide beta.
