# Plan Review Log: Fix budget↔category linkage (collapse to join-only)
Act 1 (grill) complete — plan locked with the user. MAX_ROUNDS=5.
PLAN_FILE=PLAN-budget-category.md

## Act 1 — Grill summary (decisions locked)
- **Cloud inspection: approved.** Read-only audit of live project
  `czhkvtmpebeowipawqjk` proved the data is clean and already join-only
  (`category_id` NULL on every budget; multi-cat budget holds 3 valid, live,
  non-duplicate join categories). No cloud pollution, no migration needed.
- **Repro: one device, after sync round-trip.** Cloud stays at 3 while local shows
  1 → local pull-side reduction never pushed back.
- **Fix approach: collapse to join-only** (join table = single source of truth).
- **Scalar write: stop writing `category_id` (always NULL); keep it as a read-only
  legacy fallback. Keep the column (no DDL).**
- **Verification: fix robustly now + DEBUG logging; verify by repro after.**

Defects identified: Bug A (partial repair only rescues cloud-empty), Bug B (pull
`compactMap` silently drops unresolved join categories = data-loss), Design C
(dual-representation fragility). `dedupeCanonicalCategories` and `purgeForeignRows`
both already re-point the multi-category join correctly (not the culprit).

## Round 1 — Codex

The plan fixes the `compactMap` symptom but leaves the underlying sync protocol unsafe. Material findings:

1. **The retained push sequence has a lost-wakeup race.** The parent is upserted before join deletion/insertion; another device can pull during that gap, advance the budget cursor, then ignore subsequent join-table Realtime signals because `pullBudgets` returns when no parent row changed ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1186), [SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1850)).

   Fix: Replace parent upsert plus delete/insert with one transactional RPC that publishes the parent revision only after the complete join set is installed.

2. **The claim that parent LWW arbitrates join edits is false.** Both devices can pull the same base revision, unconditionally upsert the parent, and interleave their separate join rebuilds; the final parent and final join set need not come from the same writer.

   Fix: Add a category-set revision and perform a server-side compare-and-swap of the parent and joins in one transaction.

3. **“Leave it to re-pull next cycle” cannot work.** An unresolved budget still advances the table-wide cursor; when the missing category arrives later, the unchanged budget is not fetched again ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1959)).

   Fix: Persist unresolved cloud IDs per budget and retry them after every category pull, or reconcile join sets independently of the budget delta cursor.

4. **Preserving local state can conceal a genuine cloud removal.** If local is `{A,C}` and cloud is `{A,X}` with `X` unresolved, preserving local retains `C`, which cloud explicitly removed; a later unrelated local edit can push `C` back and overwrite the cloud.

   Fix: Keep the authoritative cloud ID set separately from temporarily displayed local relationships and prohibit pushing the preserved fallback set.

5. **The pull matrix contradicts itself.** An empty cloud set is “fully resolved” because `0 == 0`, so the first rule says clear it while the third says preserve and repair it ([PLAN-budget-category.md](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:90)).

   Fix: Define precedence explicitly, with `.total` clearing immediately and `.categories + empty` handled only from an atomic, revision-matched snapshot.

6. **The empty-set repair can amplify the delete/insert gap.** A reader observing the temporary empty join can mark its stale local set dirty and push it over the writer’s intended selection.

   Fix: Eliminate externally visible intermediate join states before retaining any automatic “repair cloud” behavior.

7. **Tombstones are not unresolved IDs.** Category deletion is soft, so the cloud join remains because `ON DELETE CASCADE` only handles hard deletion; treating that known tombstone as unresolved can permanently block unrelated valid cloud removals ([SoftDeleteService.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/SoftDeleteService.swift:61), [schema.sql](/Users/udormphon/Developer/QuaraMoney/supabase/schema.sql:212)).

   Fix: Classify IDs as live, known-tombstoned, or absent; apply tombstones as authoritative removals and detach/clean their budget joins.

8. **Normalization loses data when both legacy representations are populated.** `effectiveTrackedCategories` prefers a nonempty join, so a different scalar category is discarded when normalization clears the scalar ([PLAN-budget-category.md](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:63)).

   Fix: For category-targeted legacy rows, normalize the UUID-deduplicated union of scalar and join values; for explicit total rows, clear both.

