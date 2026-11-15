# Reliable competition results, saved locally

Status: proposed. This document changes no runtime behavior.

## Problem and outcome

During competition entry, Save can stall long enough that the user closes the
editor with Cancel and opens another routine. A late completion then appears to
close the new editor. Whether the first result actually saved is unclear.

Save must mean **durably saved on this phone**. It must update local screens and
close the matching editor without waiting for connectivity, an RPC, or a refresh.
Synchronization with the family website happens independently. A failed sync
must never silently discard the result or dismiss an editor.

## Current implementation and evidence

Reviewed iOS main at `72a0a71e0eb71195b6770d75e979128d01edb4fd` and
Family-Portal backend main at `954d401f33b6de5aaabd75e1686877d3d64df074`.

- `Services/ActivityService.swift` explicitly keeps activity writes online-only,
  outside SwiftData and `SyncQueue`. Reads use cached server response snapshots.
- `Views/Activities/PerformanceEditorView.swift` starts an unstructured save
  task, awaits `saveAppearance`, awaits `onSaved`, then calls `dismiss()`. Cancel
  dismisses immediately and does not invalidate that completion. Delete follows
  the same request/refresh/dismiss sequence.
- `CompetitionView` supplies `onSaved: { await state.reload() }`.
  `ActivityScreenState.reload()` awaits a live read. Thus even a successful write
  can leave the editor waiting for another network request. The save response is
  discarded instead of updating the displayed performance.
- `ActivitySnapshotCache` stores individual read responses. It is not a local
  activity database or a durable write outbox; writes do not update it.
- `SyncQueue` already serializes execution and protects operations in flight,
  but has no activity operations. It discards operations after a retry limit.
  `SyncQueueStore.save()` logs persistence failures rather than throwing them.
  Neither behavior meets the durability promise required here unchanged.
- Backend `backend/activity_results.go` implements `SaveAppearance` as a
  transaction replacing the performance, results, and photo associations. An
  `id == 0` request creates a new appearance. The request has no mutation key or
  expected revision; blindly replaying it could duplicate a create or overwrite
  newer website edits. Cross-record validation remains server-owned.

These paths explain network-dependent stalls and a possible stale completion.
They do not prove which request stalled at the competition or reproduce the
reported dismissal; add a controlled regression case before claiming that bug
is fixed.

## Scope

Deliver the complete result-entry loop for existing, downloaded competitions:
open routines, view results, create a performance with results, edit its full
result sheet, and delete it, all without a connection. Preserve the editor's
date, notes, matchup, attribution, and existing media associations.

Opening a competition online should download its event detail, season entries,
rosters, vocabulary, and permissions as one coherent local preparation workflow.
Show when preparation is incomplete; never treat missing downloaded data as an
empty result set. Previously downloaded competitions remain available after an
app restart. Offer an explicit download/retry action for an upcoming competition.

Creating activity/season/routine/event structure offline and uploading new media
offline are later work. Existing downloaded media references must survive result
edits unchanged. Clearly identify unavailable online-only actions without
blocking text result entry. Do not claim the entire Activities feature is offline
until these remaining paths are implemented.

## 1. Isolate editor lifetime and remove refresh from completion

- Give each presentation a unique session identity, including repeat openings of
  the same routine. Completion may dismiss only that matching presentation.
- Retain task ownership; closing an editor invalidates its UI callbacks. Task
  cancellation alone is insufficient: the server may already have committed.
- As an independently shippable mitigation, apply the successful save response
  locally, close the matching sheet, and refresh separately. Audit every caller
  of `PerformanceEditorView`, plus activity delete and structure editors, for
  the same awaited-refresh/dismiss pattern.
- In the final local-save flow, Cancel discards only an uncommitted editor draft.
  Once the short local commit begins, prevent duplicate Save and Cancel until
  it succeeds or fails. Never hold this lock during network work. A committed
  result is changed or deleted through a subsequent local edit, not Cancel.
