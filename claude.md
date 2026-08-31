# Family Portal iOS

SwiftUI + SwiftData local-first iOS companion to a Go web backend. MVVM with `@Observable`, tab-based navigation, JWT auth.

## Directory Structure

```
Family-Portal-Ios/Family-Portal-Ios/
├── Family_Portal_IosApp.swift        # App + AppDelegate (APNs token)
├── ContentView.swift                 # version gate → auth gate → tabs
├── Models/
│   ├── Enums.swift, Family.swift, Person.swift, GrowthData.swift
│   ├── Milestone.swift, Photo.swift, User.swift
│   └── ChatMessage.swift, FamilyTag.swift, PersonRelation.swift
├── Services/
│   ├── APIClient.swift, APIDTOs.swift, RPCMethod.swift
│   ├── PhotoImporter.swift
│   ├── AuthService.swift, GoogleSignInService.swift
│   ├── FamilyMembershipService.swift
│   ├── DataStore.swift, NetworkMonitor.swift
│   ├── PersonRelationService.swift
│   ├── SyncService.swift, SyncQueue.swift, SyncMappers.swift
│   ├── PhotoSyncService.swift, PushNotificationService.swift
│   ├── MobileVersionService.swift
│   └── ChatService.swift, ChatWebSocketService.swift, ChatDTOs.swift
├── Views/
│   ├── Auth/          LoginView, CreateAccountView, ForgotPasswordView,
│   │                  UpdateRequiredView
│   ├── Family/        FamilyMembersView, AddPersonView, EditPersonView,
│   │                  PersonDetailView, PersonRelationsSection, TimelineView,
│   │                  ProfilePhotoPickerView
│   ├── Photos/        PhotoGalleryView, PhotoDetailView, TagPeopleView,
│   │                  PhotoRoute, PhotoFilter, PhotoFilterView
│   ├── Measurements/  MeasurementListView, AddMeasurementView,
│   │                  EditMeasurementView, GrowthChartView
│   ├── Milestones/    MilestoneListView, AddMilestoneView, EditMilestoneView,
│   │                  MilestonePhotoPickerView
│   ├── Chat/          ChatView, MessageBubbleView, MessageInputView,
│   │                  TypingIndicatorView, ConnectionStatusView,
│   │                  DateSeparatorView, UserAvatarView
│   ├── Settings/      SettingsView, FamilyManagementView, FamilyInfoView,
│   │                  FamilyMembershipView
│   └── Components/    PersonAvatarView, PersonRowView, PersonPickerRow,
│                      MeasurementRowView,
│                      MilestoneRowView, PhotoThumbnailView, RemotePhotoView,
│                      SyncStatusView, FlowLayout, ZoomableView,
│                      DateEntryPicker, TagChipsView, TagPickerView,
│                      FamilyRosterSections, CoAnchorPicker
└── Utilities/
    ├── Constants.swift, AgeCalculator.swift, PreviewData.swift
    ├── RelationGraph.swift           # walks the stored edges
    ├── FamilyGroups.swift            # bands the roster by generation
    ├── AppLog.swift                  # OSLog categories
    ├── TagColor.swift                # tag hex string → Color
    └── ErrorPresenter.swift          # shared error alert
```

## Architecture

- **UI**: SwiftUI, tab-based (Family, Timeline, Photos, Settings)
- **State**: `@Observable` classes, `@Query` for SwiftData reads
- **Persistence**: SwiftData with models: Family, Person, PersonRelation, GrowthData, Milestone, Photo, User, ChatMessage, FamilyTag
- **Networking**: `APIClient` actor with JWT auth, auto-refresh on 401
- **Auth**: `AuthService` (`@Observable`) manages login/logout/session restore
- **Sync**: `SyncService` (`@Observable`) handles bidirectional sync with offline queue support
- **File discovery**: PBXFileSystemSynchronizedRootGroup (no manual Xcode file references)

## Data Models

All models are `@Model` classes with `remoteId: String?` for backend sync.

| Model | Key Fields | Relationships |
|-------|-----------|---------------|
| Family | name, inviteCode, createdAt | members: [Person] (cascade) |
| Person | name, gender: Gender, birthday: Date?, isPregnancy: Bool, relationship: String? | family: Family?, growthData: [GrowthData] (cascade), milestones: [Milestone] (cascade), photos: [Photo] |
| PersonRelation | fromId: Int, toId: Int, kind: RelationKind | — (holds *server* person ids, not a relationship) |
| GrowthData | measurementType, value: Double, unit: MeasurementUnit, date | person: Person? |
| Milestone | descriptionText, category: MilestoneCategory, date | person: Person? |
| Photo | imageData: Data? (externalStorage), title, descriptionText, photoDate, tagRemoteIds: [Int] | taggedPeople: [Person] |
| User | name, email, familyId: UUID? | — |
| FamilyTag | name, colorHex, familyId | — (records hold tag ids, not a relationship) |