9. **The proposed launch placement is not actually before first push.** Signed-in account maintenance currently runs only after account settlement/initial sync, so adding normalization to that “ensure” path does not establish the stated ordering ([QuaraMoneyApp.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/QuaraMoneyApp.swift:643)).

   Fix: Put any required normalization inside `syncNow`, after account reconciliation and pulls but immediately before budget push.

10. **A storage-only migration is incorrectly promoted into a semantic multi-device edit.** Marking every normalized budget dirty and bumping its device-clock timestamp can make stale local linkage beat a newer remote selection.

   Fix: Do not mark storage-only local normalization dirty; convert legacy cloud scalars server-side or use revision-checked writes only when cloud content truly changes.

11. **The UserDefaults gate is underspecified and unsafe.** A global flag can skip work after account switching, store recovery, or database replacement; the repository already has an owner/version-scoped marker pattern ([PlanDataMaintenance.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/PlanDataMaintenance.swift:13)).

   Fix: Either run the cheap idempotent pass every safe cycle or use an owner-and-store-version marker committed only after the database save succeeds.

12. **Dedupe still races the subsequent budget pull.** Dedupe rewrites relationships and stamps a device timestamp before `pullBudgets`; clock skew can cause the pull either to undo the rewrite or incorrectly skip newer cloud state ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:622), [CategoryCatalog.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/CategoryCatalog.swift:329)).

   Fix: Run dedupe after all relationship-bearing pulls and immediately before pushes, with category-set revision tests.

13. **The push does not snapshot relationships with the parent DTO.** Category IDs are read from live SwiftData objects after the parent network await, so an edit during that await can pair old parent fields with a newer join set.

   Fix: Capture immutable parent DTOs and category-ID sets together before the first await and keep edited models dirty for the next cycle.

14. **Stopping scalar writes is not a complete reader/writer sweep.** `BudgetDetailViewModel.budgetIcon` still reads only `budget.category`, while the initializer and dedupe continue assigning the scalar ([BudgetDetailViewModel.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/ViewModels/BudgetDetailViewModel.swift:116), [Budget.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/Budget.swift:166), [CategoryCatalog.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Services/CategoryCatalog.swift:325)).

   Fix: Route every reader through `effectiveTrackedCategories` and remove or explicitly isolate every scalar-writing initializer, dedupe, and rollback path.

15. **The retained SwiftData legacy inverse has dangerous delete semantics.** `Category.budgets` is `.cascade` while the join inverse is `.nullify`, so hard-deleting a category can delete unnormalized scalar-linked budgets but merely detach normalized ones ([Category.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/Category.swift:34)).

   Fix: Make the legacy inverse `.nullify`, introduce the required real SwiftData schema version, and test hard deletion before and after normalization.

16. **The join pull is unpaginated.** It fetches the entire account in one request despite the engine documenting a roughly 1,000-row response cap; truncation would look “fully resolved” and authoritatively shrink later budgets.

   Fix: Paginate joins with stable `(budget_id, category_id)` ordering or query only changed budget IDs through an aggregated RPC.

17. **The schema does not enforce the claimed single source of truth.** It still permits non-null scalar writes, inconsistent `target_kind`, and join `user_id` values not structurally tied to both parent owners ([schema.sql](/Users/udormphon/Developer/QuaraMoney/supabase/schema.sql:185)).

   Fix: Add a migration enforcing join-only writes and owner-consistent composite foreign keys, preferably behind the transactional replacement RPC.

18. **Diagnostics and tests are inadequate for a convergence protocol.** DEBUG-only prints disappear in production, unresolved rows still allow “up to date” status, and the proposed unit tests omit transport ordering, partial failure, cursor retry, tombstones, pagination, and two-device concurrency.

   Fix: Add release-safe structured counters/deferred-sync status plus deterministic fake-transport tests for every adverse ordering and failure boundary above.

