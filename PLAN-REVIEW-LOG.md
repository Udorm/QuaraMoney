# Plan Review Log: Savings-as-Wallet
Act 1 (grill) complete — plan locked with the user. MAX_ROUNDS=5.

> The previous contents of this file (perpetual sync-loop-fix review log) are preserved in git
> history — recover with `git show HEAD:PLAN-REVIEW-LOG.md`.


Grill resolved 8 decisions: (1) fold onto Wallet, delete SavingsGoal; (2) block income/expense, allow both transfer directions + adjustments; (3) hard write-path guard as contract + picker-filter polish + recurring-rule pause/flag; (4) migration flips dedicated linked wallets else create+seed, preserve displayed progress + disclose small net-worth bump (option a); (5) net worth includes savings, two-figures-one-total display; (6) deterministic goal-derived wallet IDs + additive-only cloud schema; (7) rebuild chart on wallet balance, keep templates/priority/suggested-contribution/auto-contribute-reminders; (8) soft completion never-lock, drop max(0,…) floor, warn+offer-transfer on delete-with-balance. Single-device today; cloud safety is the bar.

## Round 1 — Codex (gpt-5.6-sol, high effort)

The plan is not safe to implement yet. The migration and compatibility strategy has several data-loss paths.

1. **The legacy data is deleted before it can be migrated.** Removing `SavingsGoal` and the transaction relationships is a non-additive SwiftData change, but the app currently has only `SchemaV1` and no migration stage ([SchemaVersioning.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/SchemaVersioning.swift:8)); startup maintenance cannot fetch types absent from the active schema.  
Fix: Introduce a real `SchemaV2` retaining legacy fields long enough to migrate them, then remove them in a later schema version.

2. **Cloud tombstoning contradicts “stop pushing savings goals.”** The migration promises to tombstone old goals and clear transaction tags, but stopping legacy pushes means neither `deleted_at` nor `savings_goal_id = null` reaches Supabase ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1461)).  
Fix: Continue pulling and pushing legacy goal tombstones and explicit transaction nulls throughout the deprecation window.

3. **Fresh installs can lose every legacy cloud goal.** Sync currently pulls goals before transactions ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1053)); if the new client ignores that table, a new device or post-sign-out cache rebuild has nothing local to migrate.  
Fix: Pull active legacy goals, migrate them locally after initial sync, push replacements and tombstones, and only then ignore tombstoned rows.

4. **Case A is not lossless.** A “dedicated” wallet balance contains only physical transfers, while the displayed goal also includes `currentAmount`; it may also use a different currency from the goal ([SavingsGoal.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/SavingsGoal.swift:78)).  
Fix: Permit Case A only when currencies match and wallet balance exactly equals the authoritative raw goal total; otherwise use Case B.

5. **Case A breaks deterministic deduplication.** Keeping the linked wallet’s random UUID on one device while another creates the goal-derived UUID can produce two savings wallets; the promised migration mapping has no local or cloud field.  
Fix: Always use one canonical goal-derived wallet ID, or add a synced `legacy_savings_goal_id` with a per-user unique constraint and conflict recovery.

6. **Case B compensation is undefined and fails for withdrawals or changed linked wallets.** Tagged transactions can touch historical wallets other than the goal’s current `linkedWallet`, and a net withdrawal requires a positive compensation—not the stated “outflow.”  
Fix: Compute signed goal-side deltas per physical wallet from every tagged transfer, apply exact inverse adjustments, and assert pre/post net-worth invariants before committing.

7. **Indeterminate goals will be silently under-migrated.** The reconciler skips rows lacking rates and exposes `hasUnconvertedRows`, so its `total` is only a partial displayed value ([SavingsLedgerCalculator.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/SavingsLedgerCalculator.swift:55)).  
Fix: Refuse and retry migration while totals are indeterminate, or preserve each unresolved row until an exact stored conversion can be established.

8. **The proposed “hard guard” is not a hard contract.** Transactions are created directly by CSV import, debts, events, recurring rules, bulk wallet moves, sync pull, and other paths ([CSVImportService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/CSVImportService.swift:497), [DebtService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/DebtService.swift:68), [EventLedgerService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/EventLedgerService.swift:547), [TransactionBulkEditingService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/TransactionBulkEditingService.swift:232)); authenticated Data API writes also bypass client code.  
Fix: Centralize ledger validation across every mutation and sync-apply path, plus add a database trigger enforcing wallet ownership and savings-kind transaction rules.

9. **Editing can leave an invalid transaction pending after rejection.** `AddTransactionViewModel` mutates an existing model before saving ([AddTransactionViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/AddTransactionViewModel.swift:201)); rejecting after mutation without rollback risks autosave persisting it.  
Fix: Validate the proposed immutable values before touching the model, and rollback the context on every failed commit.

10. **“Pause + flag” has nowhere to store the flag.** `RecurringRule` contains only `isActive`; there is no reason/status field to explain an automatic pause or synchronize it ([RecurringRule.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/RecurringRule.swift:36)).  
Fix: Add and sync a typed pause reason, or derive and display an invalid-wallet state while atomically setting `isActive = false`.