`Person.relationship` is the server's own wording for how that person relates to
the signed-in account's person — "daughter", "grandfather", "cousin" — derived by
walking the relation graph rather than stored on the person. It is *viewer-relative*:
the same record reads differently to two accounts, which is why nothing groups a
roster by it and why the app never computes one itself.

`PersonRelation` is one stored edge of the family graph. It is held locally so
the roster can band itself by generation on launch rather than after the network
answers, and its ends are server ids for the same reason a photo's tag ids are:
the graph is the server's to own, the whole set is replaced on every pull, and a
person still uploading has no server id to be an end of yet. Only the three
stored kinds exist — parent (directed, `fromId` is the parent), sibling and
partner (symmetric, stored in whichever direction somebody stated them).

`Person.isPregnancy` must be sent on **every** update: `UpdatePerson` assigns it
unconditionally, so an editor that omits it decodes as `false` on the Go side and
silently clears the flag. `AgeCalculator.offersPregnancyOption` decides whether
an editor shows the toggle at all — a record already flagged, or a date that has
not arrived.

`Milestone.photoRemoteIds`/`tagRemoteIds` and `Photo.tagRemoteIds` hold *server*
ids rather than SwiftData relationships: the pairings are the server's to own,
both sides can arrive from different calls, and an id with nothing to resolve it
yet simply renders as nothing.

## Services

### DataStore
Singleton managing `ModelContainer`; `makeSchema()` is the one list of `@Model`
types, shared with previews and tests.

### AuthService (`@Observable`)
- `login(email:password:)` → POST `api/login`
- `logout()` → POST `api/logout`, clears tokens
- `restoreSession()` → POST `api/refresh`; only a 401 ends the session, other failures fall back to the cached identity so an offline launch stays signed in
- `loginWithGoogle()` → POST `api/login/google/token`; `loginWithApple(_:)` → POST `api/login/apple/token`. Apple's `SignInWithAppleButton` owns its own presentation, so unlike Google there is nothing to await: the view hands the raw `Result` over and `AppleSignInService` classifies it, cancellation included. The server matches the identity token's email against the same account table the password path uses, and it accepts the token only if its audience is in `APPLE_IOS_CLIENT_ID` — the app's bundle id, `com.familyrecord.ios`
- Apple releases the user's name only on the *first* authorization, which is why `AppleTokenLoginRequestDTO` carries it: every later sign-in sends an empty string and the server names the account itself
- `serverURL` persisted in UserDefaults, synced to APIClient
- `isAuthenticated` computed from `currentUser != nil`

### APIClient (actor)
- `request<T, Body>(path:method:body:requiresAuth:retryOnAuthFailure:)` — generic async request
- `callRPC<T, Body>(_ proc:payload:)` — calls `rpc/{proc.rawValue}` with POST. Proc names live in the `RPCMethod` enum, never as inline strings: vbeam dispatches on the *Go function name* given to `RegisterProc`, so a mismatch compiles clean and fails only at runtime. `RemovePersonFromPhotoProc` carries a `Proc` suffix the others don't, because the plain name is a tx helper in `backend/photos.go`
- Tokens stored in Keychain (`com.familyrecord.accessToken`, `com.familyrecord.refreshToken`)
- Cookies synced to HTTPCookieStorage for HttpOnly support
- The refresh token only ever arrives as a `Set-Cookie` header, never in a response body: `captureTokens` banks it, and callers holding a JWT from a body must use `setAccessToken` (never `setTokens(…, refreshToken: nil)`, which would discard it)
- `ensureFreshAccessToken()` refreshes proactively when the JWT's `exp` is within 5 minutes — for the WebSocket and `RemotePhotoView`, which read the token directly rather than going through `request`. `RemotePhotoView` calls it before every load and retries once on a 401
- `refreshAccessToken()` is single-flight: the refresh token rotates on use, so concurrent refreshes can invalidate each other's credential and kill a live session. Overlapping callers await one shared `Task`
- A 401 from `api/refresh` clears tokens and fires `setSessionExpiredHandler`; any other refresh failure leaves the stored session intact
- Custom date decoding: ISO8601 (with/without fractional seconds) + "yyyy-MM-dd" fallback