- A local persistence failure keeps the draft open with a useful error. Do not
  display success or clear the draft until the durable transaction succeeds.

## 2. Introduce a local activity store with a transactional outbox

Use SwiftData for the activity records and their outbox in the same transaction.
Add schema and migration coverage through `DataStore.makeSchema()`. Keep existing
snapshot DTOs as transport inputs, not a second writable source of truth.

Store account/family scope, activity/season/event/entry data needed for entry,
rosters and vocabulary, and a local performance aggregate containing its entire
result sheet and existing photo IDs. Give each performance a stable local UUID
and optional server ID; do not use event + entry as identity because multiple
performances may be legitimate. Keep local result-row identities stable as well.

Each outbox mutation records its UUID, target local UUID, immutable payload,
base server revision, local generation, dependency, status, and retry metadata.
The save transaction writes the aggregate and pending mutation together. Deletes
write a tombstone and mutation together. Commit failures roll back both.

Extend the existing sync coordinator to drain this durable outbox rather than
writing the same activity operation separately to `SyncQueue.json`. Reuse its
single-run scheduling and status presentation where useful. Do not introduce a
second independent network loop racing the existing coordinator.

Local readers must observe changes immediately in competition cards, season
summaries, routine history, and result entry points. For server-derived Home,
person-season, and History summaries, project the local changes by stable ID or
explicitly indicate pending updates; never show a stale snapshot as if it disproves
a locally saved result. Fresh reads merge into the store before rendering.

## 3. Add a safe backend mutation contract before enabling offline replay

Implement companion changes in `Family-Portal`; define DTOs and fixtures shared
with the iOS tests. Preserve existing online clients during rollout.

- Add a durable client mutation UUID to saves and deletes. Scope deduplication
  to the authenticated account/family, verify authorization, and bind each key
  to a payload fingerprint. A reused key with a different payload is an error.
- Persist the mutation receipt and domain mutation in the same transaction.
  A retry after a lost response returns the original acknowledgement and server
  identity without creating another performance or reapplying an older write.
  Retain receipts long enough for indefinitely pending client retries; do not
  silently expire them without a reconciliation protocol.
- Return an authoritative aggregate and monotonically increasing revision.
  Require an expected revision for offline edits/deletes. Check it atomically
  with the write, not with a separate read-before-write request.
- Every backend path that changes an appearance, results, matchup, or media
  associations must advance the revision, including website writes and separate
  result setters. Otherwise whole-performance replacement remains unsafe.
- Distinguish revision conflict, already-deleted target, permission loss, invalid
  roster/media references, authentication failure, and transient network/server
  failure. Provide enough current state to reconcile without losing local input.
- Define a capability/version gate. Older servers can keep the current online
  behavior with honest messaging; never send queued writes through an unsafe
  fallback or discard pending data on capability loss.

Whole-sheet replacement remains reasonable when guarded by revision checks.
Do not attempt a silent field merge in the first implementation. On conflict,
retain both local and server versions and let the user review/reapply local work
against the current revision or explicitly choose the server version.

## 4. Reconcile, retry, and recover without losing work

- Trigger sync after local commits, on foreground/reconnect, and manual retry;
  background execution is best effort under iOS scheduling. Never promise sync
  while the app is force-quit. Pending work survives and resumes on next launch.
- Serialize mutations per performance. Coalesce only mutations not yet sent.
  Never change a payload under a mutation UUID that may have reached the server.
- An edit during an in-flight create becomes a subsequent mutation. Apply the
  returned server ID/revision while preserving the newer local generation, then
  send the subsequent edit against that revision. A late acknowledgement must
  not overwrite newer local data or clear its pending status.
- A create deleted before it was ever sent can be removed locally. If its request
  might have reached the server, recover the create acknowledgement with the same
  mutation UUID before issuing the delete. Do not leave an orphan on the website.