11. **Target currency is not invariant.** Wallet currency remains freely editable ([AddWalletViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/AddWalletViewModel.swift:41)), so changing it reinterprets `targetAmount` and historical balance data.  
Fix: Lock currency once a savings wallet has transactions, or atomically convert the target and all relevant historical rates.

12. **Persisted completion state will drift.** Transfers, adjustments, deletions, restores, sync pulls, and migration compensation can change balance without any specified completion reconciliation.  
Fix: Make completion computed from `balance >= targetAmount`, or define one mandatory post-ledger-mutation reconciler covering every write and pull path.

13. **Existing wallet deletion semantics corrupt savings history.** Deletion currently soft-deletes outgoing transactions and detaches incoming transfers ([SoftDeleteService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/SoftDeleteService.swift:74)); after withdrawing a savings wallet to zero, deleting it can still remove the counterpart wallet’s historical inflows.  
Fix: For emptied savings wallets, tombstone only the wallet while retaining transaction relationships to the tombstoned record.

14. **Archiving a funded savings wallet drops it from net worth.** The balance store explicitly excludes archived wallets ([WalletBalanceStore.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/WalletBalanceStore.swift:141)), contradicting the promise that savings remain in net worth.  
Fix: Either prohibit archiving funded savings wallets or include archived savings balances in net worth while hiding them from active lists.

15. **The Home UI assumption is false.** Home’s hero is a period income/expense chart, not net worth ([HomeView.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Views/Home/HomeView.swift:663)); adding a spendable/savings subline there mixes stock balances with period cash flow.  
Fix: Specify and build a separate net-worth balance section/data source, or move the breakdown exclusively to Wallets.

16. **The claimed auto-contribution reminders do not exist.** The fields are only modeled and synced; no scheduler consumes them.  
Fix: Either add a concrete reminder scheduling/rescheduling design and tests or remove “keep auto-contribute reminders” from scope.

17. **The chart migration discards history.** A single seed adjustment dated at migration makes prior progress appear to happen today, while `dailyBalanceSeries` lacks the existing 12-month monthly/upcoming semantics.  
Fix: Preserve historical goal-side movements or persist migration history points, and explicitly define chart window, aggregation, and future-dated behavior.

18. **The test plan misses the dangerous cases.** It omits cloud-only legacy recovery, old-client writes, indeterminate rates, starting balances, currency mismatches, divergent Case A/B devices, delete/archive behavior, bulk moves, restores, and sync-injected violations.  
Fix: Add those cases plus exact per-wallet and total net-worth assertions before treating migration as releasable.

VERDICT: REVISE
### Claude's response (Round 1)

Accepted essentially all 18 findings — the review was strong and several are genuinely material. Verified two scope-changing claims against the code before acting: #15 (Home hero is FinancialSummaryCards / period cash-flow, net worth lives in Wallets/NetWorthCard — CONFIRMED) and #16 (autoContribute fields are only synced, no scheduler consumes them — CONFIRMED dead). Revisions applied to PLAN.md:
- #1 Staged schema: added SchemaV2 (retains legacy SavingsGoal + Transaction savings fields) → migrate → SchemaV3 (removes them). No legacy deletion before migration.
- #2/#3 Deprecation-window sync: new client does NOT ignore savings_goals — it pulls active legacy goals, migrates locally AFTER initial sync, pushes replacement wallets + goal tombstones + explicit transaction savings_goal_id=null, then ignores tombstoned rows. Legacy pushes continue through the window.
- #5 Dedup mechanism replaced: deterministic-UUID dropped in favor of a synced legacy_savings_goal_id column on wallets (unique per user), carried by BOTH flipped (Case A) and created (Case B) wallets; migration keys idempotency on it.
- #4 Case A tightened: flip only when currency matches AND wallet balance == authoritative raw goal total (i.e. no phantom currentAmount, determinate). Else Case B.
- #6 Case B compensation defined: per-physical-wallet signed goal-side deltas from every tagged transfer, exact inverse adjustment per wallet, pre/post net-worth invariant assertion; withdrawals handled with correct sign.
- #7 Determinacy gate: migration refuses/retries while hasUnconvertedRows or rates unloaded; never seeds a partial total.
- #8 Contract widened: centralized ledger validation across ALL mutation + sync-apply paths (CSV, debts, events, recurring, bulk, sync pull) + a Postgres trigger as defense-in-depth.
- #9 Edit safety: validate proposed immutable values BEFORE mutating the model; rollback context on every failed commit.
- #10 RecurringRule gains a synced typed pause-reason (e.g. .invalidSavingsWallet) alongside isActive=false.
- #11 Currency locked once a savings wallet has any transaction.
- #12 Completion becomes COMPUTED (balance >= targetAmount); separate persisted hasCelebrated for one-time celebration only.
- #13 Savings-wallet deletion retains transaction relationships (tombstone the wallet, keep the counterpart wallets' historical inflows intact) instead of cascade-soft-deleting outgoing transfers.
- #14 Prohibit archiving a funded savings wallet (allow archive only at zero balance); resolves the net-worth exclusion contradiction.
- #15 Breakdown moved to Wallets/NetWorthCard (the real net-worth surface); Home hero untouched.
- #16 Auto-contribute reminders DROPPED from scope (non-functional today). NOTE: contradicts the user's grill answer (Q7 kept them believing they worked) — flagged for user sign-off.
- #17 Chart/history: Case B preserves un-tagged transfers with original dates; phantom currentAmount adjustment dated at goal.createdDate (not migration day); new chart window/aggregation defined explicitly.
- #18 Test matrix expanded to cover cloud-only recovery, old-client writes, indeterminate rates, currency mismatch, divergent Case A/B, delete/archive, bulk moves, restores, sync-injected violations, per-wallet + net-worth-total assertions.