### FamilyMembershipService
Membership self-service against `backend/membership_procs.go`: `ListFamilyMembers`, `RemoveFamilyMember`, `LeaveFamily`, `RotateInviteCode`. Takes an injectable `APIClient` (`init(apiClient:)`, defaulting to `.shared`) the way `PhotoSyncService` does.

- *Members* are user accounts; `FamilyManagementView` and `FamilyMembersView` list `Person` records. The two sets never line up — a child is a person and never a member
- Deliberately **not** queued. A membership change is a permission change: it means nothing until the server agrees, and a queued "leave family" replayed hours later would report a success that never happened. Online only, like `JoinFamily`
- These procs answer refusals as HTTP **200** with `{ success: false, error: … }` (owner-only removal, leaving as the last member), so the service lifts the message into `MembershipError.refused` — a status-code check alone would report a leave that did not happen
- Go's `omitempty` does nothing for a struct field, so `LeaveFamilyResponse.auth` arrives zero-valued when there is nothing to say. `leaveFamily` returns nil rather than handing the app a user with id 0
- A rotation that succeeds with an empty code is treated as a failure: the family would otherwise keep showing the old, now-dead code as if nothing had happened
- `familyId: 0` means the caller's primary family, matching the Go fallback
- State lands back in `AuthService`: `applyLeftFamily(_:auth:)` trims the family and re-reads the list (keeping the trimmed list if the re-read fails, since `loadFamilyInfo` empties `families` on error), and `applyRotatedInviteCode(_:forFamily:)` patches the row in place because the response is already authoritative

### PersonRelationService

The relationship graph (`backend/relation.go`): `GetPersonRelations`, `AddRelation`,
`RemoveRelation`, against an injectable `APIClient` like `FamilyMembershipService`.

- Only **three** edge kinds are ever stored — parent-of, sibling-of, partner-of.
  Grandparent, grandchild, aunt, nephew and cousin are the server walking those
  edges outward, so they can be read but never added or removed: the edge to
  remove is always one somebody typed. Sibling is stored rather than always
  inferred from a shared parent, so "Kate is my sister" works without entering
  parents nobody will enter
- Direction rides on the wire. `StatedRelation` names what the *new* person is to
  the anchor (`child` vs `parent`), so the request says what the user said and the
  client never has to normalise it. Its raw values pin the Go iota order
- Wording comes from the target's gender, which is why one stored edge reads
  correctly from both ends — and why `RelationOption` (the twelve words the
  pickers offer, mirroring `RELATION_OPTIONS` in the web) also prefills the new
  person's gender: "daughter" has already said it
- **Not** queued, for the same reason membership is not: a label is derived from
  edges this device cannot see all of, so only the server can word one. A queued
  edge would show a relationship the graph had not gained
- Refusals arrive as HTTP **200** with `{ success: false, error: … }`, lifted into
  `RelationError.refused`. `relations` is a *struct*, so Go's `omitempty` does
  nothing for it and a refusal still carries a zero-valued one — read as an empty
  graph it would wipe every relationship off the screen
- `GetPersonRelations` returns **two kinds of row**. `stored: true` is one
  somebody typed and is the only kind with anything to remove; `stored: false` is
  the graph answering — the siblings a shared parent implies, a grandmother two
  edges up — and arrives with **id 0**, the same id for every implied row. That
  is why `RelationViewDTO.id` is composed (`stored-4`, `implied-15`) rather than
  taken from the wire: a `ForEach` keyed on the wire id would collapse every
  implied row into one. `relationId` is what `RemoveRelation` takes
- `addRelation(…additionalAnchorIds:)` states the same relation against several
  people in one write, so "daughter of Steven **and** Ruth" is one call rather
  than one per parent. The server skips ids that are 0, the subject, repeated, or
  already stored — but fails the *whole* call over one it cannot see, committing
  nothing, so only ever pass ids that came back with the people themselves

### RelationGraph and FamilyGroups

Ports of `frontend/lib/relations.ts` and `frontend/lib/familyGroups.ts`, so the
phone and the dashboard answer the same questions from the same graph.

- `RelationGraph` names *neighbours* only — parents, children, siblings,
  partners. It never words a relationship: "grandmother" and "cousin" are the
  server's (`backend/relation_label.go`), and a client that derived them would
  disagree with the labels beside them on the same screen
- Siblings are those stated outright **plus** those sharing a parent, walked one
  step and no further: stated sibling edges are not transitive, because
  half-siblings break that. Stating several at once is what
  `coAnchorSuggestions` is for — a child's other parent (preselected only when
  the anchor has exactly one partner), or the anchor's siblings