A genuinely simpler alternative deserves consideration: since the client currently performs no server-side relational querying over this join, a `category_ids uuid[]` field on `budgets` would make the entire set atomic and inherit parent LWW; if FK integrity is mandatory, keep the join but expose it only through a transactional revisioned RPC.

VERDICT: REVISE
### Claude's response (Round 1 → Rev 2)
**Accepted & incorporated:**
- #3/#4/#5/#7 → rewrote pull as one deterministic precedence rule with three-way
  id classification (live / tombstoned / absent). `.total` clears first; any
  *absent* id → preserve local and **do not** re-push; tombstoned → authoritative
  removal; empty+local+categories → the only re-push (heal) branch. Dropped the
  false "re-pulls next cycle" claim (categories pull before budgets, so absent =
  genuinely missing).
- #8/#9/#10/#11 → **removed the normalization pass entirely.** Reads via new
  `effectiveTrackedCategories` + push-built-from-effective + join-only
  `setTrackedCategories` converge lazily with no migration, no dirty/timestamp
  semantics, no UserDefaults gate, no stale-linkage-beats-remote risk. Union guard
  for scalar+join kept as a test on `effectiveTrackedCategories`.
- #13 → push snapshots `(parentDTO, [categoryID])` before the first await; join
  rebuild uses the snapshot, not re-read live objects.
- #14 → reader/writer sweep: all `budget.category` readers routed through
  `effectiveTrackedCategories`; dedupe's scalar re-point converted to the join set.
- #15 → `Category.budgets` `.cascade` → `.nullify` (+ schema version bump + test).
- #16 → stable ordering on the join fetch (full keyset pagination deferred at this
  scale).
- #18 (partial) → expanded tests (precedence matrix, tombstones, union, sharing,
  delete rule, push shaping). Transport/two-device concurrency tests acknowledged
  as a harness gap / follow-up.

**Rejected / deferred with reason (Claude is arbiter):**
- #1/#2/#6/#17 (transactional/CAS RPC atomicity of the join write) — DEFERRED. The
  reported bug is single-device; concurrent same-budget category edits within the
  sub-second upsert→join gap are near-impossible for a single-user personal-finance
  app; the rewrite is large scope + DDL the user declined. Mitigations adopted
  (#13 snapshot, push-from-effective, idempotent heal). The clean long-term
  options (`category_ids uuid[]` column, or a revisioned RPC) are documented in
  Risks for a future decision.
- #12 (dedupe/pull clock-skew) — pre-existing, not introduced by this change;
  reordering dedupe risks destabilizing other flows. Noted, out of scope.
- #17 DB-level enforcement — deferred with the no-DDL decision; client is now the
  single join-only writer.

## Round 2 — Codex

Rev 2 is substantially better. Removing eager normalization, snapshotting parent/category IDs before the first await, honoring tombstones, and auditing scalar readers are good corrections. I also accept the transactional/CAS deferral for this single-device fix; it is documented honestly and is not itself blocking.

Material issues remain:

1. **Absent IDs can still wedge on one device.** The claim that category pull precedes budgets and therefore absence cannot be transient is false: `runStep` catches a category-pull failure and continues into budget pull ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:589)). The budget cursor then advances, and a later successful category pull does not reconsider the unchanged budget.

   Fix: Before applying budgets, batch-fetch absent category IDs directly from the cloud; if that fetch fails, fail `pullBudgets` before advancing its cursor.

2. **“Preserved sets are never pushed” contradicts “the next real edit re-pushes.”** Any later amount/name edit marks the whole budget dirty, and `pushBudgets` will rebuild joins from the stale preserved local set, potentially restoring categories the cloud removed ([PLAN-budget-category.md](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:129), [PLAN-budget-category.md](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:184)).

   Fix: Add a persisted local `categorySetNeedsSync`/incomplete-resolution state and rebuild joins only after an explicit category edit or resolved authoritative pull—not every budget push.

3. **`needsSync` behavior in the absent branch is ambiguous.** “Do not set `needsSync`” is not equivalent to clearing an older dirty flag after the remote row wins; leaving it true would push the preserved set during the same sync.

   Fix: Specify that remote-wins incomplete pulls set parent `needsSync=false` while retaining the separate category-resolution state described above.