Nothing rejected. One item (#16) changes a grill decision on new factual grounds and will be surfaced to the user.

## Round 2 — Codex (gpt-5.6-sol, high effort)

The revision addresses many prior findings: legacy retention, cloud-first recovery, strict Case A gating, centralized validation, computed completion, currency locking, correct net-worth placement, safe deletion/archive semantics, and broader tests. Material problems remain.

1. **Schema migration timing is contradictory.** The plan says conversion runs inside `MigrationStage.custom` and after initial cloud sync ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:43)), but schema migration occurs while the container opens, before authentication, sync, and rate loading ([QuaraMoneyApp.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/QuaraMoneyApp.swift:78)).  
Fix: Make V1→V2 structural-only, then run the account-scoped data conversion exclusively through `StartupMaintenanceGuard` after sync and rates settle.

2. **`SchemaV1` is not a frozen snapshot.** It references live `Wallet.self` and other live types, and the repository explicitly warns that a real V2 needs copied model definitions ([SchemaVersioning.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/SchemaVersioning.swift:46)).  
Fix: Define distinct frozen V1 and V2 model snapshots before adding fields, then test migration from a real file-backed V1 store.

3. **Case B still uses the wrong total for negative goals.** It seeds the floored “displayed total” while the new design promises raw negative balances; for `currentAmount = 100` and transfer net `-150`, seeding zero and compensating `+150` creates a `+150` net-worth bump instead of the allowed `+100`.  
Fix: Seed the authoritative `rawTotal`, not the legacy floored display total, and disclose any newly visible negative balance.

4. **Historical chart preservation is not actually implemented.** Keeping original transfer dates does nothing for the new savings wallet because those transfers remain attached to their old physical wallets after untagging ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:49)).  
Fix: Create one migration adjustment on the new savings wallet for each legacy ledger delta at its original date, plus the phantom starting-balance adjustment at `createdDate`.

5. **The net-worth invariant is dimensionally invalid.** “Sum of all wallet balances” directly adds USD, KHR, and other currencies.  
Fix: Assert both per-wallet expected deltas and total net worth converted into one currency using the same immutable rate snapshot used by migration.

6. **The unique dedupe key does not resolve concurrent inserts.** Two devices with different wallet UUIDs will hit the partial unique constraint; “skip if existing” only works when one device pulled the winner before migrating, while a race produces an upsert failure and retry loop.  
Fix: Define explicit unique-violation recovery that fetches the canonical server wallet, merges or reverses the losing local migration, and tombstones the loser.

7. **Old clients can mutate a migrated legacy ledger.** An offline old client can resurrect a tombstoned goal or upload a new transfer referencing it; the revised client then skips the goal because a wallet already has `legacySavingsGoalID`, leaving the new contribution unreflected.  
Fix: Make migrated goal tombstones irreversible server-side and reject new `savings_goal_id` references once a replacement wallet exists, or implement an incremental legacy-to-wallet bridge.

8. **Database enforcement protects transactions but not wallet mutations.** Raw or old clients can change a funded savings wallet’s currency, archive it, assign an invalid `kind`, or convert a wallet containing spending transactions.  
Fix: Add a `kind` check constraint and wallet-update trigger enforcing kind transitions, currency locks, target validity, and funded-archive restrictions.

9. **The transaction trigger must validate ownership too.** Current RLS checks only each transaction row’s `user_id`; foreign keys do not ensure referenced wallets belong to that user ([rls.sql](/Users/udormphon/Developer/QuaraMoney/supabase/rls.sql:34)).  
Fix: Have the trigger reject missing/cross-owner source and destination wallets as well as forbidden savings transaction types.

10. **“Reject/quarantine” has no durable behavior.** Returning no-op from the current apply loop still advances the table cursor, while throwing prevents cursor advancement and retries forever ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:3180)).  
Fix: Define a persisted quarantine/conflict record and cursor policy, surface it to the user, and provide a deterministic repair or server-delete path.

11. **Deferred migrations can make goals disappear.** The new Plan UI queries savings wallets, but indeterminate or invariant-failed legacy goals remain only as `SavingsGoal` rows.  
Fix: Dual-read unmigrated legacy goals as explicit “migration pending/needs attention” items until conversion succeeds.

12. **Savings wallets with no target remain undefined.** `targetAmount` is optional, yet completion compares against it and the Wallets creation flow exposes only a kind toggle.  
Fix: Require a positive target whenever `kind == .savings`, or explicitly design untargeted savings pots with separate progress/completion semantics.

13. **The migration summary is not durable.** A background conversion followed by a crash before presentation can permanently lose the promised disclosure and failure details.  
Fix: Persist an account-scoped migration report containing converted, deferred, failed, and net-worth-delta details until the user acknowledges it.

