# Plan Review Log: Budget & Savings (Plan tab) rework
Act 1 (grill) complete — plan locked with the user. MAX_ROUNDS=5.

Grill decisions locked: full rework, additive-only model · calendar-aligned derived periods ·
rollover dropped · percent-of-income → creation-time suggestions · savings = direction-aware
transaction ledger w/ derived completion · auto-contribute dropped · unified Plan overview
(summary→detail) · guided quick-create · biweekly dropped · single alert picker.

Reviewer model: gpt-5.6-sol, reasoning xhigh (effort overridden from config's 'low' to match prior review precedent) — codex-cli 0.144.4.

## Round 1 — Codex

The plan is not safe enough to implement. Material correctness and migration invariants remain undefined:

1. **Existing non-recurring standard budgets fall through the new model.** The plan groups recurring budgets and custom one-offs, but existing `Budget.isRecurring` defaults to `false`, and migration never changes it ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:27), [Budget.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/Budget.swift:53)).  
   Fix: Treat every non-custom budget as a standing rule and migrate `isRecurring = true`; force custom budgets to false.

2. **“Total” versus “all tracked categories disappeared” is not representable.** Both states collapse to empty relationships, contradicting the proposed needs-attention behavior ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:35), [Budget.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/Budget.swift:219)).  
   Fix: Add and sync an explicit `targetKindRaw` (`total`/`categories`) and backfill it before filtering tombstoned relationships.

3. **Custom budgets lose their final day.** The plan mandates `[start,end)`, while existing date-only pickers store the selected end day at midnight and `Budget` uses it directly ([AddBudgetView.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Views/Analysis/AddBudgetView.swift:193), [Budget.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/Budget.swift:226)).  
   Fix: Store custom `endExclusive` as the start of the day after the user-selected end date and migrate existing custom ranges.

4. **Budget-currency progress cannot be stable under rate refreshes with the existing schema.** `storedRate` only converts into the owning/destination wallet currency, not an arbitrary budget currency ([Transaction.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/Transaction.swift:42), [Wallet+Extensions.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Extensions/Wallet+Extensions.swift:46)).  
   Fix: Persist an immutable base-currency conversion snapshot per transaction, or remove the stability claim and explicitly use live FX.

5. **The overview hero is mathematically invalid.** Summing weekly, monthly, yearly, total, and overlapping category budgets double-counts spending and has no single “period progress” ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:60)).  
   Fix: Base the hero on exactly one canonical total budget and otherwise show non-additive metrics such as budget count and highest-risk budget.

6. **A withdrawal flag does not define the amount credited to a goal.** Cross-currency transfers store source amount while the destination receives `amount × storedRate`; goal currency may differ from both ([AddTransactionViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/AddTransactionViewModel.swift:219), [Wallet+Extensions.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Extensions/Wallet+Extensions.swift:94)).  
   Fix: Snapshot signed `savingsAmount` plus `savingsCurrencyCode` on each tagged transaction and define how goal-currency edits handle existing entries.

7. **Ledger eligibility is underspecified.** `linkedTransactions` includes soft-deleted rows, and the current total blindly sums every linked transaction regardless of tombstone or type ([SavingsGoal.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/SavingsGoal.swift:77), [SoftDeleteService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/SoftDeleteService.swift:31)).  
   Fix: Define one eligibility predicate requiring `deletedAt == nil`, `.transfer`, matching goal, valid wallets, and a valid saved-amount snapshot.

8. **Completion reconciliation at “transaction-save choke points” misses many mutations.** Hard delete, soft-delete/restore, wallet moves, sync pulls, and goal target/currency edits bypass the add-transaction save path ([FilteredTransactionsViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/FilteredTransactionsViewModel.swift:214), [SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1387)).  
   Fix: Centralize goal reconciliation and invoke it after every relevant local mutation, sync pull, and initial migration, with deterministic `completedDate` semantics.

9. **Existing completed goals are not backfilled.** Goals already above target through `currentAmount` or linked transfers remain stale until another transaction is saved, so the claimed completion fix is incomplete.  
   Fix: Reconcile every existing goal during the one-shot migration and add seeded legacy-store tests for both completion and reactivation.