- Nothing is *inferred* from a partner. Treating a partner's child as your own
  would be silent and unrefusable, and step-families are exactly where it is
  wrong, so a co-anchor is a tick the user makes and an edge the server stores
- `FamilyGroups.group(people:relations:)` bands the roster by generation, read
  off the **bottom** of the tree: the youngest generation present is always
  "Children". Reading from the top would rename every band the moment a
  grandparent was added. People no edge reaches go last under "Not linked yet",
  which includes anyone added offline — they have no server id to be an end of an
  edge yet. A generation, unlike a relationship, is not viewer-relative, which is
  why the graph can band a roster where `Person.relationship` cannot

### ChatService (`@Observable`, `@MainActor`)

One family room, backed by three procs (`SendMessage`, `GetChatMessages`,
`DeleteMessage`) and a WebSocket (`ChatWebSocketService`) for live delivery,
typing and presence. Messages persist as `ChatMessage`; `loadLocalMessages()`
seeds the list from the store at init so the thread is on screen before the
network answers.

- Not queued, unlike everything under `SyncService`. A send is optimistic — the
  row appears with `isSending`, adopts the server's id, or is marked
  `sendFailed` and retried by hand
- A message can arrive three ways (the send that created it, the socket echo,
  the next page) each carrying a different subset of the ids the others match
  on, which is what `merge` and `didReceiveMessage` reconcile. An *empty*
  `clientMessageId` is "unknown", never a match — treating it as one would make
  every server message that lacks one look like a duplicate of ours
- **History paging**: `loadMessages()` takes the newest page; `loadOlderMessages()`
  takes the page before the oldest one fetched, behind the pull at the top of
  `MessagesListView`. `hasMoreHistory` only ever goes true → false, since a page
  that came back short means the conversation's first message is on screen and
  everything written after it is newer, not older
- `historyOffset` counts **messages the server has handed over**, not
  `messages.count`. The list also holds what this device sent and what the socket
  delivered live, and the offset addresses the server's ordering — counting the
  whole list would step over history that was never fetched. Live messages slide
  the window the other way instead, so the next page *overlaps* what is on
  screen; `merge` dedups it, and overlapping is the safe direction to be wrong in
- The offset is likewise **not** seeded from the local message count on launch.
  That would assume the store holds an unbroken run of the newest messages; a
  device that missed a month of chat holds an old run, and starting there leaves
  a hole in the middle of the thread nothing later fills. The cost is that the
  first pull of a session can land on a page it already has, so `loadOlderMessages`
  walks on until a page adds something — capped at `maxPagesPerPull`
- A failed page returns nil and leaves `historyOffset` alone: it is the only
  record of how far back the thread has been read
- `ChatService.error` surfaces in `ChatErrorBanner` at the top of `ChatView`, not
  through `ErrorPresenter` — chat errors are per-conversation, and unlike the
  sheets that report through the app-scoped alert, this view is still on screen.
  It was write-only before history paging, where a silently failed pull is
  indistinguishable from a thread with no history