14. **The proposed test mechanism cannot verify the riskiest changes.** In-memory containers do not exercise an on-disk V1→V2 migration, and unit tests do not validate Supabase triggers or partial unique conflicts.  
Fix: Add file-backed schema-upgrade fixtures plus database integration tests for triggers, constraints, old-client writes, and unique-conflict recovery.

15. **Auto-contribution handling is still unresolved.** The plan explicitly awaits user sign-off, so implementation scope is not final.  
Fix: Record the decision before implementation—either drop the dead fields in V3 or specify a separate scheduler feature without migrating them onto Wallet now.

VERDICT: REVISE
### Claude's response (Round 2)

Codex acknowledged the R1 fixes and found a deeper layer. Verified the two schema-mechanic claims against code (#1 migration runs at container-open pre-sync/rates — CONFIRMED; #2 SchemaVersioning explicitly rejects a 2nd VersionedSchema over live types and documents additive fields migrate lightweight under V1 — CONFIRMED). This vindicated a simplification. Revisions:
- #1/#2 Schema corrected: additive phase needs NO new VersionedSchema (lightweight under SchemaV1); goal->wallet DATA conversion moved entirely into StartupMaintenanceGuard after sync+rates; frozen-snapshot SchemaV2 + MigrationStage deferred to the REMOVAL release. (Removed the wrong 'MigrationStage.custom runs the data migration' mechanic.)
- #3 Case B seeds authoritative rawTotal (not floored display total); newly-visible negatives disclosed.
- #4 History reconstructed on the NEW wallet: one dated adjustment per legacy ledger delta at its original date + phantom at goal.createdDate (un-tag alone did nothing since transfers stay on old wallets).
- #5 Net-worth invariant made single-currency via the immutable migration rate snapshot; per-wallet + total assertions.
- #6 (R2 race) Bounded unique-violation recovery: adopt canonical server wallet by legacy_savings_goal_id, tombstone the local loser; no upsert retry loop.
- #7 Old-client resurrection: server-side guard makes migrated tombstones authoritative (reject un-tombstone / new savings_goal_id inserts once a wallet carries that legacy id). Full incremental bridge REJECTED as out-of-scope given single-device sign-out/in usage — logged.
- #8 DB wallets guard added: kind CHECK + UPDATE trigger (currency-lock, kind-immutable, funded-archive block once wallet has txns).
- #9 transactions trigger extended to reject missing/cross-owner source/dest wallets (pre-existing RLS gap).
- #10 Sync-apply durable behavior simplified + trigger-backed: no throw (cursor stall) / no silent no-op; apply-then-locally-correct. No separate quarantine store — arbitration call, logged.
- #11 Plan UI dual-reads deferred/failed legacy goals as 'migration pending / needs attention' items.
- #12 Savings wallets REQUIRE a positive target at creation (both entry points); no untargeted pots in scope.
- #13 Durable, account-scoped migration report persisted until acknowledged.
- #14 Tests split into Tier 1 (in-memory logic) + Tier 2 (file-backed store upgrade fixture + Supabase-preview-branch trigger/unique-conflict/old-client/resurrection tests).
- #15 Auto-contribute elevated to a HARD GATE (decision recorded before build); recommend drop (a).

Scope-bounded (not gold-plated) with logged rationale: #7 (resurrection guard vs full bridge) and #10 (trigger-backed correction vs durable quarantine store), both justified by single-device sign-out/in usage. Nothing else rejected.

## Round 3 — Codex (gpt-5.6-sol, high effort)

The Round 2 fixes are substantially better, especially schema timing, raw-total migration, history reconstruction, currency-normalized invariants, deferred-goal visibility, and integration testing.

On deliberate scope bounds:

- I agree that a server-side resurrection guard can replace a full old-client bridge for a genuinely single-device model, provided rejected stale-client writes surface as sync errors.
- I agree that full concurrent-device merging can be out of scope.
- I disagree with applying and locally rewriting an invalid pulled financial row. Single-device use does not protect against partial deployment, preexisting cloud corruption, or administrative writes.

Material findings remain:

1. **The schema strategy still contradicts itself.** Section 1 correctly says no migration stage this release, but §5 still says conversion runs inside a SchemaV2 stage; removal is variously called SchemaV2 and SchemaV3 ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:18), [PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:50), [PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:67)).  
Fix: State consistently: additive release remains V1 with startup conversion; the later removal release is SchemaV2 everywhere.

2. **Cloud migration is not resumable across partial sync.** Current sync pushes wallets, goals, then transactions in separate steps ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1083)); a wallet can reach cloud before its adjustments/null-outs, after which `legacySavingsGoalID` causes another client or reinstall to “skip” the incomplete goal.  
Fix: Treat an existing replacement wallet as “resume/repair,” use deterministic IDs for every generated migration transaction, push transaction changes before the goal tombstone, and record a synced completion marker.

3. **The sync fallback guesses how to alter financial data.** An income/expense violation has no “savings linkage” to strip—the offending fact is its source wallet’s kind—so correction requires detaching the wallet, changing the type, or changing the wallet kind.  
Fix: Fail closed without mutating the ledger, preserve the cursor, and surface a durable sync-integrity error containing the row ID and repair action.