10. **Over-withdrawal is undefined.** Concurrent or edited withdrawals can make the derived balance negative, breaking progress charts and remaining-amount semantics.  
   Fix: Explicitly support negative balances or reject withdrawals exceeding the available snapshot balance and test concurrent/edit-induced overdraw.

11. **Mixed-version compatibility is materially misstated.** Old clients will count new withdrawals as positive, can write percentage/biweekly data back, and will observe cloud-migrated legacy fields; the risk is not limited to rollover ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:47), [PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:87)).  
   Fix: Gate cloud transformations and withdrawals behind an enforced minimum sync-client version or explicitly block mixed-version sync.

12. **The “one-shot” migration has neither a durable version marker nor reliable retry.** Current maintenance failures are debug-only and are not rearmed in the same session ([QuaraMoneyApp.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/QuaraMoneyApp.swift:625), [QuaraMoneyApp.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/QuaraMoneyApp.swift:713)).  
   Fix: Add a per-owner migration version, atomically stamp `updatedAt` and `needsSync`, commit the marker last, and surface/retry failures.

13. **Visibility-gating budget alerts suppresses legitimate alerts.** A transaction recorded outside the Plan screen can cross a threshold while the notification evaluator remains hidden ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:56)).  
   Fix: Gate evaluation on application activity, not Plan-view visibility, and test threshold crossings from every transaction entry path.

14. **Alert persistence is not delivery-idempotent.** A crash between notification scheduling and dedupe-state save can duplicate alerts, while saving first can permanently suppress a failed delivery.  
   Fix: Use deterministic notification request IDs derived from `(budget, period, threshold)`, persist state atomically, and retry/log scheduling failures.

15. **Suggestion statistics remain ambiguous and biased.** “Last three completed periods” does not say whether zero-spend periods count, and missing FX currently degrades to silent 1:1 conversion.  
   Fix: Build exactly three zero-filled period buckets, use failure-aware conversion, and downgrade confidence when any amount is unconvertible.

16. **The proposed off-main suggestion engine risks crossing SwiftData isolation boundaries.** Existing services operate on live `Category` and `Transaction` models, which cannot safely be captured by detached work.  
   Fix: Fetch inside a background `ModelContext` and return Sendable snapshots, or snapshot all inputs on the main actor before detaching.

17. **The past-period navigator rewrites more than the limit.** Editing period type, currency, or tracked categories retroactively changes every displayed historical period, but the plan only discloses current-limit reuse ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:62)).  
   Fix: Either version the complete rule or label the feature accurately as “historical spending evaluated against the current rule.”

VERDICT: REVISE
### Claude's response (→ PLAN.md Rev 2)

Accepted 16 of 17, one partially:

1. isRecurring — accepted, modified fix: rather than forcing recurring=true, legacy non-custom
   NON-recurring budgets migrate to .custom one-offs preserving their original anniversary window
   (their bounded intent survives); standard-period budgets become standing rules.
2. targetKind — accepted verbatim: additive `target_kind` column + backfill before tombstone
   filtering; backfill ambiguity for already-orphaned budgets documented as a risk.
3. Custom final-day — accepted, cheaper fix: interpret stored customEndDate as inclusive at read
   time (endExclusive = startOfDay+1d), no data rewrite; also retro-fixes the existing shipped bug.
4. Progress stability claim — accepted the "remove the claim" arm: no FX snapshot infra; progress
   stays in budget currency, cross-currency rows use live rates, stated honestly.
5. Hero math — accepted: hero is non-additive (month spending + x/y on track + highest risk);
   a left-to-spend headline only when a monthly total budget exists.
6. Savings amounts — accepted: savingsAmount + savingsCurrencyCode snapshot in goal currency at
   save; goal currency locks once ledger non-empty; legacy rows fall back to live conversion.
7. Ledger eligibility — accepted: single shared predicate (deletedAt==nil, .transfer, goal match,
   snapshot-or-fallback amount).
8. Completion choke points — accepted: SavingsGoalReconciler is the only isCompleted writer,
   hooked into save/delete chokes, goal edits, post-sync-pull apply, and migration.
9. Completed-goal backfill — accepted: reconciler runs over all goals in migration; seeded
   legacy-store tests added.
10. Over-withdrawal — accepted: raw ledger may go negative; display/progress floor at 0; withdraw
    sheet validates as best-effort.
