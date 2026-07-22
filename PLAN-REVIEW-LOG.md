# Plan Review Log: Fix the perpetual sync loop (SyncEngine / SyncRealtime)

Act 1 (grill) complete — plan locked with the user. MAX_ROUNDS=5.

> The previous contents of this file (Plan tab v2 review log) are preserved in git history —
> recover with `git show HEAD:PLAN-REVIEW-LOG.md`.

Reviewer model: `gpt-5.6-sol` (pinned in `~/.codex/config.toml`, `model_reasoning_effort = "high"`),
codex-cli 0.144.4. Codex is read-only every round.

## Act 1 summary — what the grill settled

- **Symptom reframed twice.** Initially assumed a damped "echo" (one redundant resync per push).
  The live DB then showed zero writes for 44 min, suggesting no loop at all — until the user's full
  idle log proved a true perpetual loop, and a re-query showed budget `405eda91-…` `updated_at`
  advancing `05:22:57` → `06:16:07` while idle.
- **Root cause identified:** `SyncRealtime.scheduleSync()` runs `syncNow` *inside* the cancellable
  debounce task, so each echo's `debounceTask?.cancel()` kills the sync that is still running.
  `push budgets: CancellationError()` in the log proves `finishBudgetPush` never ran, leaving
  `needsSync` set — the latch.
- **Second, independent latch found** by re-reading the full log at the user's request: cycles that
  complete with *no* cancellation still show `parentLocalWins=true` on the next pull, and
  `Core Data willSave` prints after `syncNow finished` — an unguarded post-sync save re-stamping
  `needsSync`/`updatedAt` via `SyncMutationTracker`.
- **Ruled out with evidence:** budget `.emptyRepaired` branch (cloud join state verified clean),
  `PlanDataMaintenance` normalization branches (all skip this row), `profiles` per-sync writes,
  and a Realtime resubscribe storm (`subscribed` logged exactly once).
- **Scope:** user chose all six defects plus verification of the stuck row ("Do all").
- **Rejected during the grill:** advancing the pull cursor on push (silent cross-device data loss),
  and blind time-window echo suppression (drops other devices' changes).

## Round 1 — Codex

Material problems remain:

1. Re-arm is scoped only to `SyncRealtime`, while local-save and foreground triggers still hit `syncNow`’s “already syncing” guard and are dropped ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:507)).  
   Fix — Put single-flight ownership and one pending-run latch in `SyncEngine`, and route every trigger through it.

2. Echo fingerprints can arrive too late: Realtime may deliver the event before the HTTP upsert response registers its server timestamp, causing a false pending resync ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:117)).  
   Fix — Buffer identifiable events received during a sync and reclassify them against returned fingerprints when the run finishes.

3. The proposed registration path is wrong: production pushes use `finishPush`, while `writeBackServerTimestamps` is only called by tests ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1350)).  
   Fix — Register fingerprints in `finishPush`, `finishBudgetPush`, and server tombstone-update completion.

4. A single `pendingResync` boolean discards event identity, so it cannot distinguish a pre-response own echo from a genuine concurrent remote update.  
   Fix — Queue or coalesce fingerprintable event identities, then schedule one rerun if any remain unmatched.

5. “Aborted sync leaves state untouched” is false: each completed pull saves locally and advances its cursor immediately ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:2453)). Cancellation afterward can suppress the only view-model refresh for those changes.  
   Fix — On abort, still broadcast committed remote changes and invalidate affected caches, then re-arm a retry without reporting cancellation as failure.

6. `stop()` lacks a lifecycle generation boundary; a cancelled old run can finish after restart, clear newer task state, or re-arm against a new account/context ([SyncRealtime.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncRealtime.swift:88)).  
   Fix — Clear context and pending state on stop, increment a generation token, and ignore completion/events from older generations.

7. The suggested Step 5 predicate is incorrect: `local.needsSync == true` can describe a local-newer row that LWW deliberately skips, so it does not prove a remote mutation ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:132)).  
   Fix — Make each apply closure return `didMutate`, set the flag only after LWW accepts an actual field change, and avoid saving byte-identical rows.

8. Guarding tail maintenance does not ensure convergence: `PlanDataMaintenance.run` explicitly creates dirty rows after all push steps, while the engine-tagged completion notification is ignored by auto-sync ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:738)).  
   Fix — Run sync-producing maintenance before pushes or request a central follow-up run whenever maintenance reports `changed`.