4. **The bounded dedupe recovery still overclaims convergence.** Tombstoning the losing wallet does not undo its new-wallet adjustments and physical-wallet compensation; both devices can otherwise contribute duplicate migration transactions.  
Fix: Either specify exact loser rollback using deterministic migration transaction IDs, or remove the two-device convergence claim/test and surface the unsupported conflict under the single-device scope.

5. **The wallet trigger can reject Case A as written.** “Kind immutable once a savings wallet has any transaction” can block the required normal→savings flip of a dedicated wallet that already contains transfers.  
Fix: Lock kind only when `OLD.kind = 'savings'`; separately allow normal→savings only after validating target and absence of spending transactions.

6. **Positive target validity is not enforced at the database layer.** Client creation requires it, but the proposed wallet constraints only validate `kind`, currency, and archive behavior.  
Fix: Add a database constraint equivalent to `kind != 'savings' OR target_amount > 0`.

7. **The synced recurring pause reason is missing from the cloud schema plan.** `SyncRecurringRuleRow` currently has no pause field ([SyncDTOs.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncDTOs.swift:141)), and §6 only lists new wallet columns.  
Fix: Add `pause_reason` to `recurring_rules`, its DTO, push/pull matching, canonical schema, migration, and compatibility tests.

8. **Migration adjustments can corrupt cash-flow reporting.** Adjustments affect flow unless excluded ([TransactionProcessor.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/TransactionProcessor.swift:76)); Case B creates many historical positive and negative adjustments.  
Fix: Mark every migration-generated adjustment `excludeFromReports = true` and give it deterministic migration provenance.

9. **Deleting a non-zero savings wallet still destroys net worth.** Retaining transaction relationships preserves counterpart history, but tombstoning the wallet removes its positive or negative balance from net worth; “withdraw first?” does not handle negative balances.  
Fix: Prohibit savings-wallet deletion until balance is exactly zero, offering withdraw for positive balances and top-up for negative balances.

10. **“Every mutation path” still omits restore and wallet-rehoming operations.** `SoftDeleteService.restoreTransaction` and wallet movement directly change relationships without validation ([SoftDeleteService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/SoftDeleteService.swift:42), [SoftDeleteService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/SoftDeleteService.swift:134)).  
Fix: Route restore, undo, wallet deletion/rehome, and every relationship reassignment through `WalletLedgerRules`.

11. **The server funded-balance check has no defined parity with the client engine.** The trigger must reproduce tombstone, event exclusion, source/destination, and stored-rate semantics or it will disagree with `Wallet.balance`.  
Fix: Specify one tested SQL balance function matching `Wallet.computeBalance`, or keep balance-dependent archive enforcement client-side and fail remote violations visibly.

12. **Migrated completed goals will replay celebrations.** `hasCelebrated` defaults false, but migration never maps the legacy completion state.  
Fix: Set `hasCelebrated` for migrated goals already at or above target and add a no-replayed-celebration test.

13. **Several tests retain obsolete expectations.** Case B still says it reproduces “displayed total” rather than `rawTotal`, and the migration fixture/version references remain inconsistent ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:79), [PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:83)).  
Fix: Test raw negative totals, partial cross-table sync/resume, deterministic migration IDs, reporting exclusion, and the consistently named removal schema.

14. **Auto-contribution remains an explicit hard gate.** The plan is not implementation-ready until the user records option (a) or (b).  
Fix: Resolve and record that choice before beginning the build.

VERDICT: REVISE
### Claude's response (Round 3)

Codex AGREED with 2 of my 3 scope bounds (resurrection guard replaces full bridge; concurrent-merge out of scope) and DISAGREED with the 3rd (R2 apply-then-locally-correct). Conceded the disagreement — Codex is right that single-device doesn't protect against partial deployment / preexisting corruption / admin writes. Accepted essentially all 14 findings; several were real bugs I'd have shipped. Revisions:
- #1/#13 Schema naming made consistent: additive release stays SchemaV1 + StartupMaintenanceGuard conversion; removal release is 'SchemaV2' everywhere (SchemaV3 eliminated). Removed stale 'runs inside SchemaV2 stage' language in §5.
- #2 Resumability: migration is single-device-authoritative; every generated migration transaction uses a DETERMINISTIC id (goal.id,purpose,delta-id) so interrupted pushes resume/repair not duplicate; existing replacement wallet = resume/repair (not skip); push wallet+txns+compensations BEFORE goal tombstone; per-goal synced completion marker gates 'migrated'.
- #3 (R3, REVERSAL) Sync-apply now FAILS CLOSED: skip offending row, record durable sync-integrity error (row id + repair action), advance cursor past it (no infinite loop), surface to user. No ledger mutation. Reverses R2.
- #4 Dropped the two-device convergence claim (tombstoning loser doesn't undo its adjustments/compensation). Single-device adopt-don't-remigrate; unique-violation = fail closed, not unsound auto-merge. Convergence test replaced by adopt test.
- #5 Wallet kind-lock only when OLD.kind='savings' (savings terminal) so the required normal->savings Case-A flip stays legal; normal->savings allowed once after validating target + no spending txns.
- #6 DB target CHECK: kind<>'savings' OR target_amount>0.
- #7 recurring_rules.pause_reason added to cloud schema plan (column + DTO + push/pull + mirror + compat).
- #8 ALL migration adjustments marked excludeFromReports=true + deterministic provenance (were polluting TransactionProcessor cash-flow).
- #9 Savings-wallet deletion allowed only at exactly zero: positive->withdraw, negative->top-up (old 'withdraw first' ignored negatives).
- #10 Enforcement list extended to SoftDeleteService.restoreTransaction/undo, wallet deletion + rehome, every relationship reassignment.
- #11 Balance-dependent checks (funded-archive, delete-until-zero) kept CLIENT-side; SQL would disagree with computeBalance's stored-rate/event/tombstone semantics. DB trigger keeps only non-balance guards.
- #12 Migration sets hasCelebrated=true for goals already >= target (no replayed celebration).
- #13 Test list updated: rawTotal incl. negatives, resumability/deterministic ids, reporting exclusion, adopt-don't-remigrate, consistent schema naming.
- #14 Auto-contribute remains a hard gate (user must record a/b before build).