4. **Tombstone authority is overridden by empty repair.** If `cloudIDs` contains only tombstoned categories, `liveResolved` is empty, so the repair subcase preserves local live categories even though the plan says tombstones are authoritative removals ([PLAN-budget-category.md](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:135)).

   Fix: Run empty repair only when `cloudIDs.isEmpty`; a nonempty all-tombstoned cloud set must authoritatively apply an empty live set.

5. **The accessor and its test specify different behavior.** Step 1 says join-first with scalar fallback, while tests require a UUID-deduplicated union when both are populated ([PLAN-budget-category.md](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:70), [PLAN-budget-category.md](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:157)).

   Fix: Choose and document one rule; for legacy safety, use a deterministic UUID-deduplicated union until a cloud pull normalizes the row to join-only.

6. **The SwiftData migration is not implementation-ready.** “Bump the schema version” plus “metadata-only, verify no migration needed” conflicts with the repository’s explicit requirement for a copied `SchemaV2` and migration stage for non-additive changes ([SchemaVersioning.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Models/SchemaVersioning.swift:45)). A bad migration can send the app into store recovery.

   Fix: Specify either a frozen V1 snapshot plus SchemaV2/lightweight stage and an on-disk upgrade test, or defer the delete-rule change until that migration is designed.

7. **Stable ordering does not prevent truncation.** It merely makes the same first ~1,000 rows deterministic; later budgets can still appear to have zero joins and trigger empty repair ([PLAN-budget-category.md](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:144)).

   Fix: Either paginate now using the existing page-size pattern or describe ordering as deterministic-only and retain truncation as an explicit accepted risk.

8. **The tests miss the remaining single-device failure sequence.** Pure precedence tests will not catch category-pull failure → budget cursor advance → category recovery → unrelated budget edit → stale join push.

   Fix: Add one focused injected/fake-fetch regression test for that sequence; it does not require a full multi-device transport harness.

The atomicity deferral is acceptable for the reported scope, but findings 1–4 leave a non-atomicity-independent single-device convergence and cloud-overwrite path.

