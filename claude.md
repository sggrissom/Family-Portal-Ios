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
│   ├── AuthService.swift, GoogleSignInService.swift
│   ├── FamilyMembershipService.swift
│   ├── DataStore.swift, NetworkMonitor.swift
│   ├── PersonRelationService.swift
│   ├── SyncService.swift, SyncQueue.swift, SyncMappers.swift
│   ├── PhotoSyncService.swift, PushNotificationService.swift
│   ├── MobileVersionService.swift
│   ├── AnalysisService.swift, AnalysisDTOs.swift   # offline-analysis reads: online-only, never queued
│   ├── TagService.swift                            # tag vocabulary writes: online-only, never queued
│   ├── FaceReviewService.swift, FaceReviewDTOs.swift # face review: online-only, never queued
│   ├── BookService.swift, BookDTOs.swift           # books: reads cached like activities, writes online-only
│   ├── InterviewService.swift, InterviewDTOs.swift # annual interview: reads cached like books, writes online-only
│   ├── SearchDTOs.swift                            # global search: online read, never cached or queued
│   ├── VideoDTOs.swift                             # video support, upload and playback: online only, never queued
│   ├── WidgetSnapshotBuilder.swift, WidgetPublisher.swift  # the widgets' snapshot in the App Group
│   └── ChatService.swift, ChatWebSocketService.swift, ChatDTOs.swift
├── Views/
│   ├── Shell/         AppNavigator (tabs, per-tab paths, AppRoute, filters),
│   │                  AddFlow (the one add sheet), AccountMenu (account
│   │                  button + TabRoot), MoreView (the More tab)
│   ├── Home/          HomeView (GetDashboard: strip, nudges, in season,
│   │                  on this day, recent)
│   ├── History/       HistoryView (day summaries by month)
│   ├── Growth/        GrowthRootView (family age chart)
│   ├── SameAge/       SameAgeView, SameAgePortraits, SameAgeRows (+ strips),
│   │                  SameAgeLoader (+ SameAgeCache, SameAgeBrowser)
│   ├── Auth/          LoginView, CreateAccountView, ForgotPasswordView,
│   │                  UpdateRequiredView
│   ├── Family/        AddPersonView, EditPersonView, PersonDetailView,
│   │                  PersonTabs (Story/Quotes/Artwork/Interviews/Photos/Growth), PersonRelationsSection,
│   │                  ProfilePhotoPickerView
│   ├── Photos/        PhotoGalleryView, PhotoDetailView, TagPeopleView,
│   │                  PhotoRoute, PhotoFilter, PhotoFilterView,
│   │                  PhotoBatchFormView
│   ├── Measurements/  AddMeasurementView (checkup), CheckupResultView,
│   │                  MeasurementDetailView, EditMeasurementView
│   ├── Milestones/    AddMilestoneView, MilestoneDetailView,
│   │                  EditMilestoneView, MilestonePhotoPickerView,
│   │                  MilestonePhotoUploadSection
│   ├── Activities/    ActivitiesRootView, SeasonView, CompetitionView, …
│   ├── Books/         BooksView (shelf), BookReaderView, BookBlocks,
│   │                  NewBookView, BookEditorView
│   ├── Interviews/    InterviewView (one interview's page), InterviewSetupView,
│   │                  InterviewAskView + InterviewSession (conduct), PersonInterviewsTab,
│   │                  FamilyInterviewsView (More), InterviewCompareView, PastInterviewView,
│   │                  InterviewQuestionsView (the question list)
│   ├── Chat/          ChatView, MessageBubbleView, MessageInputView,
│   │                  TypingIndicatorView, ConnectionStatusView,
│   │                  DateSeparatorView, UserAvatarView
│   ├── Settings/      SettingsView, FamilyManagementView, FamilyInfoView,
│   │                  FamilyMembershipView
│   ├── Tags/          ManageTagsView (+ TagEditorView sheet)
│   ├── Faces/         FaceReviewView (+ FaceGroupRow)
│   ├── Search/        SearchView (global search, pushed from the magnifying glass
│   │                  on every tab root), SearchModel (debounce, stale answers dropped)
│   └── Components/    PersonAvatarView, PersonRowView, PersonChips,
│                      WhenControl, FaceCropView, MeasurementRowView, MilestoneRowView,
│                      PhotoThumbnailView, RemotePhotoView, SyncStatusView,
│                      FlowLayout, ZoomableView, TagChipsView, TagPickerView,
│                      FamilyRosterSections, CoAnchorPicker, AgeChartView,
│                      DaySummaryViews, DetailSheetComponents, RecordStyle,
│                      InterviewCardView (an interview's answers as one card),
│                      CameraCaptureView (the system camera, for one photo),
│                      VideoBadge (play mark + length on a video's poster)
└── Utilities/
    ├── Constants.swift, AgeCalculator.swift, PreviewData.swift
    ├── Copy.swift                    # every user-facing string the web has words for (copy.ts)
    ├── WhenEntry, Checkup, AgeSteps, DaySummary, Story, HistoryFilter,
    │   AgeChart, FamilyStrip          # ports of the web's frontend/lib grouping, with its fixtures
    ├── Interviews.swift              # port of frontend/lib/interviews.ts: folding, titles, what changed
    ├── InterviewQuestionList.swift   # port of frontend/lib/interviewQuestions.ts: the editor's draft
    ├── SearchQuery.swift             # port of backend/search_query.go; its test table is a copy of the Go one
    ├── VideoDuration.swift           # port of formatDuration in frontend/lib/videoFiles.ts
    ├── SearchText.swift              # search folding, prefix-of-word matching, highlight ranges
    ├── SearchResults.swift           # port of frontend/lib/search.ts: chips, moment folding, See all photos
    ├── SearchLocal.swift             # offline search over the mirror, with the server's filters
    ├── RecentSearches.swift          # last 8 searches in UserDefaults, erased with the account
    ├── RelationGraph.swift           # walks the stored edges
    ├── FamilyGroups.swift            # bands the roster by generation
    ├── FamilyAccess.swift            # per-family role → which add/edit/delete controls show (authCache.ts)
    ├── AppLog.swift                  # OSLog categories
    ├── TagColor.swift                # tag hex string → Color
    └── ErrorPresenter.swift          # shared error alert
```

## Architecture

- **UI**: SwiftUI, tab-based: Home · Photos · **+** · Growth · More (the web's phone bar). **+** presents the add sheet. More (`MoreView`) lists History, Books, Same age, Activities, Interviews and Chat, pushed onto More's own stack and badged with unread chat; deep links to History, Chat and Same age open there. The account menu keeps Tags, Face review, Settings and Log out, pushed onto the current tab and handed back when the tab is left (`AppRoute.isBorrowed`). See `redesign-plan.md`
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
| Milestone | descriptionText, category: MilestoneCategory, context (a quote's context, an interview answer's question), date, interviewId, questionId | person: Person? |
| Photo | imageData: Data? (externalStorage), title, descriptionText, photoDate, tagRemoteIds: [Int], mediaKindRaw (`MediaKind`), durationMs, status, processingError | taggedPeople: [Person] |
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
- Launch is local-first and never waits on the network. `restoreSession()` adopts the cached identity (UserDefaults) as long as a refresh credential exists, so the tabs render straight from SwiftData; `revalidateSession()` then refreshes through `APIClient.refreshAccessToken()` — the single-flight path, because the sync the restore kicks off may be refreshing too. Only a 401 (via the client's session-expired handler) ends the session; other failures keep the cached identity. With a credential but no cached identity, the launch placeholder waits for revalidation
- `APIClient.defaultSession` and `PhotoImageCache`'s session time a stalled request out at 20s rather than the system's 60s: on a weak signal, requests fall back to the queue or local data sooner. `PhotoImageCache` falls back to its on-disk `URLCache` copy, however stale, when a fetch fails, and `RemotePhotoView` retries when connectivity returns
- `loginWithGoogle()` → POST `api/login/google/token`; `loginWithApple(_:)` → POST `api/login/apple/token`. Apple's `SignInWithAppleButton` owns its own presentation, so unlike Google there is nothing to await: the view hands the raw `Result` over and `AppleSignInService` classifies it, cancellation included. The server matches the identity token's email against the same account table the password path uses, and it accepts the token only if its audience is in `APPLE_IOS_CLIENT_ID` — the app's bundle id, `com.familyrecord.ios`
- Apple releases the user's name only on the *first* authorization, which is why `AppleTokenLoginRequestDTO` carries it: every later sign-in sends an empty string and the server names the account itself
- `serverURL` persisted in UserDefaults, synced to APIClient
- `isAuthenticated` computed from `currentUser != nil`
- `access` is a `FamilyAccess` built from `currentUser.families`, the role the account holds in each family (1 view, 2 contribute, 3 admin — backend `AccessLevel`)

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

- *Members* are user accounts; `FamilyManagementView` and Home's family strip list `Person` records. The two sets never line up — a child is a person and never a member
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

### AnalysisService (`@MainActor`)
The offline-analysis procs (`backend/milestone_analysis.go` and friends), all **online-only and never queued** — the server owns the answer, and a suggestion that arrives late is worth nothing. The vision daemon runs only on staging, so every proc degrades to an empty answer in production; every caller treats a failure as "no suggestion" and every screen must look normal with nothing to show. Answers worth reusing are cached in memory for the session (cleared by `LocalDataReset`), never in SwiftData.

- `suggestMilestoneCategory` → `AddMilestoneView` pre-selects a chip only while `categoryTouched` is false and marks the header "· suggested". `suggestMilestonePhotos` fills "Photos from around then", unattached until tapped. Both run from one `.task(id: lookupKey)` that sleeps 600 ms first, so a keystroke cancels the previous lookup — the web's debounce. `EditMilestoneView` offers the photos too (not the category), excluding what the milestone had attached when the editor opened (`excludeIds`, and again locally in `MilestonePhotoSuggestions.offered`); both forms share `SuggestedPhotosRow`, and a suggestion only ever changes the selection when tapped
- `milestoneMatches` → `MilestoneMatchesSection` on the milestone page ("Clara at 1 year 2 months"); each row pushes `MilestoneDetailContent` for the local milestone when it resolves by `remoteId`
- `cachedPersonPhotoInsights` / `refreshPersonPhotoInsights` (`GetPersonPhotoInsights`, built on face data, so it answers in production too): `PersonDetailView` shows the cached answer first and refreshes on appear when online. `header` stands in for the initials avatar when the person has no profile photo, and is **never written to the model**; "Use as Profile Photo" in the manage menu hands it to `setProfilePhoto` once the photo resolves locally. `PersonPhotosTab` shows Growing up (face crops, only with two or more) and Often photographed with; Story previews up to five of those faces (`GrowingUpPreview.spread`, first to last) inside its first chapter, linking to the Photos tab — a chip filters the tab to that other person, which on a tab already limited to this person *is* the all-of intersection
- `FaceCropView` crops a server photo's medium size to a `FaceBoxDTO`. `FaceCropLayout.cropRect` pads the box as the web's `faceCropLayout` does but keeps a square in pixels rather than stretching; an empty box falls back to the thumbnail
- `photoDetails` (`GetPhoto`) → the photo page's place name under the date and its pending suggestions as **dashed** `SuggestedTagChips` after the real tags. Accept/Reject (`AcceptTagSuggestions`/`RejectTagSuggestions`, which take **suggestion** ids, never tag ids) are online-only and never queued — the server owns the outcome, since accepting a catalog label can create a family tag. Afterwards the page re-fetches `GetPhoto` and hands the before/after tag ids to `SyncService.adoptServerTags`, which re-pulls the vocabulary and either takes the server's set or, when a whole-set `updatePhotoTags` is still queued, folds only the newly added ids into it so the queued write doesn't untag them
- `tagSuggestions` (`GetTagSuggestions`) → `TagSuggestionsView`, the web's `/suggestions`, linked from the gallery toolbar with a count only when `enabled && total > 0`. A tap leaves a photo out; the bulk buttons act on the first 24 shown (`TagSuggestionReview`). After a change it re-fetches the review and runs a full pull for the photos' new tag ids
- `RemotePhotoResolution.resolve` maps server photo ids to local `Photo`s in the server's order and drops any this device doesn't hold yet

**Deliberately web-only** (from the offline-analysis work; write down, don't build): naming and managing family places (`SaveFamilyPlace`, `DeleteFamilyPlace`, `ListFamilyPlaces` — they live on the web's `/settings`, which the universal-link association claims, so the app cannot link out to them), and the age-in-text parser (`parseAgeFromText`; `WhenControl` makes age entry quick already).

**Similar stacks and place filters are laid over the mirror** (`Services/PhotoBrowse.swift`), since list items still carry neither a group nor a place. Groups come from one collapsed `ListFamilyPhotos` walk per session (every page, `limit` 200) — membership doesn't depend on filters — and `SimilarGroups.collapse` folds whatever the local filter shows: the cover when it is shown, else the first member shown, badged "+N" with the whole group, which `SimilarPhotosView` opens. "Show similar photos separately" turns it off; without groups (offline before they arrived) photos show ungrouped. A place filter asks the server for the photos there with the other panel filters (`PhotoSearchRequest.listingDTO`), cached per question; the local photos among them show, and the ones this device doesn't hold yet show from the server (`ServerPhotoCell`, `RemotePhotoDetailView`) rather than being dropped. Pending uploads have no place and no group yet. A person's Photos tab filters locally only and offers neither.

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
- `ChatWebSocketService` resets its reconnect backoff only when a frame actually arrives, not when `performConnect` returns — the handshake is still in flight then, and resetting there turned a refused handshake into a reconnect every second. A 403 or 404 handshake (the server refuses an account with no membership row for its family) is permanent: the socket goes `.failed` without retrying
- The socket authenticates with the `authToken` cookie alone, so `ChatWebSocketService` takes an `authenticate` closure that runs before **every** connect, reconnects included: `ensureFreshAccessToken()`, or a forced `refreshAccessToken()` after a 401 handshake. Without it, a socket that dropped after the token expired retried ten times on the dead cookie and stayed `.failed`
- A receive loop whose task is no longer `webSocketTask` exits without reconnecting: tearing a connection down fails its pending receive, and reconnecting from there tore down the connection that replaced it. The watchdog reconnects from a task of its own, since the reconnect cancels the watchdog and would cut its own backoff sleep short
- The app retires a `ChatService` with `disconnect()` before dropping it (`retireChatService`) — on sign-out, erase and re-initialization. The receive loop keeps the socket service alive, so dropping it alone left the previous account's socket connected
- `reconcileSent` matches a message this device sent by `clientMessageId`, from the socket echo **and** from a history page, and clears `sendFailed`: a send whose answer was lost still reached the server, and retrying it would post it twice
- The "stopped typing" timer returns when its sleep is cancelled. Swallowing the cancellation with `try?` sent "stopped" on every keystroke that rescheduled it


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
- A run that syncs a record other operations were blocked on goes round again at once (`runQueueOnce` returns whether it unblocked anything). Without that, a person and their measurement added offline arrived a foreground apart: the person in this run, the measurement whenever something next triggered one
- A pull can overlap a create on the wire. When the pull reads the server after the create committed but is applied before the create's answer, it stores its own copy under the new server id, and the local record then takes the same id — a duplicate no later pull can tell apart. Each create executor calls `dropPulledCopies` before applying its answer: the local record, the one queued operations name, keeps the id, and a person's copy hands over its measurements and milestones rather than cascading them away
- `pullFamilyData()` — fetches all data via `GetFamilyTimeline`, upserts locally
- Push methods: `addPerson`, `addGrowthData`, `updateGrowthData`, `deleteGrowthData`, `addMilestone`, `updateMilestone`, `deleteMilestone`, `deletePhoto`
- Offline support via `SyncQueue` — operations queued when offline, processed on reconnect
- Server-authoritative: on conflict, server data wins; optimistic UI for local changes
- …but only once the queue has delivered them. A pull is a snapshot from before the queued operations land, so `pullFamilyData()` reads the queue first (`pendingLocalChanges()`) and does not apply server fields to a record with a pending operation, nor recreate a record whose delete is still queued. Without this, an edit made offline visibly rolls back and a deleted record reappears until the queue catches up
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
- `addCheckup(_:for:)` queues a height and a weight from one checkup as one `createCheckup` operation → `AddCheckup`, which the server saves both or neither. It is keyed on the height's local id and carries the weight's in the payload, so `pendingLocalChanges()` protects **both** local ids; execution maps `growthData` back by `measurementType`, never by position. A checkup with one value falls back to `createGrowthData`, and `createGrowthData` operations queued by older builds still run unchanged
- A milestone's tags travel **in** `AddMilestone`/`UpdateMilestone` (`tagRemoteIds:`) rather than as a follow-up `updateMilestoneTags`, so a create never lands untagged. `nil` leaves tags alone and `[]` clears them — send `nil` from any editor that did not show the tag picker. `updateMilestoneTags` remains for the detail page's tags-only editor
- Milestone photo attachments (`addMilestone(…, photos:)` / `updateMilestone(_:photos:)`) are the *complete* set, not a delta: `nil` omits `photoIds` and leaves the server's attachments alone, `[]` detaches all of them. The queue payload holds photo *local* ids and resolves them at execution — a photo still uploading throws `missingRemoteId` (park and retry) rather than attaching fewer photos than the user chose, and a photo deleted locally drops out of the list

### Testing
- Swift Testing (`@Suite`/`@Test`/`#expect`), target `Family-Portal-IosTests`, file-system synchronized — a new file is in the target as soon as it exists
- `FakeHTTP.swift` is a `URLProtocol`-backed stand-in for the backend. Each `FakeHTTPServer` owns a unique host and routing is by host, so suites running in parallel never collide; `APIClient(baseURL:session:)` is the injection point
- `Fixtures.swift` builds request/response JSON as dictionaries, plus `TestStore` (in-memory SwiftData + scratch queue) and `TestSync.harness()` (a whole `SyncService` wired to a fake backend)
- Queue tests enqueue while `NetworkMonitor(startMonitoring: false)` reports offline, then flip it — otherwise `enqueueOperation`'s own background `processQueue` races the assertions
- `APIClientRefreshTests` is `.serialized`: token storage (keychain, shared cookie jar) is process-wide

### SyncQueue (actor)
- Persists pending operations as one JSON file (`SyncQueueStore`, written atomically, adopting any queue an older build left in UserDefaults); the file URL and legacy defaults are injectable so tests use scratch ones
- Operation types live in `SyncOperationType`; the update-shaped ones (updatePerson, updateGrowthData, updateMilestone, updatePhoto, setProfilePhoto, updatePhotoTags, updateMilestoneTags) coalesce last-wins per record, the create/delete ones do not
- Nothing merges into, or cancels against, the operation a run is sending (`beginExecuting`, cleared by `dequeue`/`markFailed`/`markBlocked`/`endExecuting`). The run dequeues it by id once the server answers, so a tag folded into it mid-flight was thrown away unsent, and an untag that cancelled an add already on the wire left the person tagged on the server
- Dependency tracking: child operations wait for parent remoteId (e.g., addGrowthData waits for person sync)
- Max 5 retries before discarding failed operations. `markFailed` *returns* the operation it discarded, because that is the moment a local change stops being "not synced yet" and becomes "never syncing" — `SyncService.discardedChangeWarning` reports it and Settings shows it until dismissed
- A network error breaks the queue run rather than marking anything failed: being offline must never spend a retry
- Blocked is tracked apart from failed. An operation waiting on something unsynced spends a `blockedCount`, never a `retryCount` — nothing was sent, so the server never said no — but 20 blocked runs discards it, because a parent whose own create was discarded is never coming. `blockedOperations` is the exact complement of `readyOperations`: an operation the dependency gate holds back never reaches `executeOperation`, so `processQueue` has to ask for it by name or nothing ever accounts for it. It re-reads the synced set first, since a parent that succeeded earlier in the same run has already unblocked its children
- `PendingOperation.blockedCount` is `@OrZero` so operations written before it existed decode as 0. The queue persists as one `[PendingOperation]` blob, so one operation from an older build failing to decode would take every pending change on the device with it — add new fields the same way, and remove fields freely (decoding ignores extra keys: `UploadPhotoPayload` dropped its caption and date, now read from the photo when the upload runs)

### Photo gallery (`PhotoGalleryView`, `PhotoImporter`, `PhotoFilter`, `PhotoFilterView`)

- **Search is the gallery mode that ranks on the server** (`PhotoSearch.swift`), never grouped. Typing filters the local mirror live, as before; submitting (return) while online sends `ListFamilyPhotos` with `query`, `limit: 60` and the panel filters (`PhotoSearchRequest`, people by server id). The results show **in server order**, resolved to local photos by `remoteId` (a result not on the device yet shows from the server in its place), with "Best matches for “…” with Clara and Mia" from `matchedPersonIds`, the web's note when `searchMode == "text"`, and paging on `nextCursor` as the last cell appears. Editing the text drops back to the local filter; changing panel filters re-asks. Offline, or when the call fails, the local filter stays and a caption says only titles and descriptions were searched

- The import itself is `PhotoImporter` (`@Observable`, `@MainActor`), not the
  gallery: there is one instance, held by `AddFlow`, so every **+** imports the
  same way and one progress bar covers every batch. Its dependencies — context, sync service,
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
- Photo import requests optional Photos library access once on the first batch.
  The picker uses `.shared()` to expose item identifiers. When the selected asset
  is authorized (including limited access), its `PHAsset.creationDate` takes
  precedence over EXIF so Photos date corrections survive import. Denied access
  or an unavailable asset falls back to EXIF, then "now" with the existing warning.
  EXIF is parsed against a fixed POSIX locale. Upload already sends this resolved
  date explicitly; the server does not have to extract it again.
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

### Notification preferences (`NotificationPreferencesModel`, `NotificationSettingsSection`)

- `GetNotificationPreferences` / `UpdateNotificationPreferences` (backend/notification_preferences.go): chat notifications (default on) and lock-screen message text (default off). They belong to the **account**, so Settings reads them from the server on open and writes each toggle immediately with both fields. Online only and never queued
- The toggles show the server's last confirmed values; a save moves them optimistically and puts them back on failure, so a failed save never reads as saved. A failed first read shows Retry rather than defaults — showing defaults would invite saving them. Missing fields decode as the server's defaults, so previews are never turned on implicitly
- Separately, the section reads `UNUserNotificationCenter`'s authorization and says when iOS itself is blocking notifications on this iPhone, with a link to its settings

### Push notifications (`PushNotificationService`)

- `AppDelegate.didFinishLaunching` makes the service `UNUserNotificationCenter`'s delegate. iOS delivers the tap that cold-launched the app only to a delegate set before launch finishes, and registration — where it used to be set — runs after sign-in, a full sync and chat
- That tap can still arrive before the scene's `.task` hands over the `DeepLinkRouter`, so a payload with no router yet waits in `pendingPayload` and is opened when `router` is set

### Original photos (`OriginalPhotoActions`)

- The photo page's toolbar offers **Share Original** and **Save to Photos** for an uploaded photo — the web's "Download original". `APIClient.downloadOriginal` fetches `api/photo/{id}/original?download=1` (bytes as uploaded, never a resized variant) with the token and one refresh-and-retry on 401, straight to disk, into a folder of its own named after `Content-Disposition` (`OriginalPhotoFile.filename`). The folder is removed when the share sheet closes or the save finishes
- Online only; a cancelled download is silent; failures go through `ErrorPresenter` and the page stays. Save asks for **add-only** Photos access (`NSPhotoLibraryAddUsageDescription`) at the moment the user chooses it; `PhotoLibrarySaver` is `nonisolated` because PhotoKit runs the change block off the main actor. A photo not uploaded yet says so instead of offering either action
- A video's original is not at `api/photo/{id}/original` (404). The menu asks `GetVideoPlayback` for a fresh `downloadUrl` every time and fetches it with `APIClient.downloadMedia` — **no token and no cookies** (`httpShouldHandleCookies = false`), since a minted link carries its own authority and a bucket refuses more. `APIClient.mediaURL` resolves a `/`-relative link against the origin rather than appending it, so the signed query survives. Saved as a `.video` asset

### Video (`video-plan.md`)

- A video is a `Photo` with `mediaKind == .video`, pulled through the same `ListFamilyPhotos`/`GetFamilyTimeline`. Everywhere it is listed it shows its poster (the ordinary variants) with `VideoBadge`, which `PhotoThumbnailView` draws when given `videoDurationMs` (`Photo.videoBadgeDuration`). Server-id-only cells get no badge until the mirror catches up; attached-media thumbnails drawn from a server id (activity strips, a milestone's photos) badge through `.videoBadge(remoteId:)`, which asks the mirror (`MirroredPhoto`)
- Attached media opens where a video can play: `ActivityPhotoStrip` thumbnails link to `AppRoute.remotePhoto` (keep the strip outside a `NavigationLink` label — `AppearanceDetailRow(showsPhotos: false)` where the row is one), and the milestone viewer pages through `RemoteMediaView`. `RemoteMediaView` plays a video the mirror knows, and for an id the mirror doesn't hold asks `GetPhoto` once online for its `mediaKind`, so `RemotePhotoDetailView` plays one too (`VideoPlayerSection` takes a nil `Photo` then)
- Kept out of the profile-photo picker and **Use as Profile Photo** (`SetProfilePhoto` refuses one). Widgets skip a video until its `status` is 0, since a processing poster is the server's SVG placeholder. Same age, Growing up, books and face review are fed by server procs that already filter videos
- The photo page shows `VideoPlayerSection` for a video: `VideoPlayerModel` asks `GetVideoPlayback` on appear (polling every 5 s while `status` is 1), then plays the link in `AVPlayerViewController` over an `AVURLAsset` with `AVURLAssetHTTPCookiesKey: []`. A player failure probes the link (`APIClient.probeMedia`, one byte, no credentials) and `VideoPlayback.classify` — the web's `classifyPlaybackError` and its test table — decides: renew and resume at the same position (up to 3 times), "can't be played here", or Playback stopped + Try again. Links are never stored. Item status is watched through `publisher(for: \.status).values` on the main actor, not a KVO closure
- Upload: the add sheet asks `GetVideoSupport` when it opens (online; `AddFlow.refreshVideoSupport` → `PhotoImporter.videoSupport`) and only then lets the picker match `.videos`. A picked video is **not queued**: `PhotoImporter.importVideo` copies it out (`PickedVideo`, a `FileRepresentation`), checks it (`VideoFiles`, the web's `videoFiles.ts` wording), and runs `VideoUploadService` — `BeginVideoUpload` with no people, the file sent with exactly the instructed method and headers and no credentials (`APIClient.uploadMedia`, streamed from disk), then `CompleteVideoUpload` retried up to 4 times except on an expired or unknown session; a failed send cancels. The returned image becomes a `Photo` with its server id, so the batch form's people, caption and tags queue against it like any uploaded photo. Its row shows the upload percentage, then Processing, and a refusal's own sentence

### Adding records

The redesign (`redesign-plan.md`, phase 2) replaced the per-tab `QuickAddMenu`.

- **One add sheet.** `AddFlow` is app-scoped (like `ErrorPresenter`) and presented
  from the shell, so every **+** — the tab bar's, a person page's — opens the same
  sheet: "Who is this for?" chips, Photos · Measurement · Milestone, and up to two
  "Result — {event}" rows from `ListOpenEvents` (which open the event's page on the
  current tab). The sheet closes before its form opens; forms are sheets over the
  origin, so Done returns there
- **Explicit context, never silent inheritance.** A person is preselected only from
  the screen underneath or `QuickAddDefaults`' remembered person, always as a
  visible chip that a tap clears. The chosen person is written back as the
  remembered one. Photos from the global **+** start with nobody tagged
- `PersonChips` orders people with `FamilyGroups.chipOrder` (children first, then
  older generations, unlinked, then linked households — `Person.familyRemoteId`)
- `WhenControl` ("Today ▾": Today, Yesterday, Pick a date…, By age…) is keyed with
  `.id(person?.id)`: an age resolves against the birthday it was handed.
  `WhenEntry.resolvedDate` turns an age into a date on the device, and every write
  sends the **local** calendar day as `inputType: "date"` — never `"today"`,
  which is the server's UTC day
- **Days are record dates** (`Utilities/ServerDate.swift`): birthdays,
  measurement, milestone and activity dates are stored as midnight UTC of the day
  they name, and photo dates as the capture wall clock labelled UTC. Read them
  with `recordDay` / `recordDayKey`, show or edit them with `displayDay()`, and
  turn `Date()` or a `DatePicker` value into one with `localRecordDay()` (or
  `localWallClock()` for a photo). Never format a record date directly or mix it
  with `Calendar.current` arithmetic on `Date()`
- **Measurement is one checkup** (`Checkup`): height and weight together, either
  blank. Units are remembered per person, then per family (`QuickAddDefaults.unitPrefs`),
  and a unit is only ever used for a type it can measure. Save queues one
  `AddGrowthData` per field and pushes `CheckupResultView` — Saved / Waiting to
  sync from `remoteId`, a field whose enqueue failed retried on its own, **Add
  another measurement** (person cleared, date kept) and Done, pinned below the
  scroll. It shows one Same age strip for the whole checkup
  (`MeasurementInsightsView(showsSameAge: false)`), not one per value
- **Context folds.** Family comparison, the Same age strip and "The same milestone
  in the family" sit under a `ContextSection` heading that folds them away. Each
  kind (`ContextKind`) remembers being folded, in `@AppStorage`, across every
  screen it appears on; all start open. A record's own details (a milestone's
  tags included) come before its context
- **Milestone:** chips, "What happened?", category chips, When, and an "Add
  photos / tags" disclosure. Save shows the milestone in the same sheet.
  Every category offers "Add New Photos" (`MilestonePhotoUploadSection`), with
  "Photos of it" wording for artwork. Picks stay in the form until Save, then
  become photos tagged to the selected person, queued ahead of the milestone
  that attaches them. Save waits for picked images to finish loading
- **Photos upload first.** The pick goes straight to `PhotoImporter`; the batch
  form (`PhotoBatchFormView`) opens over the import with Who's in these?, Caption
  and Tags for the whole batch and each photo's date and status.
  `PhotoImporter` reports when a file had no capture date ("No date in photo:
  using today"). Done queues `AddPeopleToPhoto`, `UpdatePhotoTags` and
  `UpdatePhoto` (`inputType: "keep"` unless the date changed) behind each
  upload, including for photos still being read; it never cancels an upload
- `updatePhoto(_:keepingDate:)` takes the choice explicitly. Anything without a date control — the photo page's title and description — passes `true`: a dated update sends only the day and wiped the capture time. A queued update is replaced whole, so `keepingDate: true` turns into a dated update while a date change for the same photo is still waiting to be sent
- Milestone and measurement are **disabled** on an empty roster rather than
  opening a form that could never save
- An unrecognised remembered id resolves to *nobody*, never to somebody near it: a
  local id outlives an account erase. `LocalDataReset` therefore needs no sweep
- A roster row's long press opens the forms directly (`AddFlow.open`), with the
  person already chosen

### Viewing records

- Tapping a milestone or a measurement anywhere — History, a person's Story or
  Growth tab, Home — opens a **view** sheet, not the editor. These records are read
  many times and changed almost never, so the editor sits one step further in,
  behind the sheet's Edit button
- `MilestoneDetailSheetView` and `MeasurementDetailSheetView` are built from the
  same parts in `DetailSheetComponents`: a `DetailSheetHeader` (tinted category
  chip over the record's own words), then a `DetailFieldGroup` of
  `DetailFieldRow`s. New facts go in the group, and both sheets keep their shape
- Editing tags is the one edit that stays on the milestone sheet: `TagPickerView`
  saves through `updateMilestoneTags` on its own rather than through the editor,
  which knows nothing about tags
- `RecordStyle` holds the glyph and tint for a `MilestoneCategory` and a
  `MeasurementType`. Three views had grown their own copy of those switches
- `Person.age(on:)` (in `AgeCalculator.swift`) is how both sheets say how old
  somebody was on the day the record is dated

### Same age (`Views/SameAge/`)

The web's `/same-age` (`same-age.tsx`, `SameAgePortraits`, `sameAgeNavigation.ts`) and the strips under records.

- Two views, **Portraits** (the default, faces oldest first, tapping one opens the whole photo with Another photo) and **Details** (rows with records, the rest counted). `?view=details` rides on `DeepLink.sameAge` and `AppRoute.sameAge`; strips' "See everything" opens Details
- Only the browse page sends `includeAvailableAges` — it makes the server scan the photo history. Strips never do. The answer's `availableAges`/`portraitAges` are what Younger/Older step through (per view) and what the age list counts; they are kept from the first load while later steps ask lightweight. A server without them (keys absent → nil, unlike a `null` list) falls back to stepping the age grid and the wheel picker
- A direct visit (no age, no person) lets the server pick the starting age; a link's age is kept even when empty. The newborn window is the server's
- `SameAgeBrowser` tracks the chosen age apart from the answer on screen and drops any answer that a newer choice has superseded. `SameAgeCache` keys on the request including the day and whether it discovered; a discovering answer also fills the lightweight key for its answered age, never the reverse

### Permissions (`FamilyAccess`)

- A view-only member sees everything and no control that changes it, as on the
  web: every add, Edit, tag picker and delete is gated on `authService.access`.
  The server enforces the same rules; hiding the controls only spares a button that
  could only fail
- A record's family: `Person.familyRemoteId`, `Photo.familyRemoteId`, a milestone's
  or measurement's person's, a tag's or activity record's `familyId`. `nil` (added
  offline, or pulled before the field existed) reads as the account's own family
- Contribute is enough to add or edit; deleting a photo or a tag and rotating an
  invite code take admin. Add forms pass `contributableOnly: true` to `PersonChips`

### Activity matchups (`Services/Matchups.swift`)

- An appearance can carry a head-to-head round (`round`, `opponent`, `outcome`, optional `scoreFor`/`scoreAgainst`), flat on `AppearanceDTO`. `Matchups` is a port of `frontend/lib/matchups.ts` with its test table (`MatchupTests`): the matchup line, W–L(–D) records, and an entry's run summary. Change both together
- `CreateAppearance`/`UpdateAppearance` take an all-or-nothing `matchup`: absent on update leaves the stored one alone, an empty one clears it. The editor (`AppearanceMatchupSection`) always sends its whole matchup on update. A score is 0–9999, and `nil` means none was kept, never 0
- A sport's event is an "Event" and its appearance a "Game" (`ActivityLabels.sport`), as on the web

### Books (`BookService`, `BookAssembler`, `Views/Books/`)

The web's `/books`, `/book/<id>`, `/new-book` and `/edit-book/<id>`. Reached from More and a person's toolbar; "Start a book" and the reader's Edit appear only when the server says `canEdit`.

- `ListBooks` and `GetBook` are read through `ActivityRead` and cached in `ActivitySnapshotCache` (so `LocalDataReset` already sweeps them, and a book opened once reads offline). Never in SwiftData: a book is references the server resolves against its own permissions, and `GetBook` sends the records with it
- A saved book is only references and order. `BookAssembler` (`Utilities/BookAssembly.swift`) is a port of `assembleBook` in `frontend/lib/book.ts` and turns them into a cover, chapters and blocks exactly as the web does — change both together. `Utilities/BookSuggestions.swift` ports the suggesting half (`suggestItems`, `additionsSince`, `draftSelection`) and `bookPlans.ts`, so a draft or a re-pick on the phone is the one the web would make
- The book DTOs keep dates as the server's ISO **strings**, and `BookDay` does its arithmetic on `YYYY-MM-DD` the way the web's `dayOf` does, so no time zone enters a book's chapters
- Writes (`GetBookSources`, `CreateBook`, `UpdateBook`, `DeleteBook`) are online-only and never queued. A new book is drafted on the device from `GetBookSources` and created in one call. The editor works on a copy (`BookDTO` is all `var`) and sends the whole book on Save with the revision it opened; `ErrBookChanged` is matched word for word (`BookService.isChangedConflict`) and answered with "Close and Reload". Edit is disabled over a cached copy for that reason
- Save sends `reviewedAt` as `GetBook`'s `now` — the server's clock, which stamped `createdAt` — and omits it on create (Go cannot parse an empty time). Every category chosen is sent as `[]`, the server's "everything"
- Removing an item moves it to `excluded`, which a re-pick never brings back; "Keep" (`pinned`) survives re-picks. A drag reorders a chapter's items among the slots they already hold in the book's list
- The reader is set on its own paper (`BookPalette`) in the system serif, with no editing chrome. The growth chart runs birth → one year in a first-year book and the book's own first → last day otherwise (the web clamps every book to the first year)

### Annual interview (`InterviewService`, `Utilities/Interviews.swift`, `Views/Interviews/`)

The web's `/interview/<id>` and the folding of answers everywhere moments are listed. The phased plan is at the top of `plan.md`.

- An **answer** is a moment: `category == .interview`, `interviewId`/`questionId` set, `context` holding the question as it was asked. Answers arrive in the ordinary pull and live in SwiftData. Only the interview procs create them, so `MilestoneCategory.pickable` (every case but `.interview`) is what the add and edit forms offer, and `UpdateMilestone` refuses a switch to or from it
- Editing an answer changes its text, photos and tags only: `EditMilestoneView` hides the category and the date (the date follows the interview), and `setEntry` leaves an answer's `context` alone. The answer's page shows the question above it and links to its interview
- **Fold.** `Interviews.fold` (a port of `groupInterviewAnswers`) turns answers into one `InterviewAnswers` group per interview. `DaySummaries.summarize` folds (History, Story, Home's recent), and Home's on-this-day and same-age rows fold their DTOs, taking the title and portrait from the response's `interviews`. The store's cards have no `InterviewDTO`, so they go without a portrait or a custom title. Widgets leave answers out of the pool entirely
- The **interview** itself (`InterviewDTO`) and the question list are server-only, read through `ActivitySnapshotCache` like books. Writes are online only and never queued. `UpdateInterview` assigns every field, so `UpdateInterviewRequestDTO` is built from the whole interview plus the change; `ErrInterviewChanged` is matched word for word (`InterviewService.isChangedConflict`)
- A write that changes answers on the server (a new date rewrites them all; a delete removes them) is followed locally: a date change pulls, and a delete removes the local answers at once
- `GetInterview`'s `previous` is a Go `map[int]…`, which marshals its keys as strings, so it decodes as `[String: …]` behind `previous(for:)`
- **Conduct** (`InterviewSetupView`, `InterviewAskView`, `InterviewSession`): setup is one `GetInterviewSetup` call (never cached — a missed in-progress interview would start a second one the server refuses) and starts with saved questions by id and unsaved built-ins by `defaultKey`. `InterviewSession` is a port of `ask.tsx`'s state: an answer saves when the parent moves on, the text being typed is held in `InterviewDrafts` (UserDefaults, the web's localStorage) until the save succeeds, and a save that fails for a lost connection or a 5xx retries every 4 s behind a quiet "Not saved yet" line, while a refusal is shown and not retried. `finish` awaits every save before marking the interview complete, then the screen pulls so the answers reach the store. Return in the answer field moves on, as Enter does on the web
- A portrait goes straight to `api/upload-photo` (`InterviewService.uploadPortrait`) rather than through the queue, because `UpdateInterview` needs its id now. `CameraCaptureView` wraps the system camera (`NSCameraUsageDescription`); without one, the library picker stands in
- Entry points: the person page's Interviews tab (`PersonInterviewsTab`: Start or Continue, then each interview as a card, from one cached `GetPersonInterviews`), Home's `interview` and `interview-continue` nudges, and `/interview/<id>/ask`. The tab shows for anyone with an interview, or anyone this account can interview; the person page's tabs scroll sideways (`PersonTabBar`), since a child can now have seven
- **Looking back** (`Interviews.grid`, `timelines`, `sorted`, `filtered`, `byAge` — ports of `interviewGrid`, `questionTimelines`, `sortTimelines`, `filterTimelines` and `compareByAge`, with the web's fixture in `InterviewOverTimeTests`): the Interviews tab offers **Questions** (one card per question, its answers by age, filter and sort) first, where the web starts on Years, since a grid of years does not fit a phone; **Years** is a `Grid` that scrolls sideways as a whole. Swift's sort is not stable, so the sorts tie-break on list position to match the web's. `FamilyInterviewsView` (More → Interviews, `GetFamilyInterviews`) lists children first with Start, Continue or "Due soon"; `InterviewCompareView` (`CompareInterviewAnswers`) is "Compare at the same age"
- **Past interviews** (`PastInterviewView`, `PastInterviewDraft`): the web's `/interview/past/<id>`, from the tab ("Type in a past one") and the family page. When it was is a `WhenControl` starting on By age; the request goes as `when.request(now:)`, an age resolved by the server, since unlike a moment nothing is stored locally first. Listed questions go by `Interviews.ref`, extras by their text with "Add to my list"; blank means not asked. One `SaveHistoricalInterview` writes it all, then the screen pulls. The interview page's **Edit answers** sheet sends one `SaveInterviewAnswer` per changed answer (empty deletes it)
- **Question editor** (`InterviewQuestionsView`, `QuestionListDraft` — a port of `frontend/lib/interviewQuestions.ts`, cases in `InterviewQuestionListTests`): the web's `/interview-questions`, from setup ("Edit the question list") and the family page. Edits are a draft until Save sends the whole list in section order with the revision it read (`ErrInterviewQuestionsChanged` refuses a stale one). `QuestionRow.questionId` is the server's id (0 until saved) and `key` its identity. Reordering is Move up/Move down in a row's context menu (the web's non-drag fallback); swipe to retire, or to delete one never asked (`usage`, string-keyed like `previous`). Merge is offered only with nothing unsaved, as on the web
- `/interview/<id>` and `/interview/<id>/ask` are universal links (`backend/universal_links.go` claims `/interview/*`, `/interviews` and `/interview-questions`, and excludes `/interview/import`: pasting stays on the web). `DeepLink` also parses `/interview/new/<personId>`, `/interview/past/<personId>`, `/interview/compare?question=`, `/interviews` and `/interview-questions`

### Widgets (`FamilyRecordWidgets/`, `Shared/`, `WidgetSnapshotBuilder`, `WidgetPublisher`)

See `plan.md`. The app publishes, the extension only reads.

- `Shared/` is compiled into **both** targets: the snapshot model (`WidgetSnapshot`), the App Group store (`WidgetStore`, `group.com.familyrecord.ios/Widgets/`: `snapshot.json` plus `images/<remoteId>.jpg`), the timeline logic (`WidgetTimeline`, `WidgetMoment`) and the widgets' words (`WidgetCopy`). Types there are `nonisolated` because the app defaults to main-actor isolation and the extension does not. The extension never touches the network, the keychain or SwiftData
- `WidgetSnapshotBuilder` picks 14 days of "On this day" (`Utilities/OnThisDay.swift`, the port of `onThisDay` in `backend/dashboard.go`: 1–30 years, ±2 days, ≤8 photos a year newest first; 29 February moves to 1 March as Go's `AddDate` does) and a memory pool, downsamples at most 80 images to 600 px (local bytes for a pending upload, else the `medium` variant through `PhotoImageCache`), writes, prunes, and reuses any image already on disk. A photo item whose image could not be had is dropped; a milestone keeps its words
- `WidgetPublisher` runs one build at a time (a request during a run reruns it). It publishes after every `performFullSync` (`SyncService.onFullSyncFinished`, not awaited) and on backgrounding when the snapshot is over 6 hours old. `clear()` bumps a generation so a run already downloading cannot write after it; it runs whenever `isAuthenticated` goes false and from `LocalDataReset.erase(.everything)`
- Rendering modes: in full color a small widget's photo is its `containerBackground`, and moves into the content when StandBy or CarPlay removes the background; accented (CarPlay, tinted Home Screen) leads with words over a desaturated photo (`.widgetAccentedRenderingMode(.accentedDesaturated)` on every snapshot image); vibrant is words only. Medium and large add "Open Family Record to refresh" once the day is past the snapshot's horizon
- `WidgetBackgroundRefresh` books a `BGAppRefreshTask` (`com.familyrecord.ios.widget-refresh`) for just after local midnight on every publish and registers its handler in `didFinishLaunching`. It republishes from the store without pulling — a background launch has no restored session — and only for `WidgetPublisher.liveOwner`, which `clear()` removes, so a signed-out widget stays signed out
- A widget item opens its record: `/view-photo/<id>` (`DeepLink.photo`, the local photo on the Photos tab, else `RemotePhotoDetailView`) or `/milestone/<id>` (`DeepLink.milestone` → `AppRoute.milestone`, waiting like a person link for a sync to bring a milestone not on the device yet). Items with no server id open `/dashboard`. Both paths are in `backend/universal_links.go` too
- **Memory** (`MemoryWidget`, `MemoryWidgetIntent`): content (Everything / Photos / Milestones incl. artwork / Quotes), an optional person and a rotation (hourly, 6 hours, daily). It walks the filtered pool one item per rotation slot from local midnight; Shuffle (`ShuffleMemoryIntent`, `Button(intent:)` on medium and large) advances `WidgetShuffle`'s offset in the App Group's defaults and reloads that kind. On This Day takes the same optional person (`OnThisDayIntent`). `PersonEntity`'s choices are the snapshot's people, so configuring needs no network
- The pool is drawn in strata — 30 photos, 15 milestones, 15 quotes — then topped up so everyone with a server id is in at least 6 items, so a filtered Memory widget still has something to turn over
- **Quote** (`QuoteWidget`; small, medium, Lock Screen; optional person) reads `snapshot.quotes` — every quote, up to 300 — turned over every 3 hours. Words only, so it is the car-friendly choice
- **Family** (`FamilyAgesWidget`, kind still `FamilyAges`; gallery name "Family"; small, medium, large, Lock Screen rectangular and inline) lists the Home strip's people (pregnancies first, then `FamilyGroups.chipOrder` with `WidgetPublisher.ownFamilyId`) with `FamilyStrip`'s ages and any birthday within 14 days. The app works out every day of the horizon (`snapshot.family`, `WidgetFamilyMember.ageByDay`/`birthdayByDay`, the birthday carrying `turning` so nothing parses its sentence), since the extension has no `FamilyStrip`; a 29 February birthday falls on 1 March in a common year. `quotes` and `family` are optional so a version-1 snapshot without them still decodes
  - Who it shows: **People** when any are chosen, else **Person**, else everyone (`WidgetTimeline.familySelection`), always in family order. A chosen person with no age is a row saying "No birthday", never dropped
  - Medium and large are the overview: two columns (six cells, eight on large; fewer at larger text sizes), and when there are more people the last cell counts them ("+N more · Open family") — `FamilyAges.overview(capacity:)`. Nobody is left out without saying so
  - Small and the accessories are about one thing, never a partial roster (`FamilyFocus`): the one person chosen, else the soonest birthday (same-day birthdays together), else "Family spotlight", which walks everyone with an age one day at a time
- **Composition follows the content** (redesign step A in `plan.md`). Memory is one record per entry (`SingleMemoryView`): a picture leads with the record's own words, a words-only record is the card's focus (`FeatureText` sizes by length), and a footer holds the date and Shuffle, which shows only when the usable pool has two or more items (`WidgetMoment.canShuffle`). Shuffle's offset is shared, so it moves every Memory widget. On This Day with several records (`DayMediumView`, `DayLargeView`) captions each photo with its own words and gives every other record its own block and `Link`; a day with one record uses the Memory composition. Artwork is fitted, never cropped
- **Dating is truthful** (`WidgetDating`): only an exact anniversary (`WidgetDay.isAnniversary`, with 29 February on 1 March in a common year) says "On this day"; the rest of the ±2 window says "Around this day" with its own date, and a pool item says "A memory"
- Providers check each image file once per timeline (`SnapshotImageCheck`) and pass it as `imageAvailable`: a photo whose file is missing or undecodable leaves the pool or the day, and a milestone keeps its words without the picture
- The widget walks its timeline in 3-hour slots from local midnight: a day's pictures take turns, and a day with nothing shows a pool item chosen by slot, so a reload never reshuffles what is on screen

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
- `AddPerson`, `AddGrowthData`, `AddCheckup`, `UpdateGrowthData`, `DeleteGrowthData`
- `GetPersonRelations`, `AddRelation`, `RemoveRelation` (backend/relation.go)
- `AddMilestone`, `UpdateMilestone`, `DeleteMilestone`
- `AddPeopleToPhoto`, `RemovePersonFromPhoto`, `DeletePhoto`
- `SetProfilePhoto`
- `ListFamilyMembers`, `RemoveFamilyMember`, `LeaveFamily`, `RotateInviteCode`
- `SendMessage`, `GetChatMessages`, `DeleteMessage` (chat; live delivery is the
  WebSocket, these three are the REST half)
- `GetNotificationPreferences`, `UpdateNotificationPreferences` (account push settings, online only)
- `SuggestMilestoneCategory`, `SuggestMilestonePhotos`, `GetMilestoneMatches`, `GetPersonPhotoInsights`, `GetPhoto`, `GetTagSuggestions`, `AcceptTagSuggestions`, `RejectTagSuggestions` (online-only analysis calls; see AnalysisService)
- `ListBooks`, `GetBook`, `GetBookSources`, `CreateBook`, `UpdateBook`, `DeleteBook` (backend/book.go; see Books)
- `ListTags`, `UpdatePhotoTags`, `UpdateMilestoneTags` (see the notes under SyncService). The two writes are registered from `backend/photos.go` and `backend/milestone.go`, not `backend/tags.go`
- `CreateTag`, `UpdateTag`, `DeleteTag` (the Tags screen, via `TagService`; online only — the server refuses a duplicate name, so a queued create could not be trusted. After each, `SyncService.refreshTags()` re-pulls the `FamilyTag` mirror. `UpdateTag`'s `autoPhrase` is a Go pointer, so the screen always sends it: absent would leave the phrase, empty clears it)
- `GetFaceReview`, `AssignFaces`, `RejectFaces`, `DismissFaces` (the Faces screen, via `FaceReviewService`; online only. Each change reloads the review, because naming a face re-matches the family on the server; leaving after a change runs `pullFamilyData` so photos pick up their new people. The review's counts also feed the account-menu badge through `AppNavigator.updateFaceReviewCount`)

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
AddCheckup: { personId: Int, inputType: "date", measurementDate: "YYYY-MM-DD", height: {value, unit}?, weight: {value, unit}? }  // → { growthData: [only those sent, height first] }
UpdateGrowthData: { id: Int, measurementType: "height"|"weight", value: Double, unit: String, inputType: String, measurementDate: String? }
DeleteGrowthData: { id: Int }
AddMilestone: { personId: Int, description: String, category: String, context: String, inputType: String, milestoneDate: "YYYY-MM-DD"?, photoIds: [Int]?, tagIds: [Int]? }
UpdateMilestone: { id: Int, description: String, category: String, context: String, inputType: String, milestoneDate: String?, photoIds: [Int]?, tagIds: [Int]? }  // absent tagIds leaves tags alone
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