Severity trend across rounds: R1 data-loss architecture -> R2 mechanics -> R3 precise refinements + 1 reversal. Converging. Nothing rejected in R3.

## Round 4 — Codex (gpt-5.6-sol, high effort)

The Round 3 findings are largely addressed, including the fail-closed sync reversal. I accept the deliberate single-device bounds: no concurrent-migration convergence and a resurrection guard instead of a full old-client bridge. However, several material implementation gaps remain.

1. **The synced completion marker has no model or cloud representation.** Migration correctness depends on it, but it is absent from the wallet fields and cloud columns ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:55), [PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:72)).  
   Fix: Add an explicit synced field such as `legacyMigrationCompletedAt` to `Wallet`, its DTO, SQL schema, and push/pull logic.

2. **The required migration push order conflicts with the current sync engine.** The plan requires adjustments before the goal tombstone, but sync currently pushes wallets, then savings goals, then transactions ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1084)).  
   Fix: Specify a dedicated acknowledged migration-sync sequence—or atomic server RPC—that pushes wallet and transaction changes before tombstone and completion marker.

3. **Contradictory stale instructions remain.** “Resume/repair” conflicts with “skip that goal”; fail-closed unique conflicts conflict with “adopt canonical/tombstone loser”; removal is still called V3 once ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:54), [PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:59), [PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:108)).  
   Fix: Delete the stale skip, loser-tombstoning, and V3 language so only marker-gated repair, fail-closed conflict handling, and SchemaV2 remain.

4. **The target constraint permits `NULL`.** PostgreSQL considers a CHECK successful when its expression is `NULL`, so `kind <> 'savings' OR target_amount > 0` does not enforce a target ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:29)).  
   Fix: Use `kind <> 'savings' OR (target_amount IS NOT NULL AND target_amount > 0)`.

5. **The resurrection guard covers inserts but not edits.** An old client can update an existing transaction from `savings_goal_id = NULL` to a migrated goal ID ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:67)).  
   Fix: Enforce the guard on both INSERT and UPDATE whenever `NEW.savings_goal_id` references a migrated goal.

6. **The two DB triggers have a check-then-write race.** A transaction insert can observe a normal wallet while a concurrent normal→savings update observes no spending transaction, allowing both to commit and violate the invariant.  
   Fix: Lock every referenced wallet row with `SELECT … FOR UPDATE` in both triggers, acquiring multiple locks in deterministic UUID order.

7. **The wallet trigger can unintentionally change normal-wallet behavior.** Section 2 says currency becomes immutable for any wallet with transactions, contradicting both §2’s savings-only rule and the explicit normal-wallet out-of-scope boundary ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:29), [PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:122)).  
   Fix: Scope the SQL currency lock explicitly to savings wallets and the normal→savings transition.

8. **Nullable wallet-reference semantics are underspecified.** Both wallet IDs are nullable in the existing schema, so “reject missing source/destination wallet” could reject valid income/expense rows with no destination.  
   Fix: Define the required source/destination matrix per transaction type and perform ownership checks only for non-null references.

The unresolved auto-contribution choice remains a procedural hard gate rather than a technical design defect, but it still must be recorded before implementation as the plan itself requires.

VERDICT: REVISE
### Claude's response (Round 4)

Verdict shrank 6.3k->3.9k; Codex explicitly ACCEPTED the single-device bounds. Remaining items are all SQL-precision + doc-consistency, no architecture. Accepted all 8:
- #1 Added synced legacyMigrationCompletedAt completion marker to Wallet + DTO + SQL column + push/pull; wallet with legacy id but nil marker = in-progress, resume/repair.
- #2 Dedicated ordered acknowledged migration push (prefer a single server RPC): wallet+txns+compensation -> tombstone -> marker atomically; marker written last.
- #3 Deleted stale contradictions: 'skip that goal' now gated on marker (else resume/repair); loser-tombstone/adopt-canonical recovery removed in favor of fail-closed; last stray 'V3' -> 'SchemaV2'.
- #4 target CHECK made NULL-safe: kind<>'savings' OR (target_amount IS NOT NULL AND target_amount>0).
- #5 Resurrection guard now fires on INSERT AND UPDATE (old client editing savings_goal_id NULL->migrated id).
- #6 Both triggers SELECT ... FOR UPDATE referenced wallets in deterministic UUID order (check-then-write race).
- #7 SQL currency lock scoped to savings-only + normal->savings transition; normal wallets untouched (was contradicting out-of-scope normal-wallet boundary).
- #8 Per-type source/destination matrix: income/expense need source and no destination (don't reject null dest); transfers need both; ownership checked only on non-null refs.
- Auto-contribute: still the procedural hard gate (user records a/b before build) - not a technical defect.