9. Logging only model type and ID cannot “name” the observer; it identifies the victim, not the writer. `BudgetNotificationService` is already a concrete suspect because its `.dataDidUpdate` handler conditionally assigns and saves budgets ([BudgetNotificationService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/BudgetNotificationService.swift:24)).  
   Fix — Add a call stack/source tag to DEBUG save instrumentation and eliminate same-value mutations before saving.

10. Consuming a fingerprint on first match is fragile under duplicate/replayed Realtime delivery; the duplicate becomes a false remote event.  
    Fix — Retain matched fingerprints until TTL expiry or track an explicit expected-delivery count.

11. The proof section adds no automated regression coverage for the coordinator, cancellation, parsing, account switching, or the pre-response echo race ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:156)).  
    Fix — Add deterministic tests with injected sync runners, clocks, event payloads, and controllable continuations before relying on the manual 60-second checks.

VERDICT: REVISE
### Claude's response

**All 11 findings accepted.** Two were verified against the codebase before acceptance, and both
were correct — they materially changed the plan:

- **#3 (registration point) — verified true.** `grep` confirms `writeBackServerTimestamps`'s only
  callers are in `QuaraMoneyTests/SyncEngineHardeningTests.swift`. Production settles pushes in
  `finishPush` (inlining the timestamp write at SyncEngine.swift:1362) and `finishBudgetPush`.
  Registering fingerprints where the plan originally said would have been dead code. Plan now
  registers in `finishPush`, `finishBudgetPush`, and `pushDeletions` tombstone completion.
- **#9 (defect 3 culprit) — verified true, and upgraded from suspicion to confirmed root cause.**
  `BudgetNotificationService.configure` subscribes to `.dataDidUpdate` via a Combine publisher that,
  unlike the auto-sync observer, does **not** filter `object is SyncEngine` — so the engine's own
  completion broadcast wakes it. Its 400 ms debounce fires after `syncNow finished` (matching the
  log ordering, and 400 ms + 1.5 s ≈ the observed ~2 s cycle), `checkBudgetsAndTriggerAlerts`
  assigns `lastAlertThreshold = 0` even when unchanged (a same-value assignment still dirties the
  SwiftData object), and the unguarded `save()` triggers `stampPendingChanges()`. That is the latch.
  The plan's "diagnose first" step is replaced with the concrete fix.

Other notable changes:

- **#1 + #4 + #2/#10 (coordinator + echo race)** — single-flight ownership moved from `SyncRealtime`
  into `SyncEngine` so all triggers share it; the pending latch now carries **event identities**
  rather than a boolean; events arriving mid-run are buffered and reclassified against fingerprints
  registered by that run; fingerprints are retained until TTL rather than consumed on match.
- **#5** — corrected an outright false claim in the plan. An aborted sync does *not* leave state
  untouched: completed pulls have already saved and advanced their cursors, so abort must still
  broadcast committed changes and invalidate caches, or on-screen data silently diverges.
- **#7** — the proposed `didApplyRemoteChanges` predicate was wrong for the stated reason
  (`needsSync == true` marks a local-newer row that LWW *skips*). Replaced with apply closures
  returning `didMutate`, set only after LWW accepts a real field change.
- **#8** — accepted as a genuine latent bug: `PlanDataMaintenance` creates dirty rows after all push
  steps while the completion broadcast is `object: self` (ignored by auto-sync), stranding them.
  Added Step 1b (report-and-request a follow-up through the coordinator latch).
- **#6** — added a lifecycle generation token so a stale run cannot clear newer state or re-arm
  against a different account's context.
- **#11** — added Step 7 with concrete seams (injected runner, clock, payloads, controllable
  continuations) and named cases, including a defect-3 regression test asserting that a
  no-threshold-crossing `evaluateStore()` leaves `hasChanges == false`.

Nothing was rejected this round.

## Round 2 — Codex

The prior findings are substantially addressed, but six material implementation gaps remain:

1. The pending latch only carries Realtime identities; local edits, maintenance, foreground, and manual refresh requests have no identity and could still be lost.  
   Fix — Model pending state as `forceRun: Bool` plus `eventIdentities: Set<EventIdentity>`.