### SyncService (`@Observable`)
- `performFullSync()` — processes queue then pulls family data
- `processQueue()` allows only **one run at a time**. `@MainActor` is not mutual exclusion: a run suspends on every request and an operation is dequeued only *after* it succeeds, so a second run entering during that gap reads the same ready set and sends the same request twice — for an upload, a second photo on the server. A caller turned away sets `queueRunRequested` instead of dropping its work, and the run in flight goes round again, because it may already have taken its snapshot of the queue
- `pullFamilyData()` — fetches all data via `GetFamilyTimeline`, upserts locally
- Push methods: `addPerson`, `addGrowthData`, `updateGrowthData`, `deleteGrowthData`, `addMilestone`, `updateMilestone`, `deleteMilestone`, `deletePhoto`
- Offline support via `SyncQueue` — operations queued when offline, processed on reconnect
- Server-authoritative: on conflict, server data wins; optimistic UI for local changes
- `Photo.imageData` holds local bytes only until the upload is confirmed, then it is cleared and display falls back to `RemotePhotoView`. `removeOrphans` protects unsynced work by `remoteId == nil` alone — do not re-add a local-bytes exemption, which pinned uploaded photos on the device forever
- A queue operation whose own record is gone `return`s (moot, drop it); one whose *parent* is merely unsynced throws `SyncError.missingRemoteId` so it is retried rather than dequeued as a success — and is charged a blocked run, not a retry, so it cannot wait forever
- `Person.birthday` is required by the server (`validateAddPersonRequest`); the push path throws `SyncError.missingBirthday` rather than substituting a date
- `addPerson(_:stated:anchor:additionalAnchors:)` sends the stated relationship *with* the create rather than as a second call, so a person added offline arrives related. The anchor travels as a **local** id and is resolved at execution, the way a milestone's photo ids are: an anchor still uploading throws `missingRemoteId` (park and retry) instead of arriving unrelated, and one deleted since simply drops the relationship. The *additional* anchors are treated the opposite way and simply dropped when they cannot be named: they are a suggestion the user accepted rather than the relationship they set out to state, and one unresolvable id would otherwise fail the whole server call and hold the person back
- `pullFamilyData()` also stores the graph's edges as `PersonRelation`, swept by the same orphan pass as everything else
- `syncQueue` is injectable (`init(…, syncQueue:)`) so tests drive `processQueue` without touching the app's real queue
- `setProfilePhoto(_:for:)` refuses a photo the person is not tagged in (`SyncError.personNotInPhoto`) because the server does too, and a rejection discovered there costs five retries. Crop is stored and rendered, never edited on iOS: re-picking the current photo keeps its crop, any other photo starts centred at 1×
- Backend ints and floats marshal as `0` rather than as an absent key, so `applyPersonDTO` maps zero to `nil` — otherwise every person without a profile photo asked `RemotePhotoView` to load photo id 0
- `pullTags()` refreshes the `FamilyTag` vocabulary from `ListTags` inside the pull, but catches its own failures: tags label records the pull has already stored, so a tag list that 500s costs the user their chips and nothing else. Orphan removal stays in the success path — a list that never arrived is not evidence the family has no tags
- The tag **vocabulary** is read-only on iOS: tags are created, renamed, recoloured and deleted on the web (`CreateTag`, `UpdateTag`, `DeleteTag` have no iOS caller). `TagChipsView` renders `tagRemoteIds` and skips any id the local vocabulary can't resolve, exactly as `view-photo.tsx` does
- **Applying** tags is not: `updatePhotoTags(_:tagRemoteIds:)` / `updateMilestoneTags(_:tagRemoteIds:)` queue whole-set writes, since `UpdatePhotoTags`/`UpdateMilestoneTags` detach every tag they are not sent. The payload holds *remote* ids — a tag exists only because a pull produced it, so unlike a milestone's photo ids there is nothing to resolve at execution — and the local write happens after a successful enqueue, so a failure leaves nothing to undo. Milestone tag ops declare no dependency: milestones are absent from `fetchAllSyncedLocalIds`, so a dependency on one would never be satisfied; an unsynced milestone throws `missingRemoteId` at execution instead
- An id the local vocabulary can't resolve is **sent back untouched**, both by `TagPickerView` and by the service. Unresolvable means "created on the web since the last pull" far more often than "deleted", and dropping it from a whole-set write would untag a record because this device is a few minutes behind
- Milestone photo attachments (`addMilestone(…, photos:)` / `updateMilestone(_:photos:)`) are the *complete* set, not a delta: `nil` omits `photoIds` and leaves the server's attachments alone, `[]` detaches all of them. The queue payload holds photo *local* ids and resolves them at execution — a photo still uploading throws `missingRemoteId` (park and retry) rather than attaching fewer photos than the user chose, and a photo deleted locally drops out of the list

### Testing
- Swift Testing (`@Suite`/`@Test`/`#expect`), target `Family-Portal-IosTests`, file-system synchronized — a new file is in the target as soon as it exists
- `FakeHTTP.swift` is a `URLProtocol`-backed stand-in for the backend. Each `FakeHTTPServer` owns a unique host and routing is by host, so suites running in parallel never collide; `APIClient(baseURL:session:)` is the injection point
- `Fixtures.swift` builds request/response JSON as dictionaries, plus `TestStore` (in-memory SwiftData + scratch queue) and `TestSync.harness()` (a whole `SyncService` wired to a fake backend)
- Queue tests enqueue while `NetworkMonitor(startMonitoring: false)` reports offline, then flip it — otherwise `enqueueOperation`'s own background `processQueue` races the assertions
- `APIClientRefreshTests` is `.serialized`: token storage (keychain, shared cookie jar) is process-wide

