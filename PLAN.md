# Plan: Fix the perpetual sync loop (SyncEngine / SyncRealtime)

_Locked via grill — by Claude + Udorm_

> Note: the previous contents of this file (Plan tab v2 redesign, shipped in PR #21) are preserved
> in git history — recover with `git show HEAD:PLAN.md`.

## Goal

QuaraMoney's cloud sync runs in a permanent self-sustaining loop: with the app foregrounded and
completely idle, `syncNow` fires roughly every 1.5–2 s forever. Each cycle pulls one budget, sees
`parentLocalWins=true`, pushes it back to Supabase, and that push echoes over Realtime to the same
device, which schedules another sync. The echo also **cancels the sync that is still running**,
so syncs routinely abort part-way — in the worst observed cycle, six pulls, one push and the
profile step all failed with `CancellationError`. Because the failure list is non-empty,
`lastSyncDate` never advances and `hasCompletedInitialSync` never latches, so a red
`profile: The operation couldn't be completed. (Swift.CancellationError error 1.)` is stuck on the
Account screen. This is a data-integrity problem, not just wasted battery: a sync cancelled early
can push nothing, so genuine local edits may never reach the cloud.

Goal: the device must reach a quiet steady state — an idle app performs **zero** syncs — while still
reacting within ~1.5 s to genuine changes from other devices, and never aborting an in-flight sync.

## Evidence (already established — do not re-litigate)

- Live DB confirms the loop: budget `405eda91-9dc4-42a9-be13-cbec9d537263` `updated_at` moved
  `05:22:57` → `06:16:07` across two queries while the app sat idle.
- That budget's *data* is valid and benign: `period_type_raw=monthly`, `is_recurring=true`,
  `amount_type={"type":"fixed","value":1700}`, `target_kind=total`, `week_start_day=null`.
  Every `PlanDataMaintenance` normalization branch correctly skips it.
- Cloud budget↔category state is consistent (every `target_kind=categories` budget has ≥1
  `budget_categories` row), so the `.emptyRepaired` repair branch is **not** the driver.
- `profiles` is not written per-sync (oldest row 4+ days old) and is not in the watched table list.
- `[SyncRealtime] subscribed; watching 16 tables` appears exactly once — there is **no**
  resubscribe/reconnect storm.
- Some cycles complete with **no** `CancellationError` at all, `finishBudgetPush` runs, and the very
  next pull is *still* `parentLocalWins=true`. So cancellation alone does not explain the latch;
  there is a second, independent re-dirty mechanism (defect 3).

## Defects to fix

| # | Defect | Location |
|---|---|---|
| 1 | Realtime debounce `cancel()` kills the **in-flight** `syncNow` | `SyncRealtime.scheduleSync()` |
| 2 | `runStep` swallows `CancellationError` and keeps going, marking every later step "failed" | `SyncEngine.syncNow` |
| 3 | An unguarded main-context save after each sync re-stamps `needsSync`/`updatedAt` | `SyncMutationTracker.stampPendingChanges` + a `.dataDidUpdate` observer |
| 4 | No echo suppression — the device resyncs on its own writes | `SyncRealtime` |
| 5 | Push never advances the pull cursor, so `didApplyRemoteChanges` is always true on the echo | `SyncEngine.fetchChanged` / `writeBackServerTimestamps` |
| 6 | A realtime event arriving mid-sync is dropped (`already syncing`) with no re-arm | `SyncRealtime` / `SyncEngine.syncNow` |

Defects 1–3 are what actually stop the loop. 4–6 are correctness/efficiency hardening that prevent
the next variant of this bug.

## Approach

### Step 1 — A single-flight sync coordinator in `SyncEngine` (defects 1 and 6)

Today `syncNow` executes *inside* `SyncRealtime`'s cancellable debounce task, so the next
`debounceTask?.cancel()` tears down the running sync. Fixing this only inside `SyncRealtime` is not
enough: **every** trigger (local-save debounce, foreground, pull-to-refresh, sign-in) hits
`syncNow`'s `guard !isSyncing` and is silently dropped. Ownership therefore belongs in the engine.

- Add a coordinator to `SyncEngine` that owns single-flight execution: one `syncRunTask` plus one
  **pending-run latch**. All triggers go through `enqueueSync(reason:)` / `requestSyncAndWait(reason:)`
  (defined below); none of them call `syncNow` directly and none may cancel a run in progress.
- Cancellability is split: callers may cancel a *pending wait*, never work in progress. The executor
  is a **stored unstructured `Task { @MainActor in … }`**, independent of any debounce task so a
  debounce `cancel()` cannot reach it. **Do not use `Task.detached`** — `SyncEngine` and
  `ModelContext` are main-actor-bound, and detaching would carry the context across an actor
  boundary and break isolation.
- Re-arm (defect 6): a request arriving while a run is in flight sets the latch instead of being
  dropped; when the run finishes with the latch set, exactly one more pass is scheduled.
- **The latch has two parts**, because Realtime identities alone cannot represent every trigger:
  ```
  pendingRun = (forceRun: Bool, eventIdentities: Set<EventIdentity>)
  ```
  `forceRun` covers identity-less triggers — local edits, `PlanDataMaintenance` follow-ups,
  foreground, manual refresh, sign-in. `eventIdentities` covers Realtime events pending
  reclassification (Step 4). A follow-up pass runs if `forceRun` is set **or** any identity is still
  unmatched. Without `forceRun`, a local edit arriving mid-run would be silently lost.

- **Two distinct entry points — never one awaitable API.** A single awaitable `requestSync` would
  deadlock: `PlanDataMaintenance` (Step 1b) requesting *and awaiting* its own follow-up from inside
  the executor would block the very run that must finish first, and `SyncRealtime` awaiting tickets
  would stall event consumption. So:
  - `enqueueSync(reason:)` — **nonblocking**, fire-and-forget. Used by Realtime, the local-save
    debounce, and maintenance follow-ups. **The executor must only ever use this**; nothing inside a
    run may await a follow-up.
  - `requestSyncAndWait(reason:) async -> SyncOutcome` — awaitable, for callers that need the work
    to have actually happened: pull-to-refresh, sign-in settlement, conflict resolution, sign-out.
- **Every ticket must terminate.** A ticket resolves `.success` / `.failed(Error)` / `.cancelled`,
  and **all** associated continuations are resumed on **every** terminal path — normal completion,
  real failure, abort, and generation clear. An abandoned continuation hangs a refresh or sign-in
  task forever; ticket bookkeeping is `defer`-based so no exit path can skip it.
- **Sign-out is a barrier, not a request — and it must absorb the debounce.** Draining the
  coordinator is not sufficient: `handleLocalSave` holds edits in a **2-second debounce** that has
  not yet reached the coordinator, so an edit made moments before sign-out is invisible to a drain.
  `flushBeforeSignOut` must:
  1. cancel/absorb the pending local-save debounce so its edits are claimed immediately;
  2. loop — while `hasPendingLocalChanges()` is true, `requestSyncAndWait` and re-check;
  3. proceed to wipe **only** when clean; on a terminal failure, **refuse to wipe** and surface the
     error rather than destroying un-pushed edits.
  Bound the loop so a permanently failing push cannot spin; a bounded failure blocks the wipe. This
  is the single most safety-critical seam in the change and gets a dedicated test.

- **Refusing the wipe is not sufficient — a failed flush must abort the sign-out itself.**
  `SupabaseAuthManager.signOut()` currently calls `try await client.auth.signOut()` **regardless** of
  whether the flush succeeded; only the *wipe* is gated on `safeToWipe`. So a failed flush leaves the
  user signed out with dirty local rows, and the next sign-in with a different account hits
  `reconcileAccountIfNeeded`, which wipes the store — destroying un-pushed edits that never reached
  the cloud. Required change: **a failed flush aborts authentication sign-out entirely**, leaving the
  user signed in with their data intact and a surfaced, retryable error.
- **Close the sign-out TOCTOU — with an enforceable mechanism, not a notional "lock".** `safeToWipe`
  is computed *before* the `auth.signOut()` await, so a save landing during that suspension is wiped
  without ever syncing. Note that a state flag alone **cannot** block writes: the repo has dozens of
  direct `ModelContext.save()` call sites (several asynchronous), and a `willSave` observer can
  observe but **not veto** a save. So instead of pretending to block writes, make the **wipe** the
  guarded operation:
  1. **Mutation revision counter** — `SyncMutationTracker.stampPendingChanges` (already on
     `willSave`) increments a monotonic `localMutationRevision` whenever it stamps anything.
  2. **Post-auth recheck** — capture the revision at the clean check; after `auth.signOut()` returns,
     re-read it *and* re-run `hasPendingLocalChanges()`. If either shows movement, **do not wipe**.
  3. **Account-switch backstop** — `reconcileAccountIfNeeded` must refuse to wipe whenever retained
     dirty rows belong to the *previous* account, surfacing/retaining them instead. This is the
     durable guarantee: even if every earlier gate is bypassed, un-pushed edits are never destroyed
     by an account switch.

- **Lifecycle generation token — must also stop stale *side effects*, not just stale bookkeeping.**
  `SyncRealtime.stop()` (background / sign-out / account switch) increments a generation counter and
  clears context + pending state. But a token alone does not prevent an old run from continuing to
  save models, advance cursors, or issue new requests mid-flight. Therefore:
  - `reconcileAccountIfNeeded` / any wipe must **cancel and `await`** the old executor before
    touching the store — not merely mark it stale.
  - The run captures `uid` + generation at entry and **re-validates both after every network
    suspension**, before applying results or advancing a cursor. A mismatch aborts immediately
    (via the Step 2 abort path) rather than writing another account's data into the store.

### Step 1b — Maintenance must not strand dirty rows (defect 8)

`PlanDataMaintenance.run` executes at the sync tail, **after** every push step, and deliberately
creates dirty rows (`budget.needsSync = true`). The completion broadcast is tagged `object: self`
precisely so auto-sync ignores it — so those rows are stranded until some unrelated trigger fires.

- Either run sync-producing maintenance **before** the push phase, or have it report `changed` and
  make the engine explicitly `enqueueSync(reason: .maintenance)` a follow-up pass.
- Preference: report-and-request, so maintenance keeps running against freshly pulled data.
- The follow-up **must** use the nonblocking `enqueueSync(reason: .maintenance)` — never the
  awaitable form. Maintenance runs inside the executor, and awaiting its own follow-up there would
  deadlock the run that must finish first (see Step 1). It routes through the Step 1 coordinator's
  latch (`forceRun`) so it cannot itself become a loop.

### Step 2 — Treat cancellation as an abort, not a step failure (defect 2)

In `syncNow`:

- Check `Task.isCancelled` before each step and bail out of the remaining pipeline immediately.
- In `runStep`, catch `CancellationError` **and** the `URLError.cancelled` equivalent that
  URLSession surfaces instead, distinctly from a real failure: mark the sync **aborted** and stop,
  rather than appending to `failures`.
- **Cancellation is also swallowed *outside* `runStep` — fix those paths too.** Verified:
  `downloadAndStoreImage` wraps its work in a blanket `catch` that treats `CancellationError` as a
  download failure and **re-enqueues the image for retry**, and `drainImageDownloads` is called
  outside `runStep` entirely, so a cancelled run proceeds to successful finalization. Fix by:
  - rethrowing cancellation from broad `catch` blocks instead of classifying it as a failure;
  - making image draining throwing / cancellation-aware and routing it through `runStep`;
  - re-checking cancellation immediately **before** any success metadata is committed
    (`lastSyncDate`, `hasCompletedInitialSync`, deletion-queue removal, marker commits), so a
    cancelled run can never latch "succeeded".
- An aborted sync must **not** set `lastError` to a wall of cancellation noise (that is the red text
  on the Account screen), must not set `lastSyncDate`, and must not latch `hasCompletedInitialSync`.
- **Correction — an abort does *not* leave state untouched.** Every pull that completed before the
  cancellation already saved locally and advanced its own cursor inside `applyLocal`. So on abort we
  must still broadcast committed remote changes and invalidate affected wallet balance caches.
  Skipping the broadcast would strand already-committed rows with no view-model refresh — data on
  screen would silently disagree with the store.
- **Do not blindly re-arm on abort — that is how this fix grows its own loop.** An unconditional
  retry-after-cancel spins forever if URLSession keeps returning cancellation without any generation
  change. Retry policy:
  - **Stale / lifecycle generation** (background, sign-out, account switch): **no retry.** The run
    is obsolete by definition; the next legitimate trigger starts a fresh one.
  - **Unexpected same-generation cancellation**: retry with **bounded exponential backoff** and a
    hard attempt cap, after which the sync stays idle until a genuine trigger arrives.
- Decision: an aborted sync is *silent* in the UI. A cancellation is a normal lifecycle event
  (backgrounding, sign-out), not something to alarm the user about.

### Step 3 — Find and close the unguarded re-dirty (defect 3) — **root latch**

Ordering proves the engine is not the direct culprit: `syncNow finished` prints from the `defer`,
which runs *after* the `PlanDataMaintenance`/reconciler tail — yet `Core Data willSave` prints
*after* that line. So the unguarded save comes from an **observer reacting to the `.dataDidUpdate`
broadcast** the sync posts, which then saves the main context with `isApplyingSyncChanges == false`,
causing `stampPendingChanges()` to re-stamp every changed model with `updatedAt = Date()` and
`needsSync = true`.

Because `parentLocalWins == true` makes the pull *skip* applying the remote row, the local
`updatedAt` can only ever be corrected by the push write-back — so a single unguarded re-stamp
permanently pins the row as "locally newer", which is exactly the observed latch.

**The culprit is confirmed — it is `BudgetNotificationService`.** No further diagnosis needed:

```swift
NotificationCenter.default.publisher(for: .dataDidUpdate)      // NOT filtered by object
    .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
    .sink { [weak self] _ in self?.evaluateStore() }
...
func evaluateStore() {
    checkBudgetsAndTriggerAlerts(budgets: budgets, spending: spending)
    if modelContext.hasChanges { try modelContext.save() }     // UNGUARDED
}
```

The closed loop, fully accounted for:

1. The sync posts `.dataDidUpdate` with `object: self`. The auto-sync observer filters engine
   broadcasts; **this Combine publisher does not**, so the engine's own completion wakes it.
2. The 400 ms debounce fires *after* `syncNow finished` — matching the log ordering exactly
   (`syncNow finished` → `Core Data willSave`), and 400 ms + 1.5 s ≈ the observed ~2 s cycle.
3. `checkBudgetsAndTriggerAlerts` assigns `budget.lastAlertThreshold = 0` whenever
   `lastAlertPeriodKey != periodKey` — and a **same-value assignment still marks the SwiftData
   object dirty**, so `hasChanges` is true even when nothing semantically changed.
4. The unguarded `save()` triggers `stampPendingChanges()`, stamping `updatedAt = Date()` and
   `needsSync = true` on every changed model.
5. The budget is now locally-newer → next pull is `parentLocalWins=true` → push → echo → repeat.

Fixes, in order:

1. **Eliminate same-value mutations.** In `checkBudgetsAndTriggerAlerts`, only assign
   `lastAlertThreshold`/`lastAlertPeriodKey` when the new value actually differs. This is the real
   fix: an evaluation that changes nothing must leave `hasChanges == false` and never save.
2. **Do not wrap `evaluateStore` in `withSyncWriteGuard`.** These are genuine local writes when an
   alert really fires and must sync normally; suppressing the stamp would lose real alert state.
   The guard is the wrong tool here — same-value elimination is the correct one.
3. **Harden `PlanDataMaintenance.run`** — it is called unguarded at the sync tail while the
   `SavingsGoalReconciler` call beside it *is* guarded. Wrap the derived/normalization writes for
   symmetry, and pair with Step 1b so its intentional dirty rows are not stranded.
4. **Add a regression guard with a source tag.** Logging model type + id alone identifies the
   *victim*, not the *writer*. Instrument DEBUG saves with a caller/source tag (e.g. a lightweight
   `#function`/`#file` breadcrumb set by the engine and by known writers) so the next occurrence
   names the writer directly.

### Step 4 — Suppress the device's own Realtime echoes (defect 4)

Supabase `postgres_changes` carries no originating-client identity, and RLS means every delivered
row already has our `user_id` — so origin must be inferred at the app level. Use **fingerprints,
not a timer**:

- **Registration point (corrected).** `writeBackServerTimestamps` is **test-only** — its sole
  callers are in `QuaraMoneyTests/SyncEngineHardeningTests.swift`; production pushes settle in
  `finishPush` (which inlines the timestamp write) and `finishBudgetPush`. Register fingerprints in
  **`finishPush`, `finishBudgetPush`, and the server tombstone-update completion in
  `pushDeletions`** — registering in `writeBackServerTimestamps` would be dead code.
- **`pushDeletions` needs a schema change to its request before it can fingerprint at all.**
  Verified: it currently issues `.update(patch).eq("id", …).execute()` with no `.select()`, so no
  representation comes back and there is no trigger-assigned `updated_at` to key on. It must request
  and decode `id, updated_at` from each tombstone update, register the fingerprint, and only then
  remove the deletion-queue entry — in that order, so a failure or cancellation cannot drop the
  entry without having recorded the write.
- `SyncEngine` keeps `recentlyPushed` keyed by `(table, id, updated_at)`, built from the
  server-returned rows (the values the DB trigger stamped — identical to what Realtime delivers for
  that write). Entries expire on a TTL (~60 s) and are cleared on sign-out/account switch and on
  generation change.
- **Decoding is settled, not an open question.** The pinned dependency is **supabase-swift 2.48.0**
  (verified in `Package.resolved`), where `AnyAction` itself exposes **no** `record` — only its
  associated `InsertAction` / `UpdateAction` values do. So: pattern-match the associated action and
  decode its `record` with the **Supabase decoder** (not a hand-rolled `JSONDecoder`).
- **Compare timestamps canonically, never as strings.** Postgres and PostgREST can render the same
  instant with differing fractional-second precision, so a string-keyed comparison would miss every
  match and silently defeat suppression entirely. Key on a normalized `Date` value.
- `SyncRealtime` then asks `SyncEngine.shared.isOwnEcho(table:id:updatedAt:)`. A match does **not**
  schedule a resync; anything else — including `DeleteAction`, which carries no new record —
  schedules normally.
- **Do not consume a fingerprint on first match.** Realtime can duplicate or replay a delivery; a
  consumed fingerprint would make the duplicate look like a genuine remote event and restart the
  loop. Retain matched fingerprints until TTL expiry (idempotent matching).
- **Close the pre-response race.** Realtime may deliver the change event *before* the HTTP upsert
  response returns, so the fingerprint may not be registered yet when the event arrives — a naive
  check would classify our own write as remote and schedule a false resync. Therefore: events
  arriving **while a sync run is in flight** are buffered as identities rather than acted on
  immediately, and are **reclassified against the fingerprints registered by that run when it
  finishes**. Only identities still unmatched schedule a follow-up pass (via the Step 1 latch).
- This is why the pending-run latch carries identities, not a boolean: a bare flag cannot tell a
  pre-response own-echo apart from a genuine concurrent remote update, and would either loop
  forever or drop real changes.
- Fallback: events we cannot fingerprint (notably `budget_categories`, which has no `updated_at`,
  and any payload we fail to decode) schedule a resync as they do today. Correctness is preserved;
  we only lose suppression on those, which are rare.

Rejected alternative: a blind "ignore Realtime for N seconds after a push" window. It silently
drops other devices' changes that land inside the window, degrading the very feature this
subscription exists to provide.

### Step 5 — Make `didApplyRemoteChanges` mean "we actually changed something" (defect 5)

`fetchChanged` sets the flag from `!all.isEmpty` — i.e. "we fetched rows", even when those rows are
byte-identical to what we already hold (our own echo, re-fetched because the push never advanced the
cursor). Move the signal into the apply step.

**The predicate must not be `local.updatedAt != row.updated_at || local.needsSync`.** `needsSync ==
true` describes a *local-newer* row that LWW deliberately **skips** — that proves a local edit, not a
remote mutation, so that predicate would keep the flag true on exactly the rows we are trying to
quiet.

**Two outcomes, not one.** "Nothing visible changed" and "nothing needs persisting" are different
questions, and collapsing them would introduce a fresh bug: a byte-identical remote row may still
legitimately require a metadata correction (clearing `needsSync`, adopting the server `updatedAt`,
assigning `syncUserID` ownership). Refusing to save those would strand rows as permanently dirty —
re-creating the very loop we are fixing. So each apply closure returns both:

- `didPersistLocalState` — metadata or data was written; the span **must** be saved.
- `didChangeVisibleData` — LWW accepted the remote row *and* a user-visible field actually changed.

`didApplyRemoteChanges` (which gates the `.dataDidUpdate` broadcast, `PlanDataMaintenance`, and the
reconciler) is driven **only** by `didChangeVisibleData`. Saving is driven by `didPersistLocalState`.

Effect: a stray echo becomes a silent no-op instead of re-running `PlanDataMaintenance` +
`SavingsGoalReconciler` and re-broadcasting `.dataDidUpdate` — which is what feeds defect 3.

**Explicitly rejected:** advancing the pull cursor on push. Pull runs before push, so a concurrent
row written by another device between our pull and our push gets a server timestamp below ours;
bumping the cursor past it would skip that row permanently. That is silent cross-device data loss.
The current "don't advance on push" behaviour is deliberate and must stay.

### Step 6 — Verify convergence and self-heal the stuck row

- The stuck budget's *data* is valid; only its sync metadata churns. Expect the first clean sync
  after the fix to push it once, write back the server timestamp, clear `needsSync`, and settle.
- Verify by observation, not by a destructive migration: confirm the cloud `updated_at` for
  `405eda91-…` stops advancing while the app sits idle.
- If it does **not** settle, the remaining local latch is a genuine bug still unfixed — investigate
  rather than papering over it with a one-shot reset.

### Step 7 — Automated regression coverage (required, not optional)

The manual 60-second checks below prove the symptom is gone on one device; they cannot pin the
behaviour down. This is the most safety-critical code in the app, so the fix ships with
deterministic tests. Follow the existing pattern (`TestModelContainer.create()`, in-memory
container, `SyncEngineHardeningTests.swift`). Seams to introduce:

- **Injected sync runner** — assert single-flight: concurrent `enqueueSync` calls produce exactly
  one run plus one latched follow-up, never a dropped request and never two overlapping runs.
  Include an identity-less trigger (local edit) arriving mid-run and assert `forceRun` re-arms it.
- **Awaitable tickets** — `requestSyncAndWait` resolves only when a run satisfying it completes, not
  on enqueue; `enqueueSync` never blocks its caller.
- **Mutation-revision backstop** — a save landing between the clean check and the wipe bumps
  `localMutationRevision`, and the post-auth recheck must abort the wipe; and an account switch with
  retained dirty rows belonging to the previous account must refuse to wipe.
- **Sign-out barrier (highest-value test)** — a local edit made while a sync is in flight must be
  pushed before `flushBeforeSignOut` returns; the wipe must never observe
  `hasPendingLocalChanges() == true`. Include the debounce case: an edit made **inside the 2-second
  local-save debounce window**, never yet seen by the coordinator, must still be flushed. A terminal
  push failure must **block both the wipe and the auth sign-out** — assert the user remains signed
  in with data intact. Also assert the TOCTOU is closed: a save attempted between the final clean
  check and the wipe cannot land. Guards against destroying un-pushed user data.
- **No deadlock** — maintenance requesting a follow-up from inside the executor uses the
  nonblocking `enqueueSync` and completes; assert the run finishes and the follow-up still happens.
- **Stale-run side effects** — a run cancelled by an account switch must not save models, advance
  cursors, or issue follow-up requests after the switch; uid/generation re-validation after a
  simulated suspension aborts it.
- **Cancellation outside `runStep`** — a cancelled image drain must not re-enqueue as a "failure"
  and must not allow `lastSyncDate` / `hasCompletedInitialSync` to latch.
  **Scope this correctly:** deletion-queue removals that already succeeded *before* a later
  cancellation are intentional durable partial progress and must **not** be rolled back — asserting
  otherwise would demand impossible transactionality across independent HTTP calls. Test only
  cancellation *during* the tombstone request, or *between* its response and the queue removal.
- **Ticket termination** — every terminal path (success, real failure, abort, generation clear)
  resumes all associated continuations; no caller hangs. Assert no leaked continuations.
- **Abort retry policy** — a stale/lifecycle-generation abort schedules **no** retry; a repeated
  same-generation cancellation backs off and stops at the cap instead of spinning.
- **Injected clock** — fingerprint TTL expiry and idempotent (non-consuming) matching, including a
  duplicated/replayed delivery of the same event.
- **Injected Realtime payloads** — own-echo suppression; an unfingerprintable payload still
  schedules; a genuine remote identity still schedules.
- **Controllable continuations** — the pre-response race: deliver the event *before* the upsert
  response resolves and assert it is buffered, reclassified, and suppressed.
- **Cancellation** — a run cancelled mid-pipeline records no `failures`, leaves `lastSyncDate` and
  `hasCompletedInitialSync` untouched, and still broadcasts already-committed pulls. Re-arming is
  **policy-dependent and must be split into two cases**: a lifecycle/stale-generation cancellation
  must **not** re-arm; a same-generation cancellation follows the bounded-backoff retry policy and
  stops at the cap.
- **Account switch** — a run from an older generation completing after `stop()` must not clear newer
  state or re-arm against the new account's context.
- **Two-outcome apply** — an LWW-skipped row and a byte-identical row both leave
  `didApplyRemoteChanges == false`; but a byte-identical row needing a metadata correction
  (`needsSync` clear / ownership assignment) **is still saved** and does not stay dirty.
- **`BudgetNotificationService`** — an `evaluateStore()` that crosses no threshold leaves
  `modelContext.hasChanges == false` and performs no save (the defect-3 regression test).

## Proof test (acceptance criteria)

1. **Idle quiet:** app foregrounded, untouched for 60 s → zero `[SyncRealtime] remote … received`
   entries attributable to our own writes, zero `syncNow called`, zero `CancellationError`.
2. **Cloud quiet:** `select updated_at from budgets where id='405eda91-…'` unchanged across two
   queries 60 s apart while idle.
3. **Local edit still syncs:** add a transaction → exactly **one** sync cycle → row present in cloud
   → returns to quiet. No echo-triggered second cycle.
4. **Remote change still lands:** change a row from another client/SQL → the device pulls it within
   ~2 s (proves suppression did not deafen us).
5. **Cancellation is clean:** background the app mid-sync → no `lastError` shown, no wall of
   per-step `CancellationError`, next foreground syncs normally.
6. Existing suite green: `xcodebuild test -scheme QuaraMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

## Key decisions & tradeoffs

1. **Fingerprint echo suppression over a timing window** — precise, and preserves multi-device
   immediacy. Costs a small TTL map and decoding the Realtime payload.
2. **Do not advance the pull cursor on push** — protects against cross-device data loss; accepted
   cost is one redundant (now silent) pull per push, mitigated by Step 5.
3. **Cancellation is silent in the UI** — it is a lifecycle event, not a user-facing error. Risk: a
   genuinely stuck sync becomes less visible; mitigated because `lastSyncDate` still fails to
   advance, which the UI can surface as staleness.
4. **Defect 3 is fixed by eliminating same-value mutations, not by guarding the writer.**
   `BudgetNotificationService`'s writes are legitimate when an alert really fires and must sync;
   wrapping them in `withSyncWriteGuard` would silently lose real alert state. The bug is that an
   evaluation which changes nothing still dirties the context.
5. **No data migration for the stuck row** — its data is correct; only metadata churns. A migration
   touching live user data is higher-risk than verifying convergence.
6. **The re-arm latch carries event identities, not a boolean** — a boolean cannot distinguish a
   pre-response own-echo from a genuine concurrent remote update, so it would either spin or drop
   real changes. Identity sets are still bounded (deduplicated, TTL-scoped).
7. **Single-flight ownership lives in `SyncEngine`, not `SyncRealtime`** — every trigger shares the
   `already syncing` drop, so fixing it in one caller would leave the others broken.
8. **Fingerprints are retained until TTL, not consumed on match** — Realtime can duplicate or replay
   a delivery, and a consumed fingerprint would reclassify the duplicate as a genuine remote event.

## Risks / open questions

- **Defect 3's culprit is now named and confirmed** (`BudgetNotificationService`), so this is no
  longer open. Residual risk: other `.dataDidUpdate` observers may contain the same same-value-write
  pattern. The DEBUG source-tagged save instrumentation (Step 3.4) exists to surface them; a quick
  audit of other `.dataDidUpdate` subscribers should accompany the fix.
- **Behaviour change in alerting.** Suppressing same-value writes means `lastAlertThreshold` /
  `lastAlertPeriodKey` are persisted only on real transitions. Verify this does not change when
  50/80/100% alerts fire or re-fire across a period boundary — covered by the Step 7 test.
- ~~**Realtime payload decoding**~~ — **resolved.** Pinned supabase-swift is 2.48.0
  (`Package.resolved`): `AnyAction` has no `record`; its associated `InsertAction`/`UpdateAction`
  do. Decode via the Supabase decoder and match timestamps canonically (not string-keyed). Payloads
  that fail to decode fall back to scheduling a resync.
- **A `budget_categories` echo cannot be fingerprinted** (no `updated_at`). Its delete+insert will
  still trigger one resync per genuine join rebuild. Acceptable; join rebuilds are rare and now
  converge.
- **Multi-device correctness must not regress.** Test 4 exists specifically to catch over-suppression.
- **`SyncMutationTracker.isApplyingSyncChanges` must never wrap an `await`** (existing project rule);
  every new guard added here must wrap a synchronous span only.
- **Ordering of Steps 4 and 5** — Step 5 alone leaves the redundant network round-trip; Step 4 alone
  leaves the churn path intact for un-fingerprintable events. Both are needed.

## Out of scope

- Redesigning the sync architecture, the LWW scheme, or the budget↔category join model.
- The cosmetic `nw_protocol_instance_set_output_handler` / `nw_path_necp_check_for_updates` OS log
  noise — unrelated to this bug.
- The one observed `[SyncRealtime] remote INSERT received` right after subscribe (a
  backlog/other-device artifact, not part of the loop).
- Offline queueing, conflict-resolution UX, and image upload/retry behaviour.