2. `requestSync` completion semantics are unspecified; pull-to-refresh, sign-in settlement, conflict resolution, and especially `flushBeforeSignOut` must await the run satisfying their request, not merely enqueue it.  
   Fix — Return an awaitable request ticket/result and make sign-out use a barrier that drains the coordinator and verifies no pending local changes.

3. A generation token prevents stale bookkeeping but not stale side effects: an old run can continue saving models, advancing cursors, or issuing requests after an account switch.  
   Fix — Cancel and await the old executor before account reconciliation/wipe, and validate captured user ID plus generation after every network suspension before applying results.

4. Cancellation can still be swallowed outside `runStep`: `downloadAndStoreImage` catches every error, including cancellation, and `drainImageDownloads` can let a cancelled run reach successful finalization ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:2541)).  
   Fix — Rethrow cancellation from broad catches, make image draining throwing/cancellation-aware, and check cancellation immediately before success metadata is committed.

5. Step 5 conflates visible changes with required metadata writes: a byte-identical remote row may still need `needsSync`, `updatedAt`, or ownership corrected and therefore must be saved.  
   Fix — Return separate `didPersistLocalState` and `didChangeVisibleData` outcomes; save for either metadata or data changes, but broadcast/maintenance only for visible changes.

6. `pushDeletions` currently receives no server row, so it has no trigger-assigned `updated_at` with which to construct the promised fingerprint ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1306)).  
   Fix — Request and decode `id, updated_at` from each tombstone update before removing its deletion-queue entry and registering the fingerprint.

VERDICT: REVISE
### Claude's response

**All 6 findings accepted.** Two concrete code claims were verified first; both were correct.

- **#6 (pushDeletions fingerprint) — verified true.** `pushDeletions` issues
  `.update(patch).eq("id", …).execute()` with no `.select()`, so nothing is returned and there is no
  trigger-assigned `updated_at` to key a fingerprint on. The Round-1 promise to register there was
  unimplementable as written. Plan now requires requesting/decoding `id, updated_at` and registering
  the fingerprint **before** removing the deletion-queue entry.
- **#4 (cancellation swallowed outside runStep) — verified true.** `downloadAndStoreImage` wraps its
  work in a blanket `catch` that treats `CancellationError` as a download failure and re-enqueues
  the image; `drainImageDownloads` is called outside `runStep` entirely, so a cancelled run reaches
  successful finalization. Plan now rethrows cancellation from broad catches, routes image draining
  through `runStep`, and re-checks cancellation before any success metadata commits.

Accepted without further verification (all sound on reading):

- **#1** — latch split into `forceRun: Bool` + `eventIdentities: Set<EventIdentity>`. Realtime
  identities alone cannot represent local edits, maintenance follow-ups, foreground or manual
  refresh; without `forceRun` a local edit arriving mid-run would be silently lost.
- **#2** — the most important finding this round. `requestSync` now returns an awaitable ticket that
  resolves when a run *satisfying* it completes, and `flushBeforeSignOut` becomes a barrier that
  drains the coordinator and re-verifies `hasPendingLocalChanges() == false` before the wipe.
  Enqueue-and-forget here would destroy un-pushed user edits on sign-out; promoted to the
  highest-value test case.
- **#3** — a generation token stops stale *bookkeeping* but not stale *side effects*. Account
  reconciliation/wipe must cancel **and await** the old executor, and the run must re-validate
  captured uid + generation after every network suspension before applying results or advancing a
  cursor.
- **#5** — good catch that my Round-1 revision would have introduced a new bug. "Nothing visible
  changed" ≠ "nothing needs persisting": a byte-identical row may still need `needsSync` cleared or
  ownership assigned, and refusing to save it would strand it permanently dirty — re-creating this
  very loop. Split into `didPersistLocalState` (drives saving) and `didChangeVisibleData` (drives
  the broadcast/maintenance).

Nothing was rejected this round.

## Round 3 — Codex

All six prior findings are addressed. New material issues remain:

1. The ticket API can deadlock: maintenance requesting and awaiting its own follow-up prevents the current run from finishing, while Realtime awaiting tickets can stall event consumption ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:79)).  
   Fix — Separate nonblocking `enqueueSync` from `requestSyncAndWait`, and never await a follow-up from inside the executor.

2. Ticket termination is undefined when a generation is cleared, a run aborts, or a real failure occurs; abandoned continuations could hang refresh/sign-in tasks permanently.  
   Fix — Give every ticket a `success/failed/cancelled` result and resume all associated continuations on every terminal path.