### SyncQueue (actor)
- Persists pending operations to UserDefaults (JSON-encoded); `defaults` is injectable so tests use a scratch suite
- Operation types live in `SyncOperationType`; the update-shaped ones (updatePerson, updateGrowthData, updateMilestone, updatePhoto, setProfilePhoto, updatePhotoTags, updateMilestoneTags) coalesce last-wins per record, the create/delete ones do not
- Dependency tracking: child operations wait for parent remoteId (e.g., addGrowthData waits for person sync)
- Max 5 retries before discarding failed operations. `markFailed` *returns* the operation it discarded, because that is the moment a local change stops being "not synced yet" and becomes "never syncing" — `SyncService.discardedChangeWarning` reports it and Settings shows it until dismissed
- A network error breaks the queue run rather than marking anything failed: being offline must never spend a retry
- Blocked is tracked apart from failed. An operation waiting on something unsynced spends a `blockedCount`, never a `retryCount` — nothing was sent, so the server never said no — but 20 blocked runs discards it, because a parent whose own create was discarded is never coming. `blockedOperations` is the exact complement of `readyOperations`: an operation the dependency gate holds back never reaches `executeOperation`, so `processQueue` has to ask for it by name or nothing ever accounts for it. It re-reads the synced set first, since a parent that succeeded earlier in the same run has already unblocked its children
- `PendingOperation` decodes by hand only so a missing `blockedCount` defaults to 0. The queue persists as one `[PendingOperation]` blob, so one operation from an older build failing to decode would take every pending change on the device with it — add new fields the same way

### Photo gallery (`PhotoGalleryView`, `PhotoImporter`, `PhotoFilter`, `PhotoFilterView`)

- The import itself is `PhotoImporter` (`@Observable`, `@MainActor`), not the
  gallery: the quick-add menu offers photos from the Family and Timeline tabs
  too, and all three need the same run. Its dependencies — context, sync service,
  error presenter — arrive **on the call**, because a view's `@State` is built
  before its `@Environment` can be read, so `@State private var importer =
  PhotoImporter()` is the whole wiring
- A second pick made while a run is in flight extends that run's `total` rather
  than starting a competing one, so one progress bar covers both
- The picker is multi-select and `.ordered`. Items are read **sequentially** —
  each is a full-resolution image, and decoding twenty at once is the kind of
  memory spike that gets an app killed mid-import
- Import counts only the reading and queueing. The upload itself belongs to
  `SyncQueue`, which already owns retries, offline and ordering, so a finished
  import means every photo is on screen and queued, not that it is on the server;
  a bulk import is also what makes overlapping `processQueue` runs ordinary
  rather than rare (see SyncService)
- Progress is a bottom `safeAreaInset` (`PhotoImportProgressBar`), not the
  full-screen overlay it replaced: photos land in the grid as they are read, and
  blocking the screen hid the one thing that showed the import working
- A failed run reports **once**, not per photo — a dozen alerts stacked behind
  each other is what per-photo reporting looks like for an iCloud batch. A single
  failure still reports its own error, so the iCloud hint survives
- The capture date is read from the picked image's own EXIF rather than from
  `PHAsset`, which needs photo-library authorization the picker does not, and is
  parsed against a fixed POSIX locale. No EXIF date answers **nil**, not an
  epoch: the caller falls back to "now", and a photo dated 1970 would sort to the
  bottom of every gallery forever
- `PhotoFilter` is a value type holding people (local ids), tags (remote ids, as
  `Photo.tagRemoteIds` carries them), a date window and search text. Choices
  within a category OR, categories AND — the rule in
  `frontend/hooks/usePhotoFilter.ts`. Search over title and description is the
  one part with no web equivalent
- The date window is normalised, not compared raw: `to` extends to the end of its
  day (a photo carries a time, so a literal comparison excludes everything shot
  that day) and a backwards range is swapped rather than matching nothing
- The panel reads people and tags from the **store**, not from
  `ListPeople`/`ListTags` as the web does: the gallery it filters is local, so a
  filter that needed the network would be useless in exactly the situation the
  app exists for
- `hasPanelFilters` is kept apart from `isActive` so the toolbar glyph doesn't
  fill in for a search term the search bar is already showing

### Adding records

- `AddMilestoneView` and `AddMeasurementView` take `personId: UUID?`. **Nil means
  the sheet asks**, which is what lets anything open one without already standing
  on somebody — the whole reason adding used to be four taps deep
- Neither can narrow its `@Query` to the person any more: a predicate is fixed at
  `init` and cannot follow a `@State` selection, so both fetch the roster and pick
  in memory. A household is small, and `TimelineView` and `AddPersonView` already
  query all of it
- The **For** row (`PersonPickerRow`) is shown whether or not the caller named
  somebody, so a sheet opened on the wrong person is fixable in place. Its
  "Choose someone" option exists only while nothing is chosen — there is nothing
  to go back to, since neither sheet can save without a person
- `DateEntryPicker` is given `.id(person?.id)`: its age steppers resolve against
  the birthday it was handed, so a picker carried over to somebody else would hold
  a date worked out from the wrong birthday. A new person gets a fresh picker back
  on "Today"