11. Mixed-version — PARTIAL: risk statement rewritten to cover all named vectors (old-client
    rollover writes, percent/biweekly creation, withdrawal display skew). REJECTED enforced
    min-client-version sync gating: no version-gating infrastructure exists in app or backend and
    building one is disproportionate to display-only skew with no identified corruption path.
    Counter-mitigation: normalization made idempotent/repeatable so old-client writes heal.
12. Migration durability — accepted: per-owner versioned marker committed only after guarded save,
    re-armed by the existing gate, safe to retry because normalization is idempotent.
13. Alert visibility gating — accepted: evaluation is app-level (debounced .dataDidUpdate while
    active + foreground sweep), not Plan-view-visibility-gated.
14. Alert idempotency — accepted: deterministic request IDs (budgetAlert_<id>_<period>_<threshold>),
    state saved only after successful add, failures logged and retried.
15. Suggestion stats — accepted: zero-filled 3 buckets, failure-aware FX (no silent 1:1),
    confidence downgrade on unconvertible amounts.
16. Off-main SwiftData — accepted via simplification: engine runs on the main actor at sheet-open
    (bounded data); no detached model access.
17. Period navigator honesty — accepted: labeled "historical spending evaluated against the
    current rule" in plan and UI copy.

## Round 2 — Codex

Rev 2 addresses most prior findings: explicit target kind, inclusive custom dates, honest live-FX behavior, zero-filled suggestions, actor safety, app-level alerts, non-additive hero metrics, savings snapshots, legacy completion backfill, over-withdrawal behavior, and honest historical labeling.

Material issues remain:

1. **Repeatable normalization conflicts with the migration marker.** If the marker skips work, later old-client writes never heal; if normalization always runs, the marker does not control it. Current maintenance failures also do not rearm during the session ([QuaraMoneyApp.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/QuaraMoneyApp.swift:625)).  
   Fix: Separate marker-gated first migration from always-run normalization, and retry failed maintenance with bounded backoff.

2. **Non-recurring-to-custom conversion necessarily rewrites dates.** Preserving the original anniversary window requires setting `customEndDate`, and biweekly conversion must not shorten the original 14-day window ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:50)).  
   Fix: Capture the original `[start,end)` range before any period mutation, then store `customEndDate` as the final inclusive day.

3. **Mixed-version edits can corrupt snapshot semantics, not merely display them incorrectly.** An old client can edit a withdrawal’s amount, wallets, currency, or goal without updating the new snapshot columns, leaving wallet movement and savings ledger permanently inconsistent ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:94)).  
   Fix: Enforce a minimum client version for snapshot-backed entries or move snapshots into versioned child records old clients cannot overwrite.

4. **New snapshot rows still infer sign from mutable relationships.** A new contribution has `savingsIsWithdrawal == false`, but the plan can later reinterpret it as negative from wallet direction.  
   Fix: For rows with snapshots, treat the Boolean as authoritative—true is withdrawal, false is contribution—and reserve wallet-direction inference for legacy snapshot-less rows.

5. **Snapshot creation has no missing-rate behavior.** Freezing a silent 1:1 fallback permanently corrupts the goal ledger, and “that day’s rate” is unavailable for backdated transactions.  
   Fix: Use `convertOrNil`, describe it as the save-time rate, and block or explicitly flag the contribution when conversion is unavailable.

6. **The reconciler still misses a live deletion path.** Goal history drills into `FilteredTransactionsDetailView`, whose view model hard-deletes transactions directly instead of using `SoftDeleteService` ([FilteredTransactionsViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/FilteredTransactionsViewModel.swift:214)).  
   Fix: Route every transaction deletion/restore through one mutation service and reconcile both the old and new goal after edits.

7. **Sync ordering can publish completion before its contributing transaction.** The current engine pushes savings goals before transactions, allowing another device to receive `isCompleted = true` without the ledger row and reconcile it back to false ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:661)).  
   Fix: Add an explicit post-pull reconciliation phase and push derived goal status only after related transactions have successfully pushed.

8. **Legacy alert migration remains lossy.** A valid 100%-only configuration maps to `nearingOver`, silently enabling an 80% alert; 50%-only/projected configurations also collapse without a stated policy ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:44)).  
   Fix: Add an `overOnly` mode and explicitly migrate or release-note removed 50%/projected preferences.

