# Family Portal iOS — Pre-Release Improvement Plan

Scope: no new product ideas. Everything here is a bug in what exists, a piece of
backend/website functionality the app was clearly meant to use, or a gap that
blocks an App Store submission.

Reference repo: `../Family-Portal` (Go backend + React frontend). All backend
claims below are cited to a file in that repo.

---

## P0 — Correctness bugs that break shipped features

### 1. Chat message decoding uses the wrong key names (silently)

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

`DeleteMessageRequestDTO` encodes `message_id`; `backend/chat.go`
`DeleteMessageRequest` reads `id`. The server always receives `id: 0`, so no
delete ever lands. The client deletes locally and swallows the failure
(`ChatService.deleteMessage` only `print`s), so the message reappears on the
next device/pull.

### 3. `SendMessage` sends `client_message_id`, server reads `clientMessageId`

`backend/chat.go` `SendMessageRequest.ClientMessageId` is `json:"clientMessageId"`.
The server therefore persists an empty client id and broadcasts it back empty,
which is exactly the case the fragile fallback in `didReceiveMessage` exists to
paper over. Fix the key and the fallback becomes a true safety net.

### 4. WebSocket protocol names don't match the server

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

`ChatWebSocketService.handleIncomingMessage` uses
`decoder.dateDecodingStrategy = .iso8601`, which rejects fractional seconds. Go
`time.Time` marshals RFC3339 with nanoseconds. Reuse the tolerant custom
strategy already written in `APIClient.sharedDecoder` (fractional → plain ISO →
date-only) rather than maintaining two decoders.

### 6. Photo title/description edits are silently discarded

`PhotoDetailView` binds `TextField`s straight to `@Bindable photo.title` /
`photo.descriptionText`, and nothing enqueues a sync operation — there is no
`updatePhoto` case in `SyncOperationType` at all. The next `pullFamilyData` runs
`applyPhotoDTO`, which overwrites both fields from the server. The user's typing
disappears on the next sync.

The backend proc exists: `UpdatePhoto` in `backend/photos.go`. Add
`SyncOperationType.updatePhoto` + `SyncService.updatePhoto(_:)` and call it on
commit (not on every keystroke).

### 7. Deleting a person does nothing durable

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

`SyncService.deleteGrowthData` / `deleteMilestone` / `deletePhoto` all do:

```swift
modelContext.delete(data)
try modelContext.save()
try await enqueueOperation(..., localId: data.id.uuidString, ...)
```

`data.id` is read *after* the model has been deleted and the context saved.
Capture `let localId = data.id.uuidString` (and the remote id) before the delete.

### 9. Photo library access without a usage description