- The milestone sheet clears its photo selection when the person changes. `save()`
  filters the selection through `photoChoices` and so could never *send* a stale
  id, but the count beside "Attach Photos" would go on claiming them

### Error presentation and logging
- `ErrorPresenter` (`@Observable`, app scope, injected into the environment) plus the `.appErrorAlert()` modifier applied once at the root. Views report failures through it rather than swallowing them
- App-scoped rather than per view because the views raising these errors dismiss themselves in the same breath; an alert owned by a closing sheet never appears. Sheets `dismiss()` first, then report
- Reaching a view at all means the change can never sync: the push methods only *queue*, so network failures never surface there
- Service-level logging goes to `AppLog` (`OSLog` categories: sync, queue, chat, version, ui). No `print` anywhere in the app target

### APIDTOs
Response DTOs for all backend endpoints. Key types:
- `PersonDTO` (gender as Int, `relationship` derived and viewer-relative), `GrowthDataDTO` (measurementType as Int), `MilestoneDTO`, `ImageDTO`, `TagDTO`
- `AuthResponseDTO.personId` is the person the account stands for — the subject every relationship label is phrased against, and the anchor `AddPersonView` defaults to
- `RelationViewDTO`, `GetPersonRelationsResponseDTO`, `RelationActionResponseDTO` (see PersonRelationService)
- `FamilyTimelineItemDTO` { person, growthData[], milestones[], photos[] }
- `GetFamilyTimelineResponseDTO` { people: [FamilyTimelineItemDTO], relations: [RelationDTO] } — `relations` is the stored edge set among those people, the same one `ListPeople` returns. The app syncs through this one proc, so without it a roster could not be banded short of a call per person; decoded with `decodeIfPresent` so a server predating it still pulls
- `RelationDTO` { id, fromId, toId, kind: Int } — `kind` is decoded as an `Int`, not the enum: one added server-side is *dropped* on mapping rather than failing the pull, and never guessed at, since only `.parent` implies a generation step

## Auth Flow

1. User enters credentials in LoginView
2. `AuthService.login()` → APIClient POST to `api/login`
3. Response cookies captured: `authToken` + `refreshToken` → Keychain
4. On 401: APIClient auto-calls `api/refresh`, retries original request once
5. Logout clears Keychain + cookies + sets `currentUser = nil`

## Reference Webapp

The reference web application lives at `/home/sgg/Projects/Family-Portal`. Use it to understand API shapes, business logic, and expected behavior when implementing iOS features.

## Backend Reference

Go + vbeam RPC server.

- **RPC endpoint**: `rpc/{MethodName}` (POST, JSON body, requires auth)
- **Photo URLs**: `/api/photo/{id}/{size}` (sizes: small, thumb, medium, large, xlarge)
- **Photo upload**: `/api/upload-photo` (multipart/form-data)
- **Auth endpoints**: `api/login`, `api/logout`, `api/refresh`

### Key RPC Methods
- `GetFamilyTimeline` → `GetFamilyTimelineResponseDTO`
- `GetFamilyInfo` → `FamilyInfoDTO`
- `ListPeople` → `ListPeopleResponseDTO`
- `AddPerson`, `AddGrowthData`, `UpdateGrowthData`, `DeleteGrowthData`
- `GetPersonRelations`, `AddRelation`, `RemoveRelation` (backend/relation.go)
- `AddMilestone`, `UpdateMilestone`, `DeleteMilestone`
- `AddPeopleToPhoto`, `RemovePersonFromPhoto`, `DeletePhoto`
- `SetProfilePhoto`
- `ListFamilyMembers`, `RemoveFamilyMember`, `LeaveFamily`, `RotateInviteCode`
- `SendMessage`, `GetChatMessages`, `DeleteMessage` (chat; live delivery is the
  WebSocket, these three are the REST half)
- `ListTags`, `UpdatePhotoTags`, `UpdateMilestoneTags` (the three tag procs iOS calls — the vocabulary itself is web-only; see the notes under SyncService). The two writes are registered from `backend/photos.go` and `backend/milestone.go`, not `backend/tags.go`

`tagIds` on `Image` and `Milestone` carries `omitempty`, so a record with no tags
omits the key rather than sending `[]` — absent and empty mean the same thing on
the way in. Every response the app applies populates it, so reading an absent key
as "no tags" cannot wipe tags the server still holds.

`UpdatePhotoTags` and `UpdateMilestoneTags` answer with empty Go structs, so a
success is the literal body `{}` — `EmptyResponseDTO`, not `SuccessResponseDTO`,
which would throw on the missing `success` key and turn every successful write
into a retry.