9. **Multiple monthly total budgets make the hero ambiguous.** Quick-create permits duplicates, but the plan does not define which total budget supplies the headline ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:66)).  
   Fix: Enforce one standing total budget per period type or define a deterministic selection with an explicit duplicate-warning state.

VERDICT: REVISE
### Claude's response (→ PLAN.md Rev 3)

All 9 accepted, several via a design change that simplifies rather than patches:

1. Marker vs normalization — accepted: split into a marker-gated one-time migration (backfills,
   one-off conversion, completion backfill) and an always-run idempotent normalization (percent
   freeze, recurring-biweekly→weekly, nil backfills for old-client rows). Retry rides the
   existing gate re-arm points (settle/launch/foreground maintenance); no new backoff machinery.
2. One-off conversion dates — accepted: capture original [start,end) before mutating periodType;
   biweekly one-offs keep their full 14-day window; customEndDate stored as final inclusive day.
3+4+5. Snapshot corruption / sign authority / missing-rate — accepted via REDESIGN: the
   savingsAmount/savingsCurrencyCode snapshot columns are DROPPED. Ledger amount derives from
   transfer facts already on the row (contribution = destination-side amount × storedRate,
   withdrawal = source-side amount); savingsIsWithdrawal is the sole, authoritative sign source
   (legacy/old-client rows default false = contribution, historically exact — wallet-direction
   inference removed entirely). No save-time FX; goal-currency display conversion is live and
   failure-aware. Old-client edits update amount/storedRate coherently, so wallet math and goal
   ledger cannot diverge — the corruption vector is dissolved, not gated.
6. Hard-delete path — accepted: FilteredTransactionsViewModel routed through SoftDeleteService
   (also fixes the pre-existing tombstone-bypass sync bug); goal edits reconcile old + new goal.
7. Completion flap — accepted, different mechanism than proposed: pull-triggered reconciliation
   is local-only (never sets needsSync) so a receiver can't overwrite the sender's derived state;
   local mutations push as normal. REJECTED reordering pushes to transactions-before-goals:
   transactions FK-reference goals, so goals must push first for referential integrity.
8. Lossy alert migration — accepted: alertMode gains overOnly (off/nearing/overOnly/nearingOver,
   still one picker); 80/100 combos map exactly; 50%/projected dropped with release note.
9. Duplicate total budgets — accepted: quick-create blocks a second standing total budget of the
   same period type; synced-in duplicates get a needs-attention state and the hero deterministically
   uses the oldest by createdAt.

## Round 3 — Codex

Rev 3 resolves most Round 2 findings: authoritative withdrawal direction, no fragile savings snapshots, preserved one-off ranges, lossless alert modes, centralized soft deletion, local-only pull reconciliation, and deterministic handling of duplicate total budgets.

Material issues remain:

1. **The claimed maintenance retry still does not exist.** The current gate returns `.failed` without rearming, and foregrounding skips maintenance once `accountMaintenanceCompleted` is true ([QuaraMoneyApp.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/QuaraMoneyApp.swift:625), [QuaraMoneyApp.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/QuaraMoneyApp.swift:782)).  
   Fix: Explicitly add bounded retry/rearming and invoke always-run normalization after relevant sync pulls, not only startup.

2. **Migration ordering breaks one-off percentage budgets.** If the marker-gated pass converts monthly/biweekly one-offs to `.custom` before percent normalization, the original period type needed to select the completed income period is lost ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:49)).  
   Fix: Freeze percent limits using the captured original period type before changing `periodTypeRaw`.

3. **Legacy transfer conversion still diverges from wallet math.** Existing transfers may lack `storedRate`; wallet balances fall back through legacy `exchangeRate` and then fallback rates, while the plan only specifies `storedRate` ([Wallet+Extensions.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Extensions/Wallet+Extensions.swift:56)).  
   Fix: Share one transfer-side amount resolver with wallet balance logic and test stored-rate, legacy-rate, and missing-rate paths.

4. **Changing goal currency corrupts legacy starting balances.** The plan converts or retains the target but leaves `currentAmount` numerically unchanged even though it is implicitly denominated in the old goal currency.  
   Fix: Lock currency when `currentAmount != 0`, or explicitly convert the starting balance in the same atomic edit.

5. **Live FX can change completion without invoking the reconciler.** Ledger totals may cross the target after `.currencyRatesDidChange` or after a previously missing rate appears, but active/completed sections still use stored `isCompleted`.  
   Fix: Reconcile affected goals on rate-table changes, or derive list membership directly from the same live total used by progress.

