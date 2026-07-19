# Plan Review Log: Budget & Savings UI/UX redesign (Plan tab v2)
Act 1 (grill) complete — plan locked with the user. MAX_ROUNDS=5.

## Round 1 — Codex

The plan is not implementation-ready. Material problems:

1. **The budget headline is mathematically invalid.** Existing batch APIs use each budget’s own period, not the calendar month, and overlapping total/category budgets count the same transaction multiple times ([BudgetCalculator.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/BudgetCalculator.swift:54)).
   Fix — Compare calendar-month spending against one canonical total budget, or define and test explicit scope de-duplication before aggregating mixed budgets.

2. **The monthly-equivalent formula is incomplete.** `BudgetPeriodType` includes `.biweekly`, but the plan specifies no conversion for it ([BudgetPeriodType.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/BudgetPeriodType.swift:4)).
   Fix — Define every enum case explicitly, including biweekly × 26/12, and test with an injected date/calendar.

3. **“Only one new helper” is false.** Calendar-month spending across tracked scopes cannot be produced by `spendingByBudget`, which hard-codes `budget.periodDateRange`; new range-aware aggregation logic is required.
   Fix — Revise scope to include a tested range-aware budget projection rather than burying new financial logic inside a SwiftUI view.

4. **Savings totals regress when a goal completes.** Because the headline includes active goals only, finishing a goal makes saved and target totals disappear; an account with only completed goals becomes an undefined 0/0 card.
   Fix — Include completed goals in lifetime totals or specify a distinct “All goals completed” state instead of rendering active 0/0 totals.

5. **There are competing completion authorities.** The current list derives completion from `SavingsGoalReconciler.total`, while rows use `totalSaved` and the plan ambiguously says “non-completed”; these disagree when `isCompleted` is stale or conversion fails ([SavingsGoalListViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/SavingsGoalListViewModel.swift:8)).
   Fix — Build one savings projection from `SavingsGoalReconciler.Result` and use it for segments, badges, counts, totals, progress, and charts.

6. **Multi-currency totals silently corrupt unknown currencies.** `CurrencyManager.convert` falls back to returning the unconverted amount, effectively treating missing-rate currencies as 1:1, despite the plan claiming a failure-aware policy ([CurrencyManager.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Managers/CurrencyManager.swift:207)).
   Fix — Use `convertOrNil`, exclude unavailable rows, and display a partial-data warning in every aggregate.

7. **The six-month savings chart has an incorrect opening balance.** Contributions older than six months must be included in the opening balance; using only `currentAmount` as the baseline makes the chart endpoint disagree with the displayed total.
   Fix — Calculate the opening balance from the stamped starting balance plus every eligible ledger row before the chart window, then accumulate sorted in-window rows.

8. **Completed-goal actions are not compatible with the “unchanged” contribution sheet.** `AddTransactionView` excludes completed goals from its picker, so a preselected completed goal has no valid picker tag ([AddTransactionView.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Views/Transactions/AddTransactionView.swift:1028)).
   Fix — Add an explicit locked-goal override to the contribution flow and test contribution and withdrawal for completed goals.

9. **The form inventory is factually wrong.** The current create-goal form has templates and linked-wallet selection, but no description, priority, or currency-conversion offer; deleting it silently removes features while claiming “no new fields” ([AddSavingsGoalView.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Views/SavingsGoals/AddSavingsGoalView.swift:67)).
   Fix — Produce an explicit field-parity matrix and either preserve templates/linked wallet or document their removal while acknowledging description, priority, and conversion UX as new work.

10. **Budget currency edits can change value by orders of magnitude.** The plan offers conversion behavior only for goals; changing a budget from USD to KHR can turn 500 USD into 500 KHR.
    Fix — Require an explicit Convert Amount / Keep Number / Cancel decision for both budget and goal currency changes, including missing-rate behavior.

11. **“Save paths unchanged” preserves broken persistence observability.** Goal edits merely mutate properties without explicit save/error handling, while existing budget and delete paths swallow failures with `try?` ([EditSavingsGoalView.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Views/SavingsGoals/EditSavingsGoalView.swift:166)).
    Fix — Give both unified forms one explicit throwing save path that stamps sync metadata, saves, posts `.dataDidUpdate` only after success, and keeps the form open on failure.

