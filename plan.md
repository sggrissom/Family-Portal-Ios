# iOS catch-up plan

Status: all five phases implemented as stacked PRs (#101 → #105), each green in CI (build + unit tests). Not yet merged, and not yet checked on a simulator or device.
Reviewed: October 7, 2026.

## Goal and baseline

Bring the iOS app up to date with the Family Portal website's implemented family-record features, prioritizing useful browsing and discovery over exhaustive administrative parity. Preserve the app's native SwiftUI navigation, local-first records, offline queue, and permission checks.

This plan comes from a source comparison of:

- [Family Portal iOS at 25e871d](https://github.com/sggrissom/Family-Portal-Ios/tree/25e871d).
- [Family Portal at ef17e4d](https://github.com/sggrissom/Family-Portal/tree/ef17e4d).

All RPC names declared by iOS were present in the reviewed backend. That check does not establish full request/response or runtime compatibility. No simulator or device testing was performed for this review. Recheck both repositories before implementing each phase; a feature on web main may not yet be deployed to the app's configured server.

Already present in iOS: books creation/reading/editing, quotes, artwork, activities/results, face review, tag suggestions, server-backed photo search, permission-aware editing, and the recent calendar-date changes. Extend these implementations rather than replacing them. Planned web features are not automatically iOS parity requirements.

## Delivery order

| Phase | Work | Priority | Relative size | PR |
| --- | --- | --- | --- | --- |
| 1 | Same age browsing and portrait-first presentation | High | Medium–large | #101 |
| 2 | More navigation and Growing up Story preview | High | Small–medium | #102 |
| 3 | Original-photo download/share and edit-milestone photo suggestions | Medium | Medium | #103 |
| 4 | Push notification preferences | Medium | Small | #104 |
| 5 | Similar-photo grouping and place filters | Lower | Medium–large | #105 |

Each phase can ship independently. Keep the changes focused; avoid a general architecture rewrite.

## Phase 1: Same age

### Current gap

The website now separates Portraits from Details, discovers ages with saved content, offers age shortcuts, and starts a direct visit at a useful comparison. iOS still steps across the full age range and renders a montage followed by record rows. Its montage disappears when only one person has a portrait.

The iOS request omits `includeAvailableAges` and `details`; its response model omits `availableAges`, `portraitAges`, and `peopleCount`. The full page and embedded strips share a loader/cache, so discovery must not accidentally be requested by every record detail.

### Implementation

- [x] Extend `OverviewDTOs.swift` for the new request flags, age options, and counts. Decode absent fields compatibly with older servers, distinguishing unavailable discovery from a genuinely empty result where necessary.
- [x] Request age discovery for the full browse page. Keep embedded strips lightweight.
- [x] Use portrait ages in Portraits and recorded ages in Details; step to the next available age rather than the next interval across years of empty data.
- [x] Add the web's age shortcuts and an age picker showing how many people have content. Preserve explicitly requested ages even if empty.
- [x] Default a direct visit to Portraits and let the server select its starting age. Preserve contextual person/age links.
- [x] Show a portrait grid with meaningful zero-, one-, and multiple-person states. Keep missing-photo names secondary. Move alternative-photo cycling and the original image into a focused viewer.
- [x] Keep measurements and milestones in Details, emphasizing rows with records and collapsing missing records.
- [x] Keep controls stable and visible while loading. Track the requested age separately from the displayed response, ignore cancelled/stale results, and provide retry without losing the chosen age.
- [x] Update cache handling so a lightweight strip response cannot satisfy a browse request that needs discovery metadata. Retain discovered options across subsequent lightweight age requests; invalidate date-sensitive defaults appropriately.
- [x] Carry the `view=details` selection through deep-link parsing and navigation. Update contextual record links deliberately.
- [x] Match the current web wording for newborns: the server owns the newborn window; do not reimplement its selection rules locally.

### Acceptance

- A direct visit starts with a useful comparison when one exists.
- Younger/Older skip empty ages for the selected view.
- Newborn, one-person, no-portrait, no-record, and explicitly empty-age cases make sense.
- Rapid navigation never lets an older response replace the latest selection.
- Portraits/Details links reopen the intended view; embedded strips still work.
- Cached/offline behavior and older-server fallbacks remain usable.

Primary files: `Services/OverviewDTOs.swift`, `Views/SameAge/`, `Utilities/DeepLink.swift`, and `Views/Shell/AppNavigator.swift`.

Web references: `backend/same_age.go`, `frontend/pages/same-age/same-age.tsx`, `frontend/components/SameAgePortraits.tsx`, and `frontend/lib/sameAgeNavigation.ts`.

Done in #101. Older servers without discovery fall back to grid stepping and the wheel picker. Deferred: manual checks on device; strips' "See everything" opens Details, while photo pages keep their strip rather than the web's Portraits link.

## Phase 2: Navigation and Growing up discovery

### Implementation

- [x] Add a visible More destination containing History, Books, Same age, Activities, and Chat, following the website's browsing organization.
- [x] Keep Add as an action and preserve its permission-dependent visibility.
- [x] Keep account/session/settings controls in the account menu. Preserve chat unread visibility and existing per-tab navigation behavior.
- [x] Add a compact Growing up preview to a person's Story tab when enough portraits exist. Spread the preview across the available timeline and link to the full Photos-tab collection.
- [x] Reuse the existing photo-insights response and face crop views; do not add a second portrait-ranking mechanism.

### Acceptance

- Books and Same age are discoverable without opening an account-management menu.
- Existing deep links, tab reselection, add flows, and view-only accounts still behave correctly.
- Growing up is discoverable from Story without dominating it; empty insights add no clutter.

Primary files: `ContentView.swift`, `Views/Shell/AccountMenu.swift`, `Views/Shell/AppNavigator.swift`, `Views/Family/PersonDetailView.swift`, and `Views/Family/PersonTabs.swift`.

Web references: `frontend/components/AppNav.tsx` and `frontend/pages/profile/profile.tsx`.

Done in #102. The unread-chat badge moved from the account avatar to the More tab and its Chat row.

## Phase 3: Photo actions and milestone editing

### Original photos

- [x] Add Share original and Save to Photos actions for uploaded photos using the existing authenticated `/api/photo/{id}/original?download=1` endpoint.
- [x] Download the original bytes rather than a resized display image. Preserve the response's filename/type when possible.
- [x] Use the app's authentication/refresh behavior, show progress and failures, and clean up temporary share files safely.
- [x] Request only the Photos permission required for saving, when the user chooses that action. Handle local-only photos explicitly.

Acceptance: a user can share/save an original photo, cancellation and denied permission are handled, and offline/authentication failures are visible without losing the detail screen.

Primary files: `Views/Photos/PhotoDetailView.swift`, `Services/APIClient.swift`, and the app's privacy usage descriptions as needed.

### Photo suggestions while editing milestones

- [x] Reuse the existing suggestion service in `EditMilestoneView`, based on the current person, description, and date.
- [x] Debounce requests, discard stale responses, and exclude already selected attachments.
- [x] Suggestions require an explicit selection; they must not change attachments automatically.
- [x] Preserve current selections when suggestions fail or the device is offline, including artwork attachment behavior.

Acceptance: editing offers nearby photos, saving preserves the user's complete attachment selection, and unavailable analysis does not block ordinary editing.

Web references: `frontend/pages/photos/view-photo.tsx` and `frontend/pages/milestones/edit-milestone.tsx`.

Done in #103. Deferred: manual checks of the share sheet and the Photos add-only permission prompt on device.

## Phase 4: Notification preferences

- [x] Add DTOs/service calls for `GetNotificationPreferences` and `UpdateNotificationPreferences`.
- [x] Expose the existing chat-notification and message-preview preferences in Settings.
- [x] Follow the server's defaults and validation; do not enable message previews implicitly.
- [x] Treat saves as online-only and retain/recover the last confirmed values after failure.
- [x] Explain the distinction between account preferences and iOS notification authorization.

Acceptance: changes made on web are reflected in the app, app changes persist on the server, and failed saves never appear successful.

Primary files: `Services/RPCMethod.swift` and `Views/Settings/SettingsView.swift`, with a small service/DTO addition following existing conventions.

Web reference: `frontend/pages/settings/settings.tsx`.

Done in #104. Deferred: confirming the configured server has the two procs deployed; without them the section shows Retry rather than defaults.

## Phase 5: Photo browsing parity

- [x] Add similar-photo groups with a representative image, count badge, and group viewer.
- [x] Support the web's choice to show similar photos separately.
- [x] Add place filters backed by the existing server APIs.
- [x] Keep ranked search distinct from grouped browsing, as on the website.
- [x] Define how server grouping/place metadata coexists with the local photo mirror, pending uploads, paging, and offline filters before changing the gallery.
- [x] Do not silently omit server-returned photos merely because their local mirror record has not arrived.

Acceptance: users can open every photo in a group, filters compose predictably, search preserves server ranking, and offline browsing still works. Photo-date filtering must preserve the recent calendar-date fixes.

Primary files: `Views/Photos/PhotoGalleryView.swift`, `PhotoFilter.swift`, `PhotoFilterView.swift`, and the photo DTO/service layer.

Web reference: `frontend/pages/photos/family-photos.tsx`.

Done in #105. Groups and places are laid over the local mirror rather than replacing it (see `Services/PhotoBrowse.swift`): groups load once per session and fold whatever the local filters show; a place filter fetches the matching server ids, and photos the device lacks are shown from the server. Deferred: manual checks on device and with large libraries (group loading walks every page once per session).

## Deferred management parity

These are existing web capabilities, but are not prerequisites for the browsing catch-up:

- Family-to-family links and per-person sharing controls.
- Person merge and deletion, including impact previews and permissions.
- Naming/managing family places.
- Full-family import/export and administrative diagnostics.

Keep them as separate decisions. Family membership and invite-code management already exist in iOS and should not be confused with family-to-family sharing. If offering a browser fallback for a web-only setting, account for universal links: opening `/settings` normally can return to the app.

Book publishing, public sharing, print/PDF output, annual interviews, video, and other planned features should be evaluated against actual web implementation when their turn comes.

## Validation and completion

For implementation PRs:

- Add focused DTO/behavior tests for changed contracts, absent/null fields, age discovery, cancellation, deep links, and failed preference saves.
- Reuse existing tests for permissions, photo attachments, dates, books, and navigation where affected.
- Build and run the relevant iOS tests with Xcode; manually check the changed screens on a small iPhone and iPad.
- Check offline, slow-network, view-only, empty-data, and multi-person cases relevant to each phase.
- Verify the target backend deployment supports new contracts or retain a tested fallback.
- Mark each completed phase with its PR and note any intentionally deferred acceptance criteria.

Documentation-only changes do not require application tests. This plan does not claim that runtime parity has been verified.