6. **“Pull reconciliation is local-only” conflicts with automatic mutation tracking.** Saving a changed goal normally stamps `needsSync = true`; the plan does not say that this save runs under the sync-write guard ([SyncMutationTracker.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/QuaraMoney/Supabase/SyncMutationTracker.swift:83)).  
   Fix: Perform pull-triggered reconciliation and save inside `withSyncWriteGuard`, with a test asserting the goal remains clean.

7. **Old-client compatibility of the withdrawal flag is assumed, not verified.** Old payloads omit `savings_is_withdrawal`; correctness depends on Supabase upsert preserving that existing column rather than applying its default ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1920)).  
   Fix: Add a real Supabase compatibility test using the old transaction payload; require version gating if it resets the flag.

8. **Suggestions remain unit-ambiguous.** The amount and copy are monthly, but Options can change the saved budget to weekly, quarterly, or yearly without specifying recomputation ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:69)).  
   Fix: Recompute suggestions from three completed periods of the selected type and update the displayed unit whenever period type changes.

9. **Nil target/alert values from old-client realtime rows remain wrong until another maintenance pass.** The always-run normalizer is not currently part of sync, so a newly pulled category budget can temporarily behave as a total budget.  
   Fix: Give nil-backed getters lossless legacy derivation and normalize pulled budgets immediately after the budget pull.

VERDICT: REVISE
### Claude's response (→ PLAN.md Rev 4)

All 9 accepted (one as a verification requirement rather than a design change):

1. Retry doesn't exist — accepted: plan now explicitly upgrades the gate's .failed path (neither
   durable marker nor in-session accountMaintenanceCompleted set on failure → same-session retry
   at existing triggers), and always-run normalization additionally runs after budget sync pulls.
2. Migration ordering — accepted: percent freeze runs FIRST, using each budget's original period
   type, before one-off conversion rewrites periodTypeRaw; ordering is now explicit (a→d).
3. Legacy transfer rates — accepted: one shared transfer-side amount resolver extracted from
   Wallet+Extensions (storedRate → legacy exchangeRate → fallback) used by both wallet balances
   and the savings ledger; all three rate paths tested.
4. Goal-currency + legacy starting balance — accepted (lock variant): currency edit locked while
   legacy currentAmount ≠ 0; conversion of a read-only legacy value was rejected as it
   contradicts "never writable".
5. FX-driven completion — accepted, both arms: UI derives list membership/detail state from live
   totals (stored flag is only a cloud/filter cache), AND the reconciler hooks rate refreshes
   (local-only, like pulls — a rate move is not a user mutation to push).
6. Pull reconcile vs mutation tracker — accepted: pull-/rate-triggered reconciliation saves run
   inside the synchronous withSyncWriteGuard span (never across await, per the tracker contract),
   with a test asserting the goal stays needsSync-clean.
7. Old-payload upsert preserving the flag — accepted as a hard pre-ship verification step against
   the live schema (expected PostgREST partial-column upsert behavior; checked, not assumed;
   documented abort condition if it fails). Version gating remains rejected/out of scope.
8. Suggestion units — accepted: buckets and copy recompute per selected period type; a monthly
   average can never be saved as a weekly limit.
9. Nil raw fields on pulled rows — accepted with a stronger fix than requested: targetKind and
   alertMode getters are nil-lossless (derive from legacy fields/relationships with the exact
   backfill rule), making backfill an optimization; plus post-pull normalization.

## Round 4 — Codex

Rev 4 addresses all nine Round 3 findings directly. The revised migration order, transfer resolver, rate-triggered reconciliation, guarded local-only saves, compatibility check, nil-lossless getters, and period-aware suggestions are substantially stronger.

New material issues remain:

1. **Mixed-version withdrawal editing is still semantically unsafe.** Preserving an omitted `savingsIsWithdrawal = true` prevents data loss, but an old client can re-tag that transaction to another goal while believing it is a contribution; the hidden flag makes it a withdrawal on new clients ([AddTransactionView.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Views/Transactions/AddTransactionView.swift:382)).  
   Fix: Gate editing/tagging of withdrawal rows to withdrawal-aware clients; verifying partial upsert behavior alone is insufficient.