3. The sign-out barrier misses edits whose two-second local-save debounce has not yet entered the coordinator; draining an empty coordinator can still leave dirty rows ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:483)).  
   Fix — Cancel/absorb the debounce, explicitly request a final sync whenever pending local changes exist, and repeat until clean or a terminal failure prevents wiping.

4. Every abort currently re-arms a retry, which can create another permanent loop if URLSession repeatedly returns cancellation without a generation change ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:128)).  
   Fix — Suppress retries for stale/lifecycle generations and use bounded backoff for unexpected same-generation cancellations.

5. The image-drain cancellation test incorrectly requires prior deletion-queue removals not to commit; successful earlier steps are intentionally durable partial progress and cannot be rolled back ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:290)).  
   Fix — Test only cancellation during the tombstone request or between its response and queue removal; preserve removals completed before later cancellation.

6. The Realtime API question is already resolvable: in pinned supabase-swift 2.48.0, `AnyAction` itself has no `record`; only its associated `InsertAction` and `UpdateAction` values do.  
   Fix — Pattern-match the associated action, decode its record with the Supabase decoder, and test canonical timestamp equality against PostgREST-returned dates.

VERDICT: REVISE
### Claude's response

**All 6 findings accepted.** Codex confirmed all Round-2 findings were addressed.

Two of these caught flaws that my *own Round-2 revisions* introduced — exactly what the cross-model
check is for:

- **#1 (ticket deadlock)** — the awaitable `requestSync` I added in Round 2 would deadlock:
  `PlanDataMaintenance` (Step 1b) requesting *and awaiting* its follow-up from inside the executor
  blocks the run that must finish first, and Realtime awaiting tickets stalls event consumption.
  Split into nonblocking `enqueueSync` (the only form the executor may use) and
  `requestSyncAndWait` for callers that genuinely need completion.
- **#4 (retry loop)** — "abort re-arms a retry" would spin forever if URLSession repeatedly returns
  cancellation with no generation change, i.e. my fix could have grown a *new* permanent loop.
  Now: no retry for stale/lifecycle generations; bounded exponential backoff with a hard cap for
  unexpected same-generation cancellation.

Also accepted:

- **#2** — tickets need `.success/.failed/.cancelled` with all continuations resumed on every
  terminal path (`defer`-based), or an abandoned continuation hangs refresh/sign-in permanently.
- **#3** — important data-loss gap: `handleLocalSave` holds edits in a **2-second debounce** that has
  not yet reached the coordinator, so draining an empty coordinator can still leave dirty rows.
  Sign-out must cancel/absorb the debounce, then loop request-until-clean, and **refuse to wipe** on
  terminal failure. Added to the sign-out test as an explicit case.
- **#5** — my Round-2 test spec was wrong: it demanded that deletion-queue removals completed before
  a later cancellation be rolled back. Those are intentional durable partial progress and cannot be
  transactional across independent HTTP calls. Test narrowed to cancellation *during* the tombstone
  request or *between* its response and the queue removal.
- **#6 — verified true.** `Package.resolved` confirms **supabase-swift 2.48.0**. `AnyAction` exposes
  no `record`; only its associated `InsertAction`/`UpdateAction` do. Plan now pattern-matches the
  associated action, decodes with the Supabase decoder, and — importantly — compares timestamps
  **canonically rather than as strings**, since differing fractional-second rendering between
  Postgres and PostgREST would otherwise miss every match and silently defeat suppression. The
  corresponding open risk is now closed.

Nothing was rejected this round.

## Round 4 — Codex

The six prior findings are addressed. One material data-loss path and two consistency issues remain:

1. A failed flush only “blocks the wipe,” but current `signOut()` still signs out of Supabase regardless ([SupabaseAuthManager.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SupabaseAuthManager.swift:214)); dirty old-account data can then be destroyed by a later account-switch wipe.  
   Fix — Make flush failure abort authentication sign-out entirely, and run successful sign-out inside an exclusive account-transition state that prevents new saves between the final clean check and wipe.

2. The cancellation requirements still conflict: Step 2 retries only bounded same-generation cancellations, while the generic cancellation test says every cancelled run “re-arms.”  
   Fix — Split the test explicitly: lifecycle/stale cancellation must not re-arm; same-generation cancellation follows the bounded retry policy.