`PhotoGalleryView.photoDate(from:)` calls `PHAsset.fetchAssets(withLocalIdentifiers:)`.
That is PhotoKit, not the sandboxed picker, and it requires photo-library
authorization — but `Info.plist` has no `NSPhotoLibraryUsageDescription`. Add
the key (and request authorization, or drop to the picker's own metadata) before
submission; missing usage strings are both a crash risk and a review rejection.

### 10. Verify the refresh-token lifecycle end to end

`AuthService.login` calls `setTokens(accessToken: token, refreshToken: nil)` —
the refresh token is only ever obtained opportunistically from a `Set-Cookie`
header in `APIClient.captureTokens`. If `/api/login` doesn't set that cookie on
the native path, every session dies 24h later with no way back except
re-entering credentials. Worth an explicit test against
`backend/refresh_tokens.go` before release rather than after.

---

## P1 — Release-readiness gaps

### 11. There is no auth gate

`ContentView` renders all five tabs unconditionally. Signed out, a first-time
user sees three empty tabs, a Chat tab wired to a nil `ChatService`, and a
sign-in link buried in Settings. Present `LoginView` as a `fullScreenCover` (or
switch the root view) on `!authService.isAuthenticated`.

### 12. A new user cannot start on iOS at all

The backend has `CreateAccount` (`backend/users.go`) and
`RequestPasswordReset` / `ValidatePasswordResetToken` / `ResetPassword`
(`backend/password_reset.go`); the website has `auth/create-account.tsx` and
`auth/reset-password.tsx`. The app has neither. Sign-up and forgot-password are
table stakes for a standalone App Store listing.

### 13. No family create/join flow

`backend/users.go` exposes `GetFamilyInfo` and `JoinFamily` (invite code). The
iOS `Family` model even has an `inviteCode` field — but `Family` is never
inserted, synced, or read by any code path outside `PreviewData`. A user who
signs in without a family sees an empty app and no route forward. Same for
`Models/User.swift`, which is dead.

### 14. Wire up the mobile version gate the backend already built for this app

`backend/mobile_version.go` ships `GET /api/mobile-version?platform=ios&appVersion=x.y.z`
(deliberately pre-auth, cached 300s) plus a `CheckMobileVersion` proc, returning
`ok` / `update_available` / `update_required` with `updateUrl` and
`updateMessage`. Nothing in the app calls it. Implement the check at launch and
a blocking screen on `update_required`.

Note: it rejects anything that isn't strict `major.minor.patch` — see #15.

### 15. Version numbers are wrong in two places

- `MARKETING_VERSION = 1.0` in `project.pbxproj` — not valid semver, so the
  version endpoint above returns HTTP 400. Set `1.0.0`.
- `SettingsView` hardcodes `Text("1.0.0")`. Read
  `CFBundleShortVersionString` + `CFBundleVersion` from the bundle so it can
  never drift.

### 16. No push notifications

`backend/push_notifications.go` exposes `RegisterPushDevice` /
`UnregisterPushDevice` (APNs token, platform, sandbox/production environment,
bundle id), and `backend/chat.go:369` already calls `QueuePushNotification` on
every new message. The app never registers for remote notifications, so that
entire server-side path is dark. Add `UNUserNotificationCenter` registration
after login, `RegisterPushDevice` on token receipt, and `UnregisterPushDevice`
on logout.

### 17. Missing privacy manifest

No `PrivacyInfo.xcprivacy` in the target. The app uses `UserDefaults`
(`SyncQueue.storageKey`), which is a declared-reason API. Required for App Store
submission. Also add the privacy-policy link the listing will need.

### 18. Bundle identifier and deployment target

- `PRODUCT_BUNDLE_IDENTIFIER = grissom.Family-Portal-Ios` — not reverse-DNS, and
  inconsistent with the `com.familyrecord.*` keychain namespace. It is immutable
  after the first App Store Connect upload; decide now.
- `IPHONEOS_DEPLOYMENT_TARGET = 26.2` limits the app to a single point release.
  Lower it to the oldest OS you're willing to support.
- `TARGETED_DEVICE_FAMILY = "1,2"` claims iPad support, but every screen is a
  phone-shaped `TabView` with no split-view layout. Either adapt or drop iPad.

### 19. No tests, and CI only builds

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

`SyncService.updateGrowthData` and `updateMilestone` are fully implemented and
unreachable — there is no edit UI. The website has `milestones/edit-milestone.tsx`
and `growth/GrowthForm.tsx`. Add edit sheets from `MeasurementListView` and
`MilestoneListView`.

### 21. No "today" / "age" date entry

`backend/growth.go` and `backend/milestone.go` accept
`inputType: "today" | "date" | "age"` with `ageYears`/`ageMonths`. iOS hardcodes
`inputType: "date"` in `SyncService` and `AddGrowthDataRequestDTO`. Entering "at
14 months" is materially easier on a phone than scrolling a date picker back two
years.

### 22. Photo upload collects no metadata

`PhotoGalleryView` inserts `Photo(title: "", descriptionText: "", ...)` and
uploads immediately. The website's `photos/add-photo.tsx` (615 lines) collects
title, description, date, people, and a crop. At minimum: a post-pick sheet for
title/description/tagged people before the upload is enqueued.

### 23. Profile photos are display-only

`PersonDTO` carries `profilePhotoId`, `profileCropX/Y/Scale`; `SyncMappers`
reads only `profilePhotoId` and drops the crop. `backend/person.go` exposes
`SetProfilePhoto`, and the website has `CropSelector.tsx`. The app can show an
avatar it can never set.

### 24. Milestone ↔ photo links are synced but invisible

`Milestone.photoRemoteIds` is populated by `applyMilestoneDTO` and never
rendered. `AddMilestoneRequest.PhotoIds` exists on the backend and
`AddMilestoneRequestDTO` doesn't include it. The most recent commit in this repo
is literally "add milestone photos" — finish it.

### 25. Growth chart plots mixed units on one axis

`GrowthChartView` labels the Y axis with `sortedMeasurements.first?.unit` and
plots raw `value`s. A person with some measurements in `in` and some in `cm`
gets a chart that is wrong rather than merely unlabeled. Normalize to a single
unit (with a display-unit toggle) before charting.

Related, lower priority: the website has a family-wide comparison chart
(`growth/family-chart.tsx`) and a `ComparePeople` proc backing `/compare`;
neither exists on iOS.

### 26. No tags

`backend/tags.go` (`ListTags`/`CreateTag`/`UpdateTag`/`DeleteTag`) plus
`UpdateMilestoneTags` and `UpdatePhotoTags`; the website has a manage-tags page.
The iOS models have no tag concept at all. Read-only tag display on milestones
and photos would be a cheap first step.

### 27. Timeline omits photos

`TimelineView.TimelineItem` is `milestone | growthData`. The website's
`family-timeline.tsx` includes photos, and `pullFamilyData` already fetches them
per person. Adding a `.photo` case is small and closes an obvious gap.

### 28. Photo processing status is ignored

`servePhotoHandler` serves a placeholder while `image.Status == 1` and 404s on
`status == 2`; `GetPhotoStatus` exists to poll. `ImageDTO.status` is already
decoded by iOS and never used — `RemotePhotoView` caches the placeholder result
and never retries, so a freshly uploaded photo can stay blank indefinitely.

### 29. Multi-family is not modeled

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

Every appearance issues a fresh authenticated `URLSession` request. Scrolling the
gallery re-downloads everything, repeatedly. Add a shared `NSCache`/`URLCache`
layer and confirm grids request `thumb`/`small` rather than larger variants.

### 31. Local photo blobs are never released

`Photo.imageData` holds the full-resolution image via `.externalStorage` and is
never cleared after a successful upload (`removeOrphans` even skips photos with
`imageData` to protect them). Local storage grows without bound. Clear the blob
once `remoteId` is set and the server copy is confirmed serving.

### 32. Chat history is unbounded and unpaginated

`ChatService.loadMessages` only ever fetches the newest 50; `GetChatMessages`
supports `offset` and the UI has no "load older". Meanwhile every message ever
received is retained in SwiftData forever. Add pagination up, and pruning down.

### 33. `SyncQueue` persistence

The entire pending-operation queue — including base64 payloads — is a single
JSON blob in `UserDefaults`, rewritten on every mutation. Move it to a file or
SwiftData store before people accumulate a real backlog offline.

### 34. Errors are printed, not surfaced

~20 `print("Failed to sync ...")` sites across the views swallow real failures.
`AddMeasurementView`, `AddMilestoneView`, `TagPeopleView`, and `PhotoDetailView`
all report nothing to the user. Adopt `os.Logger` for diagnostics and show an
inline error where the user acted.

### 35. Sheet dismissal waits on the network

`AddMeasurementView.save()` and `AddMilestoneView.save()` `await` the sync call
before `dismiss()`. On a slow connection the sheet just sits there, even though
the write already succeeded locally and the queue guarantees delivery. Dismiss
immediately.

### 36. `TimelineView` filtering cost

Every keystroke rebuilds and re-sorts the merged milestone+growth array over the
full dataset. Push person/type/year filters into the `@Query` predicates and
debounce `searchText`.

### 37. `PreviewData` omits `ChatMessage`

`DataStore`'s schema includes `ChatMessage`; `PreviewData.container` does not.
Any preview touching chat models crashes. Keep the two schemas in one place.

### 38. Duplicated family-list code

`FamilyMembersView` and `FamilyManagementView` carry byte-identical
parents/children partition-and-sort logic. Extract it (a `Person` sort
comparator plus a shared section view).

### 39. Accessibility pass

Toolbar buttons are bare `Image(systemName:)` with no label; avatars, photo
thumbnails, and chart content have no accessibility text. Cheap to fix, visible
in review, and required for a decent VoiceOver experience.

### 40. Age string may disagree with the website

`PersonDTO.age` is a server-computed display string that `SyncMappers` discards
in favor of the local `AgeCalculator`. Confirm the two produce identical text,
or adopt the server's, so the app and the website never disagree on a child's
age.

---

## Suggested sequencing

1. **P0 #1–#5** (chat wire protocol) — one focused pass over `ChatDTOs.swift` and
   `ChatWebSocketService`; fixes the most visibly broken feature in the app.
2. **P0 #6–#9** (data-loss and crash risks) + **P1 #11** (auth gate).
3. **P1 #19** (test target + fixture decoding tests) — lock in 1 and 2, then
   turn on `test` in CI.
4. **P1 #12–#18** — the actual submission checklist: signup/reset, family join,
   version gate, push, privacy manifest, bundle id, versions.
5. **P2** in the order listed; #20, #21, #24, #27 are the cheapest wins.
6. **P3** opportunistically, with #30–#32 before any wide beta.