2. **Old clients can still corrupt a legacy starting balance’s denomination.** Rev 4 locks goal currency only in the new UI; an old client can change `currencyCode` while leaving `currentAmount` unchanged, after which the original denomination is unrecoverable.  
   Fix: Add `startingBalanceCurrencyCode` during migration and always interpret `currentAmount` through it, or require minimum-version gating for such goals.

3. **The main-actor suggestion assumption is no longer bounded to three months.** Period-aware yearly suggestions scan three years, and total-budget suggestions scan every expense in those periods on the UI actor ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:39)).  
   Fix: Fetch and aggregate in a background `ModelContext`, returning Sendable suggestion snapshots.

4. **Custom-period suggestion behavior is undefined.** A custom one-off has no repeating calendar unit, so “three completed periods in that unit” cannot be computed.  
   Fix: Disable historical suggestions for custom budgets or explicitly scale a daily average to the selected custom duration.

5. **Weekly periods and synced alert keys are not stable across devices.** `Calendar.current.firstWeekday` can differ by device or region, producing different weekly ranges and `periodStartISO` keys for the same synced budget.  
   Fix: Persist the budget’s week-start/calendar basis or use one account-wide fixed calendar for period math and alert keys.

6. **The marker still lacks an identity for local-only users.** A per-owner UUID marker is undefined when `localOwnerID == nil`, yet startup maintenance also runs for users who never enable Supabase.  
   Fix: Define an explicit local-store sentinel identity and test marker durability before and after account adoption.

7. **The past-period navigator remains undefined for custom one-offs.** `.custom` has no adjacent derived periods, but the UI description still applies the navigator to every budget detail.  
   Fix: Hide the period navigator for custom budgets and show only their single inclusive window.

VERDICT: REVISE
### Claude's response (→ PLAN.md Rev 5)

Accepted 6 of 7; rejected 1 with reason:

1. Old-client re-tag of withdrawal rows — REJECTED as a gating requirement: blocking edits from
   old clients needs server-side version awareness that doesn't exist and was already ruled out
   of scope; there is no client-side mechanism (the old client is the one acting). Accepted as a
   documented residual risk: consequence is a sign error on the re-tagged goal, requires the same
   user editing on an outdated second device, visible and one-tap-fixable in the new UI.
2. Starting-balance denomination — accepted, stamp variant: new additive
   savings_goals.starting_balance_currency_code set at migration; currentAmount always
   interpreted through it. This also REPLACES Rev 4's currency lock — with denomination pinned,
   goal currency is freely editable again (strictly better UX than the lock).
3. Unbounded main-actor suggestion scans — accepted: engine computes in a background ModelContext
   returning Sendable snapshots (WalletBalanceStore pattern), consistent with Round 1 finding 16's
   isolation constraint.
4. Custom-period suggestions — accepted (disable variant): no repeating unit, no suggestion;
   scaling a daily average was rejected as false precision.
5. firstWeekday instability — accepted: weekly budgets persist week_start_day (stamped at
   creation / by migration), all devices derive identical ranges and alert keys.
6. Marker identity for local-only stores — accepted: "local" sentinel identity, re-evaluated on
   account adoption (idempotent), tested across the boundary.
7. Navigator on custom one-offs — accepted: hidden; single inclusive window shown.

## Round 5 — Codex (final round, MAX_ROUNDS reached)

Most prior findings are addressed, but two material gaps remain:

- Post-migration old-client one-offs break: an old client can still create a standard-period budget with `isRecurring == false`; because the one-off conversion is marker-gated and normalization does not repeat it, updated clients will incorrectly treat that budget as a permanent standing rule. Fix: make conversion of non-custom, non-recurring budgets an idempotent post-pull normalization.
- `weekStartDay` alone does not make weekly periods deterministic: devices in different time zones derive different absolute `Date` boundaries and `periodStartISO` alert keys, causing inconsistent totals and duplicate/missed alerts. Fix: persist a canonical time zone/calendar basis and use it for period calculations and notification keys.

VERDICT: REVISE
### Claude's response (→ PLAN.md Rev 6) — resolution at cap

1. Old-client one-offs post-migration — ACCEPTED fully: non-custom non-recurring → .custom
   conversion moved into the always-run idempotent normalization (same freeze-before-convert
   ordering), so old-client-created one-offs can never masquerade as standing rules.