All accepted; nothing rejected. Remaining verdict content is implementation-precision, architecture stable since R2.

## Round 5 — Codex (gpt-5.6-sol, high effort) — FINAL (MAX_ROUNDS cap)

Round 4’s prior findings are addressed, and the single-device scope bounds are acceptable. Three material correctness gaps remain.

1. **The non-atomic migration option still has an unrecoverable crash window.** If the goal tombstone lands but the completion marker does not, a reinstall cannot reconstruct the migration because tombstoned goals are ignored and missing locally ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:61), [SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:2375)).  
   Fix: Make the atomic server RPC mandatory, or place the marker before tombstoning and define marker-present/live-goal recovery that finishes the tombstone.

2. **The transaction-type matrix omits `adjustment`.** Migration depends heavily on adjustments, but the SQL rules define shapes only for income, expense, and transfer ([PLAN.md](/Users/udormphon/Developer/QuaraMoney/PLAN.md:29)).  
   Fix: Explicitly require adjustments to have a source wallet, no destination, valid ownership, and a non-zero signed amount.

3. **The cloud `kind` constraint remains NULL-permissive unless the column is explicitly non-null.** A CHECK such as `kind IN ('normal','savings')` accepts NULL, potentially bypassing savings rules and breaking non-optional DTO decoding.  
   Fix: Define `kind text NOT NULL DEFAULT 'normal' CHECK (kind IN ('normal','savings'))`.

The auto-contribution sign-off remains a product-scope decision, but under this round’s correctness-only criterion it does not affect the verdict.

VERDICT: REVISE
### Claude's response (Round 5) — loop terminated at cap

Verdict shrank again (3.9k->1.6k). Codex confirmed R4 findings addressed and the single-device scope bounds acceptable. Three remaining findings, all narrow, all ACCEPTED AND APPLIED:
- #1 R5 Atomic server RPC is now MANDATORY (was 'ideally'). Non-atomic ordering had an unrecoverable crash window: tombstone lands + marker doesn't => reinstall ignores the tombstoned goal and can never reconstruct. Documented fallback: marker BEFORE tombstone + finish-the-tombstone recovery; never tombstone-first.
- #2 R5 Transaction-type matrix extended to 'adjustment': requires source wallet, no destination, valid ownership, non-zero signed amount (migration's own writes are adjustments and were unvalidated).
- #3 R5 kind column declared 'text NOT NULL DEFAULT ''normal'' CHECK (kind IN (''normal'',''savings''))' — bare CHECK accepts NULL, bypassing savings rules and breaking non-optional DTO decoding.

OUTCOME: MAX_ROUNDS=5 reached without a formal APPROVED line, but there is NO outstanding disagreement — every R5 finding was accepted and applied verbatim, and Codex explicitly confirmed the scope bounds are acceptable and that auto-contribution is a product decision not affecting correctness. Severity decayed monotonically across rounds: R1 data-loss architecture (18) -> R2 mechanics (15) -> R3 refinements + 1 conceded reversal (14) -> R4 SQL precision (8) -> R5 three narrow SQL/atomicity items (3). Claude's assessment: converged in substance; the only true open item is the USER-GATED auto-contribute decision (a or b), which is a product choice, not a defect.

### Act 2 resolution — user sign-off

Loop terminated at MAX_ROUNDS=5. No formal VERDICT: APPROVED was emitted, but no disagreement remains outstanding — all Round 5 findings were accepted and applied, and Codex confirmed the single-device scope bounds acceptable.

USER DECISIONS (recorded before build):
- Auto-contribute hard gate: option (a) — DROP the dead autoContribute* fields; not migrated onto Wallet; retired in the later SchemaV2 removal release. Supersedes grill Q7.
- Implementation: Codex builds it (Act 3, /codex-build) with SPEC_FILE=PLAN.md; Claude reviews the diff and runs the proof.

## Act 3 — Build (Codex writes, Claude verifies)

Builder: Codex gpt-5.6-sol (high effort), codex-cli 0.144.4, `codex exec --yolo`, one-shot whole spec. Branch feat/savings-as-wallet, clean tree at launch.

### Round 1 — Codex build
48 files changed, +1960/-1077, plus 6 new files (WalletLedgerRules.swift, SavingsWalletMigrationService.swift, SyncIntegrityStore.swift, SavingsWalletTests.swift, 20260806154757_savings_wallets.sql, supabase/tests/savings_wallets.sql).
Codex self-reported: BUILD SUCCEEDED + 304 tests 0 failures on OS=26.4.1; localization parity 1222/1222; no hosted Supabase ops; no git mutations.