12. **Edit-mode duplicate detection can reject the object itself.** Reusing create-mode duplicate-total logic without excluding `existing.id` makes an existing total budget appear to duplicate itself.
    Fix — Exclude the edited budget ID and use the same oldest-`createdAt` canonicalization as the list.

13. **Delete-from-detail navigation is unspecified.** Soft-deleting inside an edit sheet leaves the underlying detail displaying a tombstoned model, and the plan invents an “existing form delete” that does not exist.
    Fix — Define an `onDeleted` callback/navigation-pop flow and surface save failures before dismissing either the form or detail.

14. **“See All” cannot match `BudgetCalculator` semantics.** `FilteredTransactionsDetailView` does not exclude `excludeFromReports` rows and its descriptor excludes archived-wallet transactions, while the calculator uses different rules ([FilteredTransactionsViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/FilteredTransactionsViewModel.swift:108)).
    Fix — Extend the filter configuration with explicit report-exclusion and archived-wallet policies, then share one tested relevance predicate across recent rows, chart, and See All.

15. **The suggestion workflow retains a stale-result race.** `BudgetSuggestionEngine` launches an unstructured detached task, so cancelling `.task(id:)` does not reliably prevent an older request from overwriting a newer selection ([BudgetSuggestionService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/BudgetSuggestionService.swift:45)).
    Fix — Make computation cancellation-aware and generation-check the request before applying its result.

16. **The localization step violates repository instructions.** The plan explicitly skips regeneration even though `AGENTS.md` requires regenerating `String+Localization.swift`, and pruning runtime string keys has no compiler protection ([AGENTS.md](/Users/udormphon/Developer/QuaraMoney/AGENTS.md:90)).
    Fix — Regenerate the localization accessor and retain old keys unless an exact repo-wide reference audit proves they are unused.

17. **Verification is far too narrow for the new financial projections.** Testing only the monthly helper leaves overlap, missing rates, completion transitions, chart baselines, duplicate editing, persistence failures, and completed-goal contributions unprotected.
    Fix — Add deterministic unit/integration tests for each projection and boundary above, plus at least one UI smoke test covering create-edit-delete navigation.

18. **The plan adds more main-thread recomputation without a data strategy.** Full transaction arrays, nested budget scans, conversion, and chart aggregation will run from view rendering and repeat on unrelated state changes.
    Fix — Compute one cached observable snapshot per screen, refresh it on data/rate changes, and move large scans to a private context using persistent IDs and generation-checked tasks.