3. Step 1b still says maintenance calls `requestSync`, despite the new API forbidding awaitable requests inside the executor.  
   Fix — Name `enqueueSync(reason: .maintenance)` explicitly throughout Step 1b and update the stale `requestSync` test terminology.

VERDICT: REVISE
### Claude's response

**All 3 findings accepted.** Codex confirmed all Round-3 findings addressed. Converging: 11 → 6 → 6
→ 3 findings, and this round was one substantive issue plus two internal-consistency defects.

- **#1 — verified true, and a real data-loss path.** Read `SupabaseAuthManager.signOut()`:
  ```swift
  await SyncEngine.shared.flushBeforeSignOut()
  let safeToWipe = lastError == nil && hasCompletedInitialSync && !hasPendingLocalChanges()
  do { try await client.auth.signOut() } catch { … }   // runs regardless
  if safeToWipe { wipeForSignOut() }
  ```
  Only the *wipe* is gated. A failed flush therefore leaves the user signed out with dirty local
  rows; signing in with a different account then hits `reconcileAccountIfNeeded`, which wipes the
  store and destroys un-pushed edits that never reached the cloud. Plan now requires a failed flush
  to **abort authentication sign-out entirely**.
  I also found a **TOCTOU Codex only implied**: `safeToWipe` is computed *before* the
  `auth.signOut()` await, so a save landing during that suspension is wiped without ever syncing.
  Addressed by the exclusive account-transition state Codex proposed, now stated explicitly.
- **#2** — genuine self-contradiction introduced by my Round-3 edit: Step 2 says lifecycle
  cancellations must not retry, while the test bullet still said every cancelled run "re-arms".
  Test split into the two cases.
- **#3** — stale terminology: Step 1b still said `requestSync` after Round 3 split the API. Now
  names `enqueueSync(reason: .maintenance)` explicitly, with the reason (awaiting inside the
  executor would deadlock) stated inline.

Nothing was rejected this round.

## Round 5 — Codex (MAX_ROUNDS)

The prior findings are addressed conceptually. Two material implementation gaps remain:

1. The “exclusive account-transition state blocks new local saves” has no enforceable mechanism: the repository has dozens of direct `ModelContext.save()` calls, including asynchronous writers, and `willSave` observation cannot veto a save.  
   Fix — Define a concrete mutation barrier used by every write entry point, or use a `willSave` mutation revision plus a post-auth recheck and prohibit account-switch wiping whenever retained dirty rows belong to the previous account.

2. “Executor task is created detached” is unsafe if implemented as `Task.detached`: `SyncEngine` and `ModelContext` are main-actor-bound, so capturing the context across that boundary risks Swift concurrency errors.  
   Fix — Use a stored unstructured `Task { @MainActor in … }`; it remains independent of the debounce task without leaving the main actor.

Minor cleanup: replace the remaining stale `requestSync` references in Step 1 and Step 7 with `enqueueSync` or `requestSyncAndWait` so tests target the correct API.

VERDICT: REVISE
### Claude's response

**All 3 findings accepted and applied.** This was Round 5 of MAX_ROUNDS=5, so the loop terminates
here; the applied fixes were **not** re-reviewed by Codex.

- **#1 — accepted; my wording was genuinely unimplementable.** The plan said the account-transition
  state "blocks new local saves". It cannot: the repo has dozens of direct `ModelContext.save()`
  call sites (several asynchronous), and a `willSave` observer can *observe* but not *veto* a save.
  Replaced with an enforceable design that guards the **wipe** rather than pretending to block
  writes: (1) a monotonic `localMutationRevision` bumped by the existing `stampPendingChanges`
  `willSave` hook; (2) a post-auth recheck of both the revision and `hasPendingLocalChanges()` that
  aborts the wipe on any movement; (3) an account-switch backstop where `reconcileAccountIfNeeded`
  refuses to wipe retained dirty rows belonging to the previous account. (3) is the durable
  guarantee — even if every earlier gate is bypassed, un-pushed edits survive.
- **#2 — accepted.** "Executor task is created detached" was ambiguous and would be wrong if read as
  `Task.detached`: `SyncEngine` and `ModelContext` are main-actor-bound, so detaching carries the
  context across an actor boundary. Now specifies a stored unstructured `Task { @MainActor in … }`,
  which is independent of the debounce task without leaving the main actor.