- Pulls preserve dirty aggregates and tombstones. An older snapshot cannot
  resurrect a deleted performance, duplicate an acknowledged create, or replace
  pending fields. Track request generations/revisions for overlapping refreshes.
- Retry transient failures with bounded backoff and jitter; retain work after
  any retry budget is exhausted. Pause authentication failures for sign-in.
  Preserve conflicts and terminal validation failures as actionable records.
- Use unobtrusive per-performance states: Pending sync, Syncing, Couldn't sync,
  and Needs review. Provide retry and review from the result and a shared sync
  status view. Failure must not reopen or close an unrelated editor.
- Partition data and outbox by account and family; never replay one account's
  changes using another account's session. Before logout/account removal erases
  unsynced work, offer an explicit keep/recover or discard decision. Family access
  loss preserves recoverable work without repeatedly attempting unauthorized writes.
- Migrate existing snapshots as clean baseline data only where dependencies are
  sufficient. Keep existing queues readable. Preserve/quarantine unreadable
  activity storage for recovery instead of interpreting corruption as no work.

## Delivery sequence

1. Editor session regression test and immediate response-driven dismissal fix.
2. Backend idempotency, revisions, conflict responses, and capability gate.
3. Local schema/outbox, persistence failure handling, preparation downloads,
   migrations, and account-scoped recovery.
4. Queue execution and reconciliation, then switch result entry and readers to
   the local store. Enable only with the safe backend contract available.
5. Pending/error/conflict UI, device acceptance testing, and updated architecture
   documentation in `claude.md`. Track structure/media offline work separately.

Keep these as reviewable implementation PRs. The first mitigation is useful on
its own; the feature is complete only when the offline acceptance cases pass.

## Verification and acceptance criteria

Add focused tests beside `ActivityWriteTests`, `ActivitySnapshotCacheTests`,
`SyncServiceQueueTests`, and backend `activity_results_test.go`, introducing
dedicated local-store and editor-session tests where necessary.

| Scenario | Required outcome |
| --- | --- |
| Prepared competition; airplane mode; add/edit/remove results | Immediate local update, matching editor closes, pending status visible |
| Relaunch while still offline | Competition, results, tombstones, and pending work restored |
| Kill after local commit, before send | Exactly the saved work resumes; no lost outbox entry |
| Server commits, response is lost, app restarts | Same mutation retried; exactly one server performance |
| Save A, close A, open B, release delayed A response/refresh | B stays open and its fields are untouched |
| Edit a performance while its earlier save is in flight | Later edit survives acknowledgement and eventually syncs |
| Repeated Save taps and overlapping reconnect/foreground triggers | One local commit per accepted save and no duplicate execution |
| Stale pull races local edit/delete or create acknowledgement | No rollback, resurrection, or duplicate |
| Website changes results/media while phone is offline | Revision conflict; both versions retained for review |
| Roster changes, permission loss, or parent deleted | Local work preserved with actionable failure |
| Storage write fails or schema/queue upgrade encounters old data | No false success or silent data loss; migration/recovery tested |
| Offline create then delete, before and during transmission | No orphan on server and no resurrected local card |
| Account/family switch with pending work | No cross-account display or replay; explicit recovery/discard policy |
| No downloaded competition or incomplete preparation | Clear unavailable/incomplete state; no fabricated empty sheet |

On a physical device, enter results for several routines under airplane mode and
under a throttled connection with delayed/dropped responses. Include rapid editor
switching, force quit/relaunch, then reconnect and compare the website. Target
Save-to-dismiss within 300 ms for a typical sheet on the test device; instrument
local commit time separately from sync latency and record results. UI tests must
also prove no network dependency rather than relying solely on a timing threshold.

Log mutation IDs, local generations, outcomes, and durations without award text or
other family content. Success means entry never waits for a network response,
pending changes survive restart and retries, and delayed completions cannot
interfere with the next routine.