2. weekStartDay + time zones — SPLIT. Accepted: alert period keys become calendar-component
   labels (2026-W29 / 2026-07 / 2026-Q3 / 2026; custom = budget ID), so key format is identical
   across devices and time zones. REJECTED: persisting a canonical account time zone for period
   math. Reason: the entire app (analytics, Home, transaction grouping) computes date boundaries
   in device-local time; pinning budgets to an account time zone would make the Plan tab disagree
   with the analytics screens beside it for every travelling user, to fix an edge (simultaneous
   multi-time-zone devices) whose worst case — a boundary transaction in adjacent periods — is
   the app's existing, documented date semantics.

Outcome at cap: 5 rounds, final verdict REVISE. 43 of 44 findings accepted in some form across
the review; the sole unresolved disagreement is the canonical-time-zone question above, handed
to the user with both positions stated.

## Sign-off
User broke the sole remaining tie in favor of device-local period math (Claude's position);
PLAN.md Rev 6 is final. User chose Codex to implement (Act 3 — /codex-build).

## Act 3 — Build

### Round 1 — Codex build
Thread 019f75d1-7cd2-78c3-87d0-f5335e105b7e. 37 files (640+/874−), honest self-report: data/logic
core complete (calendar periods, resolver, reconciler, maintenance, notifications, sync DTOs, SQL,
bilingual strings, 7 new tests), UI/engine layer partially done. Claude-run proof: full suite
green on iOS 26.4.1 (exit 0), incl. all PlanReworkTests.

### Claude's verdict
Core is spec-faithful: models (nil-lossless getters, component period keys, inclusive custom end,
tombstone-filtered categories), maintenance ordering (percent-freeze before one-off conversion,
marker-after-save, failure re-arm verified), sync hooks (normalization pushes heals, reconciliation
local-only under guard), Wallet math delegation, soft-delete routing fix, direction-aware VM flow.
FAILS review on:
1. PlanOverviewView hero subtracts preferred-currency spending from budget-currency limit; row
   formats preferred-currency amount with budget currency symbol (mixed-currency bug class).
2. Withdraw sheet pre-fills linked wallet as DESTINATION for withdrawals (should be source).
3. PlanDataMaintenance converts with USD/KHR-only fallbackRates (live-rates snapshot removed).
4. Alert dedupe state recorded before UNUserNotificationCenter.add outcome (spec: after success).
5. evaluateStore is O(budgets×transactions) per data update (single-pass API exists, unused).
6. BudgetSuggestionEngine is a rename only — no bucket/confidence/background contract, not wired
   into quick-create (static caption).
7. Quick-create: free-text currency field (CurrencySelectionView exists), default target=total
   opens pre-blocked when a total budget exists.
8. BudgetListView untouched: no standing/one-off grouping, filter sheet now unreachable, search
   bindings dead; BudgetInsightsView orphaned (MoreView entry removed, content not folded).
9. Insights card + hero are placeholders (no month spending, no highest-risk).
→ Fix round 1 dispatched.

### Round 2 — Codex fix round 1
All 11 review items fixed, no deviations claimed.

### Claude's verdict (round 2)
Verified in code, item by item: hero/rows now use per-budget-currency spending
(spendingByBudgetCurrency) hoisted to one pass per body; withdrawal sheet sets the linked wallet
as SOURCE; PlanDataMaintenance takes an injected rates table (both callers snapshot
CurrencyManager.shared.rates on the main actor) and skips rows with missing rates; alert dedupe
state persists only after UNUserNotificationCenter.add succeeds (deterministic IDs make retries
safe); BudgetSuggestionEngine is real (detached ModelContext, Sendable result, three zero-filled
calendar buckets, missing-rate exclusion + confidence downgrade, custom ⇒ nil, enum kept out of
#Predicate) and wired into quick-create via .task(id:) with Use-suggestion fill,
CurrencySelectionView, and .categories default; BudgetListView rebuilt (needs-attention /
standing / upcoming / active / ended sections, searchable, toolbar Menu filter, count-based
summary); overview hero shows real month spending + on-track + highest-risk; BudgetInsightsView
deleted; all new strings bilingual. Claude-run proof: ** TEST SUCCEEDED **, exit 0 (iOS 26.4.1).
Build accepted — presenting for human commit sign-off.