VERDICT: REVISE
### Claude's response (Rev 2)
Accepted 1–17 in full or with a design choice; 18 accepted proportionately.
- (1) Headline redefined: canonical total budget when one exists (list's oldest-createdAt canonicalization), else union-of-categories spending vs summed monthly-equivalent limits — no per-budget summing, no double count. Known residual limit-overlap for two budgets tracking the same category documented (already needs-attention).
- (2) Biweekly ×26/12 added; every enum case enumerated; injected date/calendar for tests.
- (3) New logic named honestly: `PlanOverviewMetrics` builder in Services, pure + unit-tested, date-range-scoped fetch (not spendingByBudget, not whole-table @Query).
- (4) Savings card states defined: active-goals headline kept (deliberate: card = "what I'm working toward"), plus explicit zero-state and a distinct "All goals completed / lifetime saved" state — no 0/0 render. Rejected folding completed goals into the active headline.
- (5) `SavingsGoalReconciler` made the single authority for all savings math.
- (6) All new aggregates use `convertOrNil` + exclusion + partial-data footnote; 1:1 fallback banned in Plan aggregates.
- (7) Chart opening balance = stamped starting balance + all pre-window ledger rows; final bar ties to reconciler total.
- (8) SavingsContributionSheet gains locked-goal mode (picker hidden/locked when goal preselected); completed-goal contribution/withdrawal tested.
- (9) Real field-parity matrix from an audit of all four forms: templates create-only, linked wallet added to edit (was Add-only), alert UI standardizes on BudgetAlertMode picker; no invented description/priority fields.
- (10) Convert / Keep number / Cancel dialog on currency change for BOTH forms; Convert disabled when rate missing.
- (11) One explicit throwing save path per form: stamp sync metadata, do/catch save, .dataDidUpdate only on success, form stays open on failure. Scoped to the new forms, not an app-wide try? audit (out of scope).
- (12) Edit-mode duplicate check excludes the edited budget's id, same canonicalization as list.
- (13) Delete-from-detail specified: confirm → SoftDeleteService + save → dismiss form + pop detail via onDeleted chain.
- (14) Shared relevance predicate extracted; FilteredTransactionsDetailView gains explicit excludeFromReports/archived-wallet flags defaulting to current behavior for existing call sites.
- (15) Suggestion results generation-tokened in the new form; engine untouched.
- (16) String+Localization.swift regenerated per repo convention; keys pruned only with grep-proven zero references.
- (17) Verification expanded: deterministic unit tests per projection/boundary (overlap, biweekly, missing rates, completion transitions, chart baseline, dup-edit self-exclusion, currency-change outcomes, save-failure). Scripted XCUITests explicitly rejected (no existing UI-test infra; navigation flows covered by a defined manual smoke matrix) — logged as a scope decision, not an oversight.
- (18) Overview computes one cached snapshot via the established generation-checked, visibility-gated pattern from date-scoped fetches. Rejected building new background stores for list/detail screens: per-budget own-currency list math is the existing calculator on scoped data, and detail screens operate on one budget/goal — proportionate to the app's current perf patterns.

## Round 2 — Codex

The revision addresses most prior findings, but several material data-correctness and lifecycle issues remain.

1. **The category-union fallback still has a dishonest denominator.** Spending is de-duplicated, but overlapping category budgets still duplicate limits; contrary to the plan, existing needs-attention logic flags only duplicate total budgets, not overlapping category budgets ([BudgetListView.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Views/Analysis/BudgetListView.swift:30)).
   Fix — When category scopes overlap, omit aggregate `X of Y` progress and show calendar spending plus the exact on-track count.

2. **“Failure-aware everywhere” contradicts the chosen calculator APIs.** Own-currency rows still require FX when a transaction currency differs from its budget, and `spendingByBudgetCurrency` uses the unsafe 1:1 fallback ([BudgetCalculator.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/BudgetCalculator.swift:127)).
   Fix — Add a Plan-specific per-budget projection returning amount plus `hasMissingRate`, using `convertOrNil`, and use it for lists, details, charts, and on-track counts.

3. **The reconciler is still not the single savings authority.** The plan explicitly reuses `remainingAmount` and `suggestedMonthlyContribution`, but both call `totalSaved`, as does `isOnTrack`, bypassing `SavingsGoalReconciler` ([SavingsGoal.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/SavingsGoal.swift:111)).
   Fix — Introduce `SavingsGoalMetrics` computed from one reconciled amount and use it for remaining, monthly target, progress, completion, and behind status.

4. **The chart cannot guarantee its final bar equals the reconciler total.** The reconciler includes every eligible row regardless of date, while transactions may be future-dated; the plan’s six-month window omits such rows, and withdrawal flooring semantics are unspecified.
   Fix — Define future rows explicitly—preferably a “Future” bucket—and accumulate signed raw balances while applying `max(0, rawBalance)` only to each displayed point.

5. **The cached overview misses required invalidation events.** It observes rate refresh but not `.preferredCurrencyDidChange`, calendar-day/month rollover, timezone changes, or foreground re-entry, so amounts and periods can remain stale.
   Fix — Refresh on preferred-currency change, `NSCalendarDayChanged`, significant-time change, and every transition to an active scene.

6. **The earlier performance issue is fixed only for the overview.** Budget list/detail and savings detail still lack a snapshot strategy and can retain whole-table queries plus repeated chart/row aggregation.
   Fix — Specify generation-checked, date-scoped snapshot loaders for every redesigned list/detail that performs nontrivial ledger aggregation.

7. **`PlanOverviewMetrics` is described as both pure and responsible for fetching.** A fetch-owning SwiftData service is actor-bound and not a pure deterministic builder; passing models into detached work would violate repository concurrency rules.
   Fix — Split it into a private-context `PlanOverviewLoader` and a pure `PlanOverviewMetrics.compute(from: valueSnapshots)` function returning a `Sendable` result.

8. **Save failure handling is not transactional.** After mutating or tombstoning a model, `modelContext.save()` can fail while the changed object remains in context and may autosave later despite Cancel.
   Fix — Capture and restore original fields/tombstone state on failure, remove failed inserts, and inject the persistence boundary so these rollback paths are testable.

9. **Canonical total selection remains under-specified.** “Monthly preferred” does not define which budget wins when no monthly total exists, and equal timestamps lack a stable tie-breaker.
   Fix — Define a total ordering such as period priority → `createdAt` → UUID and unit-test it.

10. **The localization regeneration step has no executable path.** The repository contains only `Scripts/check_missing_keys.py`; no generator for `String+Localization.swift` is present.
    Fix — Name the actual external generator command or add a deterministic repository script and verify it produces no unrelated diff.

VERDICT: REVISE
### Claude's response (Rev 3)
All 10 accepted, three reshaped:
- (1) Overlap in the category-union path now degrades the headline (spending + on-track only, no "of Y", no bar) — adopted Codex's fix verbatim; corrected my false claim that needs-attention covers category overlaps.
- (2) New `BudgetSpendingProjection` (spent + hasMissingRate, convertOrNil) is the only per-budget math the new screens use; legacy 1:1-fallback APIs untouched for old callers.
- (3) New `SavingsGoalMetrics` from the reconciler Result; model helpers totalSaved/remainingAmount/suggestedMonthlyContribution/isOnTrack banned from redesigned UI.
- (4) Chart: signed raw accumulation, max(0,·) per displayed point only, explicit trailing "Upcoming" bucket for future-dated rows — series always ties to the stat card.
- (5) Invalidation set completed: preferred-currency change, NSCalendar.dayChanged, significant-time/timezone change, scene-active, plus the existing triggers.
- (6) Scoped generation-checked loaders specified for budget list (union of current periods) and both details (single period / single ledger); savings list rows stay on the per-goal ledger relationship (bounded) — proportionate, per existing app patterns.
- (7) Split into context-bound PlanOverviewLoader + pure PlanOverviewMetrics.compute(from: valueSnapshots) — matches WalletBalanceStore pattern and repo concurrency rules.
- (8) Transactional saves: forms edit local @State, apply-at-save, restore captured values on failed save (create: delete insert; delete: un-tombstone), injectable seam for tests.
- (9) Canonical total ordering fully specified: period priority (monthly→weekly→biweekly→quarterly→yearly) → createdAt → UUID, unit-tested.
- (10) Reshaped: rather than inventing a generator, new UI uses `.localized` keys exclusively (existing Plan-tab convention), so no regeneration is needed; EN/KM parity proven via Scripts/check_missing_keys.py; L10n constants only pruned-around, never hand-edited. A generator script is explicitly out of scope.

## Round 3 — Codex

Rev 3 fixes most Round 2 findings, including overlap degradation, safe projection intent, savings metrics, future chart rows, loader/compute separation, rollback behavior, canonical ordering, and overview invalidation. Material gaps remain:

1. **Missing FX is still treated as merely “partial,” when status becomes unknowable.** Excluding an unconverted expense can falsely mark a budget on track; excluding a savings row can falsely classify a goal as active or incomplete.
   Fix — Model progress/completion as determinate or indeterminate; hide progress/on-track claims and exclude indeterminate items from `N of M` classifications.

2. **The budget-list fetch bound is false.** Ended custom one-offs may be years old, so their union is not bounded by the yearly window; fetching only current-period data would produce zero or incomplete final results.
   Fix — Fetch disjoint ranges for every budget in the selected segment, including each ended custom range, without collapsing them into an arbitrarily broad union.

3. **The list loader omits state-dependent invalidation.** Its fetch scope depends on “listed budgets,” but the stated invalidation set excludes segment and search changes.
   Fix — Include selected segment and relevant filter/search state in the generation request key, or load projections independently of presentation filtering.

4. **Savings relationships are not bounded.** A long-lived goal can have arbitrarily many linked transactions, and recomputing every goal’s all-time ledger in list rendering preserves the prior performance problem ([SavingsGoal.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/SavingsGoal.swift:45)).
   Fix — Give the savings list a cached, private-context snapshot loader that computes all-time per-goal metrics once per invalidation.

5. **Time invalidation is specified only for overview and budget list.** Savings behind status/monthly target and budget-detail left-per-day can become stale across midnight, timezone changes, or foregrounding.
   Fix — Apply one shared Plan invalidation policy to every metrics-driven overview, list, and detail screen.

6. **Budget See All still violates the safe-FX guarantee.** Extending result-set flags does not change `FilteredTransactionsViewModel`’s summary total, which still uses `TransactionProcessor.calculateTotal` and its 1:1 fallback ([FilteredTransactionsViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/FilteredTransactionsViewModel.swift:176)).
   Fix — Add an opt-in safe-conversion policy and partial-data state to `TransactionFilterConfig`, preserving existing defaults for other callers.

7. **Canonical total selection accepts invalid budgets.** Period priority can select a zero-limit or otherwise needs-attention monthly budget over a valid lower-priority total budget, yielding an unusable headline.
   Fix — Select only valid canonical candidates; if none exist, render a setup/attention state without aggregate progress.

8. **Localization still directly contradicts repository instructions.** `AGENTS.md` requires regenerating `String+Localization.swift` whenever strings are added, regardless of whether call sites use `.localized` ([AGENTS.md](/Users/udormphon/Developer/QuaraMoney/AGENTS.md:90)).
   Fix — Add/use a generator, or obtain explicit approval to change the repository convention and update `AGENTS.md`; declaring generation out of scope is not compliant.

VERDICT: REVISE
### Claude's response (Rev 4)
All 8 accepted; #8 resolved by doc-fix rather than generator:
- (1) Determinacy modeled first-class: every projection carries isDeterminate; indeterminate items make no on-track/behind/completed claims and are excluded from N-of-M ("· K unknown" shown).
- (2) List loader fetches each budget's own period range as its own bounded range (incl. ended customs); no collapsed min-to-max union.
- (3) Loader generation requests keyed on selected segment; search filters in-memory only, never refetches.
- (4) Savings list gets a cached private-context snapshot loader computing all-time per-goal metrics once per invalidation.
- (5) PlanRefreshPolicy: one shared invalidation contract (data/rates/preferred-currency/language/dayChanged/significant-time/scene-active) applied to all five screens.
- (6) TransactionFilterConfig gains an opt-in safe-conversion policy + partial-data state for the summary total; defaults preserved for existing callers.
- (7) Canonical selection filters to valid candidates (limit > 0, not needs-attention); no valid total ⇒ attention/setup state without aggregate progress.
- (8) Verified AGENTS.md:90 — the regeneration bullet is stale against the codebase's actual practice (entire Plan tab + Pro Analytics ship `.localized` keys with no L10n constants; repo has no generator script). Resolution: comply-by-correction — this PR amends the AGENTS.md/CLAUDE.md bullet to document the real two-path convention and proves EN/KM parity via Scripts/check_missing_keys.py. Rejected inventing a generator script (scope creep for a UI redesign; rejected silently ignoring the doc too).

## Round 4 — Codex

Rev 4 addresses the prior eight findings. New implementation-level problems remain:

1. **The background savings loader cannot use the stated authority.** `SavingsGoalReconciler` is `@MainActor`, and its nested `Result` is not `Sendable`; a detached private-context loader cannot legally call it or pass its result across actors ([SavingsGoalReconciler.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/SavingsGoalReconciler.swift:4)).
   Fix — Extract a nonisolated, snapshot-based `SavingsLedgerCalculator` and make both the reconciler and Plan metrics delegate to it.

2. **The overview fetch scope still contradicts lifetime savings totals.** Date-range-scoped budget fetching is correct, but savings totals require every eligible ledger row across all time.
   Fix — Specify separate overview inputs: date-scoped budget transactions and an all-time savings-ledger snapshot scoped by nondeleted goal IDs.

3. **The See All conversion policy is incomplete.** Existing summaries always display preferred currency, while budget detail uses budget currency; highest/lowest sorting also uses unsafe fallback conversion ([FilteredTransactionsViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/FilteredTransactionsViewModel.swift:156)).
   Fix — Add an explicit summary currency plus conversion policy to `TransactionFilterConfig`, and apply it consistently to totals and amount-based sorting with stable placement for indeterminate rows.

4. **Swipe deletion is not covered by the transactional helper.** The rollback discipline is specified only for forms, while redesigned list deletion can retain the current `try?` failure behavior despite being described as consistent.
   Fix — Route both list swipe confirmations and form deletion through the same save/restore helper and error presentation.

5. **One query per budget creates avoidable query amplification.** Standing budgets often share identical or overlapping weekly/monthly/yearly ranges, so the proposed loader may fetch the same transactions dozens of times.
   Fix — Merge overlapping or adjacent ranges without spanning gaps, fetch each merged interval once, then distribute snapshot rows to budgets in memory.

6. **The localization parity script cannot serve as reliable verification.** It hardcodes one developer’s absolute path and only prints mismatches while exiting successfully ([check_missing_keys.py](/Users/udormphon/Developer/QuaraMoney/Scripts/check_missing_keys.py:20)).
   Fix — Make paths repository-relative and exit nonzero when either language is missing keys.

VERDICT: REVISE
### Claude's response (Rev 5)
All 6 accepted:
- (1) Ledger math extracted into nonisolated, snapshot-based SavingsLedgerCalculator; reconciler and Plan metrics both delegate; parity test pins identical results. Semantics unchanged.
- (2) Overview inputs split explicitly: date-scoped budget transaction fetches + all-time savings-ledger snapshot scoped to non-deleted goal IDs.
- (3) TransactionFilterConfig gains explicit summary currency + safe-conversion policy applied to the summary total AND amount-based sorting; indeterminate rows sorted last, shown unconverted; defaults preserved.
- (4) Swipe deletions route through the same transactional save/restore helper and error presentation as form deletes — no try? path survives in redesigned deletion.
- (5) Loader merges overlapping/adjacent ranges (never spanning gaps), fetches each merged interval once, distributes rows in memory; merging unit-tested.
- (6) check_missing_keys.py fixed in this PR: repo-relative paths + nonzero exit on missing keys, then run as a PR check.

## Round 5 — Codex (final round, MAX_ROUNDS reached)

Rev 5 addresses all six prior findings. Three material FX/fetch issues remain:

1. **The savings conversion contract is internally impossible.** The plan promises `CurrencyManager.convertOrNil` everywhere while also promising no-semantic-change parity with `SavingsGoalReconciler`; the former consults fallback rates, while the reconciler requires both currencies in the supplied live-rate table ([SavingsGoalReconciler.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/SavingsGoalReconciler.swift:57)).
   Fix — Preserve the reconciler’s strict live-rate semantics in `SavingsLedgerCalculator`, and describe the common guarantee as “rate-checked, never 1:1 fallback” rather than universal `convertOrNil`.

2. **`convertOrNil` is not fully rate-safe.** It validates only `sourceRate > 0`; a zero or invalid target rate succeeds and converts the amount to zero ([CurrencyManager.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Managers/CurrencyManager.swift:220)).
   Fix — Require both rates to be finite and greater than zero, with tests for zero, negative, NaN, and infinite values.

3. **Archived transactions can be lost before the shared predicate runs.** The natural shared descriptor defaults to `excludeArchivedWallets: true`, contradicting the Plan rule that archived-wallet spending is included ([TransactionProcessor.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/TransactionProcessor.swift:150)).
   Fix — Require Plan budget loaders to fetch with `excludeArchivedWallets: false` and add an end-to-end loader test using an archived source wallet.

VERDICT: REVISE
### Claude's response (Rev 6, final)
All 3 accepted and incorporated:
- (1) FX guarantee rephrased as "rate-checked, never 1:1 fallback": budgets via hardened convertOrNil, savings ledger keeps the reconciler's strict live-rate-table semantics — parity preserved by construction, contradiction removed.
- (2) convertOrNil hardened in this PR: both source AND target rates must be finite and > 0; tests for zero/negative/NaN/infinite on both sides.
- (3) Every Plan budget fetch passes excludeArchivedWallets: false explicitly (shared descriptor default would drop archived rows pre-predicate); end-to-end loader test with an archived source wallet added.

### Resolution
MAX_ROUNDS=5 reached without a formal APPROVED. This is not a positional deadlock: every finding in all 5 rounds (18+10+8+6+3 = 45) was accepted (some reshaped, each with logged reasoning); the final 3 are incorporated in Rev 6 and no counter-positions remain open. The cap simply expired before a re-review could confirm. Handed to the user for sign-off per the skill's no-fake-convergence rule.