VERDICT: REVISE
### Claude's response (Round 2 → Rev 3)
**Accepted & incorporated:**
- #1/#7 → pull now scopes the join fetch to the pulled budget IDs (`budget_id IN
  …`, chunked) so it can't truncate across budgets, AND eagerly fetches any
  not-yet-local category referenced by that set; if the targeted fetch throws,
  `pullBudgets` throws so its cursor doesn't advance (retry next sync). Absent ids
  become rare/transient.
- #2/#3 → added persisted additive `Budget.categorySetDirty`. Push rebuilds cloud
  join rows ONLY when it's true (a category edit or empty-repair); name/amount
  edits update the parent row and leave join rows untouched. The absent-preserve
  branch sets parent `needsSync=false` and leaves `categorySetDirty=false`, so a
  preserved set is never pushed. Kills the stale-set-overwrite path (new Bug E).
- #4 → empty-repair gated on `cloudIDs.isEmpty` only; a non-empty all-tombstoned
  cloud set falls to the authoritative branch and clears the local set.
- #5 → `effectiveTrackedCategories` defined as a deterministic UUID-dedup UNION of
  live join + live scalar (one rule for accessor and tests).
- #8 → added an injected-failure regression test (category-pull failure → absent →
  throw/eager-fetch; then unrelated edit → assert no stale join push).

**Deferred with reason:**
- #6 (SwiftData `.cascade→.nullify` delete-rule + SchemaV2) → DEFERRED to its own
  migration. Not the reported bug; not destructively reachable (referenced
  categories are adopted, not hard-deleted; soft-delete never cascades); a botched
  schema migration risks store recovery. This fix now touches NO schema
  (`categorySetDirty` is an additive property). Tracked as a follow-up.

## Round 3 — Codex

Rev 3 is much stronger, and I accept the delete-rule and transactional/CAS deferrals for this fix. Prior findings 3, 4, 5, 6, and 8 are addressed. Findings 1, 2, and 7 are only partially addressed.

Remaining material issues:

1. **The already-corrupted device will not self-heal.** The buggy build likely advanced the budget cursor when it reduced local 3→1. Rev 3 still returns immediately when no parent budget changed, so the clean cloud join of 3 is never reconsidered ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1849)). Eager absent fetching only helps newly pulled parent rows.

   Fix: Add a per-owner Rev-3 protocol marker that resets the budget cursor and performs one full budget/category reconciliation, committing the marker only after success.

2. **`categorySetDirty=false` loses joins during local-source uploads.** Existing local-only budgets receive the additive flag’s false default; first sync to an empty cloud pushes parents but no joins. More critically, “Keep Local” deletes the cloud and `forceAllLocalNeedsSync` sets only `needsSync`, so every restored budget would upload without its categories ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:446)).

   Fix: Set `categorySetDirty=true` for every budget in force-local/republish flows and rebuild joins for previously unowned local-only budgets; add tests for both paths.

3. **Legacy scalar-only pending rows still have a wipe path.** A scalar-only budget with `needsSync=true` and the new flag defaulting false sends `category_id=nil` but does not insert its effective category into the join, contradicting the claimed lazy conversion.

   Fix: During the one-time protocol reconciliation, convert pulled scalar rows through `setTrackedCategories`; for unowned scalar-only rows, explicitly authorize the first join rebuild.

4. **The reader/writer sweep from Rev 2 disappeared.** Current code still has direct scalar behavior such as `BudgetDetailViewModel.budgetIcon` and `CategoryCatalog.merge` assigning `b.category`; the latter marks the parent dirty without setting `categorySetDirty`, so dedupe can fail to repair the cloud join.

   Fix: Restore the explicit grep sweep and change dedupe to call the join-only setter, ensuring it marks `categorySetDirty=true`.

5. **Scoped `IN` queries do not structurally eliminate truncation.** A chunk can still return over 1,000 join rows across several budgets; “handful per budget” is an assumption, not a bound.

   Fix: Paginate every scoped join query with stable `(budget_id, category_id)` ordering, or define a chunk size backed by an enforced maximum category count.

6. **The new tests need the upgrade and force-upload cases.** The injected transient-fetch test is good, but it will not catch an already-advanced cursor or `forceAllLocalNeedsSync` omitting category dirtiness.

   Fix: Add regressions for local 1/cloud 3 with an advanced cursor, first upload of pre-Rev-3 local budgets, and Keep Local after cloud deletion.

The new category-set dirty flag is the correct lightweight alternative to transactional joins, but its initialization and bulk-upload semantics must be completed before implementation.

VERDICT: REVISE
### Claude's response (Round 3 → Rev 4)
**Accepted & incorporated (all 6):**
- #1 (no self-heal — the decisive catch) → added a one-time per-owner
  reconciliation gated by an owner+store-version marker committed after success:
  resets the budgets cursor (`removeObject(forKey: cursorKey("budgets"))`) so the
  clean cloud re-pull heals every reduced `needsSync==false` budget (the user's
  device). New "Bug F" named explicitly.
- #2/#3 (flag init / bulk-upload wipe) → `categorySetDirty` set true for
  `needsSync==true` budgets during the reconciliation (safe: the reduction bug
  leaves rows `needsSync==false`), and `forceAllLocalNeedsSync` now sets it true for
  every Budget. Covers local-only first upload and scalar-only pending rows.
- #4 (reader sweep regressed) → restored as an explicit step; dedupe `merge` scalar
  re-point converted to the join-only setter (also sets the dirty flag).
- #5 (IN not truncation-proof) → scoped join fetch now keyset-paginated with stable
  `(budget_id, category_id)` ordering, chunked.
- #6 → added self-heal, first-upload, and keep-local regression tests.

No new deferrals. Delete-rule and atomicity deferrals stand (Codex accepted both).

## Round 4 — Codex

Rev 4 addresses prior findings 4–6 and most of 1–3:

- Cursor-reset self-heal is now specified and tested.
- Keep Local correctly marks every budget’s category set dirty.
- Local-only/scalar pending uploads are covered.
- Reader/writer sweep and dedupe conversion are restored.
- Scoped join fetching is now genuinely paginated.
- Required regression tests are included.
- Settled deferrals remain non-blocking.

One material flaw remains: the reconciliation still equates `needsSync==true` with category-set intent ([PLAN-budget-category.md](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:150)). That inference is exactly what `categorySetDirty` was introduced to avoid.

A concrete single-device failure:

1. The old bug reduces local categories from 3→1 and leaves `needsSync=false`.
2. Before installing Rev 4, the user edits only the budget name or amount, making `needsSync=true`.
3. Reconciliation sets `categorySetDirty=true`.
4. The full pull sees the newer local parent timestamp and `localChangeWins` returns early before applying the cloud category set ([SyncEngine.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Supabase/SyncEngine.swift:1873)).
5. Push treats the reduced one-category set as deliberate and overwrites the correct cloud set of three.

The plan calls a dirty-reduced row “believed impossible,” but an ordinary parent edit after the reduction creates exactly that state.

Fix: During reconciliation, set `categorySetDirty=true` automatically only for unowned/local-only budgets; for cloud-owned budgets with `categorySetDirty=false`, reconcile cloud categories independently of parent-field LWW—even when newer local parent fields remain dirty.

Add one regression: local categories=1, cloud=3, `needsSync=true` from a name-only edit, `categorySetDirty=false`; reconciliation must retain the local name, restore three cloud categories, and push no stale join rebuild.

VERDICT: REVISE
### Claude's response (Round 4 → Rev 5)
**Accepted — the one remaining flaw, incorporated:**
- Codex's concrete Bug G (name/amount edit after the reduction → `needsSync=true` →
  reconciliation flags dirty → parent LWW suppresses cloud category set → reduced
  set pushed over cloud 3). The `needsSync ⇒ category intent` inference is removed.
- **Structural fix:** pull now splits the per-row apply — parent scalar fields follow
  `localChangeWins`, but the **category set is governed solely by `categorySetDirty`**,
  applied even when the parent row is locally newer. `categorySetDirty==false` ⇒ cloud
  authoritative. The whole-row early `return` on `localChangeWins` is gone.
- Reconciliation now auto-flags `categorySetDirty=true` **only for local-only budgets**
  (no matching cloud row in the full re-pull / `syncUserID != owner`), never from
  `needsSync` on cloud-owned rows.
- Added the exact regression Codex asked for: local cats=1, cloud=3, `needsSync=true`
  from a name-only edit, `categorySetDirty=false` → name retained, categories restored
  to 3, no stale join push.

## Round 5 — Codex (MAX_ROUNDS)

Bug G is resolved in the sync arbitration itself, but not in the real edit flow.

- Material flaw: Rev 5 makes `setTrackedCategories` always set `categorySetDirty = true` ([plan](/Users/udormphon/Developer/QuaraMoney/PLAN-budget-category.md:80)), while every form save—including a name-only edit—unconditionally calls that method ([BudgetFormView.swift](/Users/udormphon/Developer/QuaraMoney/QuaraMoney/Views/Analysis/BudgetFormView.swift:495)). After the reported 3→1 local corruption, a name-only save therefore marks that corrupt category set as intentional; reconciliation preserves it and can push 1 back to the cloud. The proposed regression bypasses this real call path by directly constructing `needsSync == true, categorySetDirty == false`.

One-line fix: Only set `categorySetDirty` when the normalized category UUID set or target kind actually changes, and run the name-only regression through the same mutation helper used by `BudgetFormView`.

VERDICT: REVISE
### Claude's response (Round 5 → Rev 6) — FINAL, MAX_ROUNDS reached
**Accepted & incorporated (single finding, correct):**
- Codex R5: `BudgetFormView.applyFormValues` calls `setTrackedCategories` on every
  save, and Rev 5 made that method unconditionally set `categorySetDirty=true` — so a
  name-only save on an already-reduced budget marks the corrupt set intentional (Bug G
  via the real UI path, which the Rev 5 hand-built regression bypassed).
- Fix: `setTrackedCategories` now sets `categorySetDirty` **only when the normalized
  category-id set or target kind actually changed**. The regression is rewritten to run
  through the real `BudgetFormView` mutation path and assert a name-only save leaves
  `categorySetDirty==false`. Added a change-detection unit test.

## Resolution — MAX_ROUNDS=5 reached; converged (no substantive disagreement)
Findings trajectory: 18 → 8 → 6 → 1 → 1, each accepted or deferred-with-reason.
Codex's final verdict was REVISE, but the Round-5 finding was a single correct
refinement that Claude fully accepted and incorporated — not a tie to break. No
counter-positions remain open. The only items still "open" are the two changes both
parties explicitly agreed to DEFER as out of scope:
  1. `Category.budgets` `.cascade → .nullify` (needs its own SchemaV2 migration).
  2. Full multi-device join-write atomicity (`category_ids uuid[]` column or a
     transactional revisioned RPC).
Both are documented in Risks/Out-of-scope. The single-device reported bug and every
data-loss path found across five rounds are closed by Rev 6. Handing to the user for
the final sign-off.

## Act 3 — Build (Codex builds, Claude verifies)

### Round 1 — Codex build (session 019f7af8-c48e-7761-9e78-394f2f64e86a)
Implemented Rev 6 end-to-end. Files changed (12):
- Budget.swift — `effectiveTrackedCategories` (UUID-dedup union), additive `categorySetDirty`,
  join-only `setTrackedCategories` with normalized change-detection, readers re-expressed.
- SchemaVersioning.swift — registered `categorySetDirty` as additive/lightweight (no stage).
- SyncDTOs.swift — documented `category_id` as pull-only; push encodes nil.
- SyncEngine.swift — BudgetPushSnapshot (captured before await; joins rebuilt only when
  categorySetDirty; finishBudgetPush clears intent only for rebuilt+unchanged snapshots);
  applySyncedBudgetRow (parent scalar LWW split from category-set reconciliation);
  applySyncedTrackedCategories rewritten to the precedence matrix (dirty→preserve;
  total→clear; absent→preserve-no-push; empty→repair-push; else authoritative w/ tombstones);
  paginated scoped join fetch with keyset + stall guard; eager absent-category fetch that
  throws before cursor advance; one-time owner+store-version reconciliation resetting the
  budgets cursor + flagging only local-only budgets; forceAllLocalNeedsSync flags budgets.
- CategoryCatalog.swift — dedupe merge re-points via the join-only setter.
- PlanDataMaintenance.swift — owner-scoped reconciliation marker (needs/commit).
- PlanMetricsLoaders.swift, BudgetDetailViewModel.swift — reader sweep to effective accessor.
- BudgetFormView.swift — static shared `applyFormValues` (prod + tests); snapshot captures
  `categorySetDirty`; init seeds from effective.
- BudgetCategoryLinkageTests.swift (NEW, 18 tests) + SyncEngineHardeningTests/PlanReworkTests updates.

### Claude's verdict — Round 1: ACCEPTED (no fix rounds needed)
Read the full diff. Spec fidelity is exact on every hard point:
- Non-goals respected: Category.swift UNMODIFIED (no delete-rule change); nothing under
  root supabase/ touched; no schema/RPC/array-column.
- Parent/category decoupling correct: `guard !budget.categorySetDirty` gates category
  application; parent fields apply only when `!parentLocalWins`; Bug-G resolved in the real
  arbitration, and the regression exercises the actual BudgetFormView.applyFormValues path.
- Reader sweep complete (budgetIcon, PlanMetricsLoaders, displayName, needsAttention,
  trackedCategoryIds/Infos all via effectiveTrackedCategories). Rollback snapshot captures
  categorySetDirty (no dirty-state leak on cancel).
- Proof (Claude re-ran, not Codex's paste): focused suites GREEN —
  BudgetCategoryLinkageTests 18/18, SyncEngineHardeningTests all pass, PlanReworkTests all pass.
- The 7 TransactionSuggestionEngineTests failures are PRE-EXISTING: independently reproduced
  identically on clean HEAD (stash) with none of this change present; they touch none of the
  changed files (time/weekday/location-dependent baseline).
No deviations. Awaiting human commit sign-off.