`photoIds` on `AddMilestone`/`UpdateMilestone` is nullable in the Go sense:
`UpdateMilestoneTx` only touches attachments when the key is present, so an
absent key and an empty array mean opposite things.

## Enum Mappings (iOS ↔ Backend)

Backend uses integer iota values (from 0):

| Enum | iOS Value | Backend Int |
|------|-----------|-------------|
| StatedRelation.none | — | 0 |
| StatedRelation.child | — | 1 |
| StatedRelation.parent | — | 2 |
| StatedRelation.sibling | — | 3 |
| StatedRelation.partner | — | 4 |
| Gender.male | "male" | 0 |
| Gender.female | "female" | 1 |
| Gender.other | "other" | 2 |
| MeasurementType.height | "height" | 0 |
| MeasurementType.weight | "weight" | 1 |

**Note**: In RPC *responses*, measurementType comes as Int (0/1). In RPC *requests*, measurementType is a string `"height"`/`"weight"`.

### Unit Strings (requests & responses)
- Height: `"cm"`, `"in"`
- Weight: `"kg"`, `"lbs"`

iOS enums use `inches`/`centimeters`/`pounds`/`kilograms` — mappers needed.

## RPC Request Formats

Dates sent as `"YYYY-MM-DD"` strings. The `inputType` field: `"date"`, `"age"`, or `"today"`.

```
AddPerson: { name, gender: Int, birthdate: "YYYY-MM-DD", isPregnancy: Bool, stated: Int, anchorId: Int, additionalAnchorIds: [Int] }  // stated/anchorId both 0 = not saying
UpdatePerson: { id: Int, name, gender: Int, birthdate: "YYYY-MM-DD", isPregnancy: Bool }  // isPregnancy is assigned unconditionally — always send it
GetPersonRelations: { personId: Int }
AddRelation: { personId: Int, anchorId: Int, stated: Int, additionalAnchorIds: [Int] }   // stated says what personId is to anchorId
RemoveRelation: { relationId: Int }   // a stored row's id; implied rows have none
AddGrowthData: { personId: Int, measurementType: "height"|"weight", value: Double, unit: "cm"|"in"|"kg"|"lbs", inputType: "date"|"age"|"today", measurementDate: "YYYY-MM-DD"? }
UpdateGrowthData: { id: Int, measurementType: "height"|"weight", value: Double, unit: String, inputType: String, measurementDate: String? }
DeleteGrowthData: { id: Int }
AddMilestone: { personId: Int, description: String, category: String, inputType: String, milestoneDate: "YYYY-MM-DD"?, photoIds: [Int]? }
UpdateMilestone: { id: Int, description: String, category: String, inputType: String, milestoneDate: String?, photoIds: [Int]? }
DeleteMilestone: { id: Int }
DeletePhoto: { id: Int }
AddPeopleToPhoto: { photoId: Int, personIds: [Int] }
RemovePersonFromPhoto: { photoId: Int, personId: Int }
GetChatMessages: { limit: Int, offset: Int } // see below; both are *int on the Go side
ListTags: {}                                // argument-less, but the body is required
UpdatePhotoTags: { photoId: Int, tagIds: [Int] }         // complete set; [] detaches all
UpdateMilestoneTags: { milestoneId: Int, tagIds: [Int] } // complete set; [] detaches all
ListFamilyMembers: { familyId: Int }        // 0 = the caller's primary family
LeaveFamily: { familyId: Int }
RotateInviteCode: { familyId: Int }
RemoveFamilyMember: { familyId: Int, userId: Int }
```

`GetChatMessages` pages **backwards**: the window is cut from the newest message,
so offset 0 is the live end of the conversation and each further page is older.
A page still arrives oldest-first within itself, which is why the response shape
is unchanged from before paging existed. `limit` outside 1...200 falls back to the
server's default of 100.

Until `backend/chat.go` was changed for item 11, `GetFamilyChatMessages` passed
neither offset nor direction to `vbolt.Window`, so the request's `offset` was
accepted and ignored and the window was cut from the *oldest* end — a family past
100 messages loaded its first ever messages and never its recent ones, on both
iOS and the web. Any new proc that pages over a `vbolt.Index` has the same trap:
the index carries no priority, so its natural order is ascending by id.

The membership procs report refusals in the body (`success: false`) at HTTP 200,
and `RotateInviteCodeResponse` omits `familyId`/`inviteCode` entirely on failure
— `omitempty` on scalars, but not on the `auth` struct in `LeaveFamilyResponse`,
which arrives zero-valued instead.