### Claude's verdict — ACCEPTED (0 fix rounds needed)
Independently verified, not taken on report:
- PROOF RE-RUN BY CLAUDE: xcodebuild test ... OS=26.4.1 -> '** TEST SUCCEEDED **', 'Executed 304 tests, with 0 failures (0 unexpected)'. Build succeeded.
- Localization parity re-run by Claude: check_missing_keys.py -> 'Localization parity check passed.'
- FENCES HELD: git status shows no commits/branch changes; no hosted Supabase calls (SQL exists only as migration files + schema/rls mirrors); .vscode/ untouched; String+Localization.swift (auto-generated) untouched.
- House conventions clean on the diff: 0 new .system(size:), 0 new static .font(.app(, no Double/Float money fields, no enum-in-#Predicate, enqueueSync used (not syncNow).
- Spec fidelity spot-checked on the risk surface: WalletLedgerRules implements the exact per-type matrix incl. adjustment (#2 R5); migration service has the determinacy gate, rawTotal seeding (#3 R5), deterministic IDs, excludeFromReports provenance (#8 R3), hasCelebrated seeding (#12 R3), marker-gated idempotency, and single-currency net-worth invariant (#5 R3); SQL has kind NOT NULL DEFAULT + CHECK (#3 R5), NULL-safe target CHECK (#4 R4), 'for update ... order by id' (#6 R4), INSERT-OR-UPDATE triggers (#5 R4), apply_savings_wallet_migration atomic RPC (#1 R5), resurrection guard + partial unique index (#7 R2).
- 12 new tests map 1:1 onto spec §8 incl. review-derived cases (Case-A net-worth-flat, Case-B idempotency, negative rawTotal withdrawal, indeterminate deferral, celebration latch, adopt-don't-remigrate, file-backed legacy fixture).
- autoContribute correctly ABSENT from Wallet (user decision (a) honored).

ACCEPTED DEVIATIONS (disclosed by Codex, judged sound by Claude):
1. PROOF_CMD bug was mine: OS=26.4 does not exist on this machine (26.4.1 does). Codex reported the failure verbatim instead of silently substituting, then proved on 26.4.1. Correct behavior.
2. Normal-wallet .deleteTransactions no longer nulls incoming transfers' destinationWallet. This touches NORMAL-wallet behavior (nominally out of scope) but is FORCED by the spec's own rule that transfers must always have both endpoints — nulling would create rows that fail validation on restore/sync-apply. Balances are unaffected (an outgoing transfer debits its source regardless of destination). Judged a necessary consequence, not a redesign; flagged to the user.
3. Supabase local SQL tests written but not executed (Docker daemon unavailable). Codex did NOT fall back to the hosted project, per constraint. SQL trigger/RPC behavior therefore remains UNPROVEN until run against a local stack or preview branch.

NOT IMPLEMENTED (correctly, per spec): SchemaV2 removal of SavingsGoal/legacy columns (deferred release); auto-contribute scheduler; concurrent multi-device convergence. SavingsLedgerCalculator/SavingsGoalReconciler retained for migration + tests, retired from production presentation.

### Act 3 addendum — production cloud migration applied 2026-08-07

Pre-flight scan of the live project (czhkvtmpebeowipawqjk) found 28 pre-existing rows that would have violated the new transaction-matrix trigger:
- 24 transfers with source_wallet_id = destination_wallet_id (SampleDataService seed, note 'Pay Credit Card', $500/mo 2024-07..2026-06, both sides 'Bank Account') — money never moved, so balance-neutral.
- 4 expenses with source_wallet_id IS NULL (2026-06-22 test debris, no wallet/category/note, amounts 89/7777/89/999999) — attached to no wallet, invisible to every balance.

CLAUDE-FOUND BUG IN THE GENERATED SQL: validate_transaction_wallet_matrix fired on INSERT OR UPDATE for ALL rows including tombstoned ones. That made the 28 legacy rows permanently un-updatable AND created a deadlock — the cleanup UPDATE that tombstones them would itself have been rejected by the trigger it was clearing the way for. Fixed by adding an early 'if new.deleted_at is not null then return new; end if;' exemption (soft-deleted rows contribute to no balance, so validating their shape is pointless). Mirrored into supabase/schema.sql. Live rows remain fully enforced.

Applied by the USER in the Supabase SQL editor (Claude's direct DB writes were blocked by the permission classifier, twice; not worked around):
1. supabase/tests/STEP1_junk_row_cleanup.sql — tombstone-only (reversible), balance-neutral.
2. supabase/migrations/20260806154757_savings_wallets.sql

CLAUDE-VERIFIED POST-STATE (read-only queries): 28 rows tombstoned; 0 live violations; 7/7 new wallets columns; kind NOT NULL DEFAULT 'normal'; recurring_rules.pause_reason present; both CHECK constraints (wallets_kind_check, wallets_savings_target_check); all 3 triggers installed; apply_savings_wallet_migration RPC present; partial unique index on legacy_savings_goal_id present; deployed validate_transaction_wallet_matrix confirmed to contain the tombstone guard + row locking + deterministic lock order (i.e. the corrected file was applied).

STILL UNPROVEN AT COMMIT TIME: the triggers have never actually fired. supabase/tests/STEP3_trigger_smoke_test.sql (12 assertions inside BEGIN...ROLLBACK) was written for the user to run. Docker was unavailable so Codex's supabase/tests/savings_wallets.sql never executed either.

NEXT: device test with sync OFF (exercises the local Case A/B migration with zero cloud exposure), then sign in and sync.