- **#3 — accepted.** Remaining stale `requestSync` references in Step 1 and Step 7 renamed to
  `enqueueSync` / `requestSyncAndWait` so the tests target the real API.

## Resolution — MAX_ROUNDS reached without APPROVED

Per the skill, convergence is **not** faked. Status at termination:

- Rounds ran: 5/5. Finding counts: 11 → 6 → 6 → 3 → 3 (+1 cleanup). Every finding across all five
  rounds was accepted; none were rejected.
- Codex confirmed at each round that all prior findings were addressed.
- The Round-5 fixes are applied but unverified by a sixth review.
- No unresolved disagreement exists between Claude and Codex — the deadlock is procedural (the round
  cap), not substantive.

## Act 3 — Build

### Round 1 — Codex build (thread 019f896e-a50f-7be3-9f9f-cde9261015b9)

Codex implemented all 7 plan steps with full write access on branch `fix/sync-perpetual-loop`
(~48 min). 16 files changed, +1801/-271. Its own report claimed 266 tests green and flagged three
deviations honestly (see below).

### Claude's verdict — ACCEPTED, no fix rounds needed

Verified independently rather than trusting the report:

- **Proof re-run by Claude**, not taken from Codex's paste:
  `xcodebuild test -scheme QuaraMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
  → `Executed 266 tests, with 0 failures (0 unexpected)` · `** TEST SUCCEEDED **`. 47 of those are new.
- **Localization parity** — `Scripts/check_missing_keys.py` passes; EN/KM both gained the new
  sync-safety keys.
- **`PLAN.md` / `PLAN-REVIEW-LOG.md` untouched**, as instructed.

Hard project rules all hold:

- **No `Task.detached` in the executor** — it is `Task { @MainActor [weak self] in }` (SyncEngine.swift:258).
  The remaining `Task.detached` hits in the repo are all pre-existing files this change did not touch.
- **Cursor still never advances on push** — `setCursor` has exactly one call site, inside the pull's
  `applyLocal`.
- **`isApplyingSyncChanges` never wraps an `await`** — both spans (656–659 manual, 1813–1814
  `withSyncWriteGuard`) are synchronous; the `await requestSyncAndWait` at 757 sits *after* the guard
  block closes.
- **Every trigger routes through the coordinator** — zero direct `syncIfOperational` / `syncNow`
  callers remain outside `SyncEngine`.

Spot-checks on the highest-risk logic:

- **Root cause genuinely fixed** — `SyncRealtime.scheduleSync` no longer runs `syncNow` inside the
  debounce task; it calls the nonblocking `enqueueSync`, so `debounceTask?.cancel()` can only abort a
  sleep, never in-flight work.
- **Timestamp matching is canonical** — `EventIdentity` normalizes to microseconds
  (`Int64((timeIntervalSince1970 * 1_000_000).rounded())`) and compares on that integer, so
  fractional-second rendering differences between PostgREST and Realtime cannot silently defeat
  suppression (the Round-3 risk). Fingerprints are non-consuming; `reclassifyPendingEvents()`
  implements the pre-response race fix.
- **Sign-out barrier is correct** — `performProtectedSignOut` throws on flush failure *before*
  `authenticationSignOut()`, and re-validates `cleanRevision` after it via `canWipe`, then again in
  `wipe`. The TOCTOU is closed and the whole thing is injectable, hence deterministically testable.
- **Latch fix is correct** — `lastAlertThreshold = 0` now assigns only when the value differs. The
  still-unconditional `needsSync = true` in `triggerAlert` sits behind the `lastAlertThreshold <
  threshold` gate, so it is a bounded one-shot alert transition, not a loop.
- **Step 5** implemented as `ApplyOutcome(didPersistLocalState:didChangeVisibleData:)` across all
  12 pull appliers.

Deviations accepted (all disclosed by Codex, none silent):

1. `QuaraMoney.xcscheme` — test parallelization `YES` → `NO`, working around iOS 26.5 simulator clone
   crashes. Test-infra only; no app behaviour change. Matches the known-bad 26.5 runtime.
2. `Models/Category.swift` — added the explicit `inverse: \Transaction.category` to an existing
   relationship. Out of scope, but low risk: it declares what SwiftData was already inferring and
   matches the sibling relationships in the same file. Needed to get the pre-existing suite green.
3. Live 60-second device observation (acceptance criteria 1 & 2) not performed — requires an
   authenticated running app. Deferred to the user.
