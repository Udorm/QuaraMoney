# Plan: Fix budget↔category linkage (collapse to join-only, harden sync)
_Locked via grill — by Claude + Udorm · 2026-07-19 · Rev 6 (post Codex Round 5 — MAX_ROUNDS)_

## Goal
Budgets can track one or many expense categories. Two parallel storage
representations exist today — the scalar `Budget.category` (single) and the to-many
join `Budget.categories` (multi) — mirrored into two cloud shapes
(`budgets.category_id` + a `budget_categories` join table). Keeping these
consistent across model, sync push, sync pull, dedupe, and the form has produced
three rounds of bugs; the live one is "pick multiple categories → resets to one
after a sync round-trip." A read-only audit of the live cloud
(`czhkvtmpebeowipawqjk`) proved the cloud data is **clean and already join-only**
(`category_id` NULL on every budget; the one multi-cat budget correctly holds 3
valid, live, non-duplicate join categories), so the defect is client-side and the
affected device holds a *reduced local copy while the cloud is still correct*. We
**collapse to a single representation — the `categories` join is the sole source of
truth**, make the scalar a read-only legacy fallback, and — the central idea —
**reconcile a budget's category set independently of the parent-row last-write-wins**:
parent scalar fields (name/amount/period) follow the existing LWW, but the category
set is governed solely by a new `categorySetDirty` flag (`false` ⇒ no local category
intent ⇒ the cloud set is authoritative, even when the parent row is locally newer).
A **one-time per-owner reconciliation resets the budgets cursor** so the clean cloud
re-heals already-reduced devices. Multi-device join-write *atomicity* and the
`Category.budgets` `.cascade` delete-rule fix are explicitly deferred (Codex
accepted both); this fix touches no schema beyond one additive property.

## Context established by the grill (facts)
- **Local model** (`Models/Budget.swift`): `category: Category?` (inverse
  `Category.budgets`, `.cascade`) and `categories: [Category]?` (distinct inverse
  `Category.multiCategoryBudgets`, `.nullify`). The distinct inverse (`23a9c0d`)
  lets budgets share a category without SwiftData detaching it. `syncUserID: UUID?`
  is set by pull (`b.syncUserID = row.user_id`, ~L1904) — a nil value marks a
  budget never claimed by the current cloud account.
- **Cloud** (`supabase/schema.sql`): `budgets.category_id` + table
  `budget_categories(budget_id, category_id, user_id)` PK `(budget_id, category_id)`;
  no cross-budget uniqueness on `category_id`; join table has **no timestamp / no
  LWW**; responses capped (~1000 rows).
- **Cursors**: per-table UserDefaults key `cursorKey(table)`; `fetchChanged(table)`
  returns rows past the cursor; resettable via `removeObject(forKey:
  cursorKey("budgets"))` (pattern used ~L804). Join fetch currently uses no cursor,
  whole-account (~L1852).
- **Push** (`pushBudgets`, ~L1165): parent DTOs → `upsert` → second pass on live
  objects → `DELETE`+`INSERT` joins from `b.categories`. `finishPush` clears
  `needsSync` unless re-edited during the await.
- **Pull** (`pullBudgets`, ~L1849): whole-account `joinMap`; per id
  `compactMap { fetchByID }` (**silently drops unresolved**); scalar fallback;
  `applySyncedTrackedCategories` (repairs only "cloud empty"). Row-level
  `localChangeWins` (~L1873) currently returns early for the **whole** row,
  including the category set — this is the coupling Rev 5 breaks.
- **Sync order** (`syncNow`, ~L607+): … pull categories → dedupe → … → **pull
  budgets** → … → **push budgets**. `runStep` (~L589) catches a failed step and
  continues, so a failed category pull still advances into budget pull. Deletes are
  soft; a soft-deleted category keeps its cloud join row → resolves locally as a
  **tombstone**.
- **Keep-local / republish**: `forceAllLocalNeedsSync` (~L446) flags every row
  (incl. Budget) `needsSync=true`; touches no category-set state.
- **Repro (confirmed)**: one device; reduction after a sync round-trip; cloud stays
  at 3 while local shows 1; the reduced row is `needsSync=false` and its cursor has
  advanced (never re-pulled).

## Defects being fixed
- **Bug B (silent drop / data-loss):** pull drops unresolved join ids.
- **Bug A (partial repair):** repair rescues only "cloud empty."
- **Design C (dual-representation fragility).**
- **Bug E (push amplification / stale-set overwrite):** a parent edit rebuilds cloud
  joins from the current local set.
- **Bug F (no self-heal):** the reduced device is `needsSync=false` with an advanced
  cursor.
- **Bug G (LWW couples parent + category set):** a name/amount edit after the
  reduction makes the row `needsSync=true`, so parent LWW suppresses the cloud
  category set and the reduced set gets treated as authoritative.

## Approach
1. **Model — join is the single source of truth** (`Models/Budget.swift`):
   - Add `var effectiveTrackedCategories: [Category]` = **UUID-deduplicated union**
     of the live join set and the live scalar (deterministic order, dedup by `id`).
     The one accessor behind every reader and the push.
   - Re-express `trackedCategoryIds`, `trackedCategoryInfos`, `displayName`,
     `needsAttention` on it.
   - `setTrackedCategories(_:targetKind:)`: `.categories` → store selection in
     `categories`, `category=nil`; `.total` → both nil. **Set
     `categorySetDirty=true` only when the change is real** — i.e. the normalized
     category-id set (`Set(selected.map(\.id))`) differs from the current
     `Set(effectiveTrackedCategories.map(\.id))`, or `targetKind` differs from the
     current `targetKind`. A no-op re-assignment (e.g. a name-only form save that
     re-passes the same set) must leave `categorySetDirty` unchanged. This is
     essential: `BudgetFormView.applyFormValues` calls this method on **every** save,
     so an unconditional flag would let a name-only save on an already-reduced budget
     mark the corrupt set as intentional and push it over the cloud (Codex R5 / Bug
     G in the real UI path).
   - **Add `var categorySetDirty: Bool = false`** — persisted **additive** property.
     Semantics: *"the local category set is a deliberate local choice; push it and
     treat it as authoritative over the cloud set."* `false` ⇒ no local category
     intent ⇒ the cloud set wins. Set by `setTrackedCategories`, the empty-repair
     pull branch, `forceAllLocalNeedsSync`, and the reconciliation (local-only rows
     only). Cleared by the authoritative pull branch and after a successful join
     push. Default `false`.
   - Keep `category` read-only legacy fallback; never written by app logic. Legacy
     `convenience init(…category:…)` documented legacy-only.
2. **Reader/writer sweep**: grep every `Budget` `.category` read → route through
   `effectiveTrackedCategories`/`trackedCategoryIds` (`BudgetDetailViewModel.
   budgetIcon` ~L116 and filter ~L41, `PlanMetricsLoaders` ~L344). Change
   `CategoryCatalog.merge`'s scalar re-point to the **join-only**
   `setTrackedCategories(unionOf(effective, winner), .categories)` (also sets the
   dirty flag so the healed set pushes).
3. **Push** (`pushBudgets`), parent/join decoupled:
   - Snapshot **before the first `await`**: per pending budget
     `(parentDTO with category_id: nil, categorySetDirty, [categoryID] from
     effectiveTrackedCategories)`.
   - `upsert` parents; rebuild cloud join rows (delete-then-insert from the snapshot
     id set) **only when snapshot `categorySetDirty == true`.** Parent-only dirty
     budgets leave cloud joins untouched (fixes Bug E). Clear `categorySetDirty` on
     a successful rebuild (guarded like `finishPush`).
4. **Pull — decouple parent LWW from category-set reconciliation** (the Bug G / Rev 5
   core; `pullBudgets` + rewritten apply):
   - **Bounded, paginated join fetch**: `where budget_id IN (chunk of pulled ids)
     order by budget_id, category_id`, keyset-looping each chunk until a page
     `< pageSize` (truncation-proof, smaller).
   - **Eagerly resolve absent categories**: for cloud ids with no local `Category`,
     directly fetch+upsert them before classification; if that fetch **throws**, let
     `pullBudgets` throw (cursor not advanced).
   - Split the per-row apply into two independent decisions:
     - **Parent scalar fields** (name/amount/period/…): compute
       `parentLocalWins = localChangeWins(needsSync, localUpdatedAt, remoteUpdatedAt)`;
       apply cloud parent fields only when `!parentLocalWins`. (No longer an early
       `return` for the whole row.)
     - **Category set** — governed by `categorySetDirty`, **not** by
       `parentLocalWins`:
       - `categorySetDirty == true` → local set is authoritative: do not apply the
         cloud set; leave it to push.
       - `categorySetDirty == false` → the cloud set is authoritative; apply it via
         the precedence below **even if `parentLocalWins`** (this is what heals a
         reduced budget carrying a stray name/amount edit — Bug G).
   - **Category-set precedence** (when `categorySetDirty == false`), `cloudIDs =
     joinMap[row.id]` if it has joins else `row.category_id.map{[$0]} ?? []`; classify
     each id **live / tombstoned / absent**:
     1. `targetKind==.total` → clear both.
     2. any **absent** remains → preserve local; do not set `categorySetDirty`;
        DEBUG-log counts.
     3. `cloudIDs.isEmpty` **and** local non-empty **and** `targetKind==.categories`
        → empty-repair: preserve local live; `categorySetDirty=true`; bump
        `updatedAt`; mark for push.
     4. else (all live/tombstoned) → **authoritative**:
        `setTrackedCategories(liveResolved, targetKind)`, then override
        `categorySetDirty=false`. A non-empty all-tombstoned set clears (tombstones
        honored).
   - **`needsSync` bookkeeping** (kept coherent across the split): after applying,
     set `needsSync=false` **only when** `!parentLocalWins` **and** the category set
     was not left dirty; if `parentLocalWins`, keep `needsSync=true` so the parent
     name/amount still pushes (its join rows stay untouched because
     `categorySetDirty==false`).
5. **One-time self-heal reconciliation** (Bug F), gated by an **owner+store-version
   marker committed only after a successful sync** (`PlanDataMaintenance`-style):
   - Reset the budgets cursor so `pullBudgets` re-pulls **all** rows and re-applies
     step 4. Because category-set reconciliation is now independent of parent LWW,
     every cloud-owned budget with `categorySetDirty==false` is healed to the cloud
     set — **including one carrying a name/amount edit** (Bug G fixed).
   - Set `categorySetDirty=true` **only for local-only budgets** — those with **no
     matching cloud row in the full re-pull** (equivalently `syncUserID` not equal
     to the current owner) and a non-empty effective set — so their joins upload on
     first push. Cloud-owned budgets are **never** auto-flagged from `needsSync`
     (removes the false `needsSync ⇒ category intent` inference — Codex R4).
6. **Keep-local / republish** (`forceAllLocalNeedsSync`): also set
   `categorySetDirty=true` for every Budget (Keep Local means local is authoritative,
   including its category sets).
7. **Diagnostics**: DEBUG-gated logs in the pull split/precedence, the push
   snapshot/rebuild, and the reconciliation, with counts.
8. **Tests** (`QuaraMoneyTests`, in-memory `ModelContainer`; injectable apply):
   - `setTrackedCategories`: single → `categories==[c1]`, `category==nil`,
     `categorySetDirty==true`; total → both nil.
   - Two budgets share one category → both retain it.
   - `effectiveTrackedCategories`: scalar-only → `[scalar]`; both populated → UUID
     union; tombstoned filtered.
   - Precedence matrix (`categorySetDirty==false`): total→clear; all-live→apply(+dirty
     false); any-absent→preserve(no dirty); all-tombstoned(non-empty)→clear;
     empty+local+categories→repair(+dirty true).
   - **Parent/category decoupling through the REAL edit path (Bug G, Codex R4+R5
     regression)**: start from local categories=1, cloud=3; perform a **name-only
     save via the same mutation helper `BudgetFormView` uses** (`applyFormValues` /
     `setTrackedCategories` with the form's seeded set) — assert the save leaves
     `categorySetDirty==false` (no real set change); then after reconciliation the
     local **name is retained**, categories are **restored to 3**, and push performs
     **no** join rebuild (cloud stays 3). Do NOT hand-construct the flag state — the
     test must exercise the actual form call path.
   - **Change-detection unit test**: `setTrackedCategories` with the same id set and
     same target kind → `categorySetDirty` stays `false`; with an added/removed
     category or a target-kind flip → `categorySetDirty==true`.
   - `categorySetDirty==true` path: local category edit → cloud set NOT applied on
     pull; push rebuilds joins.
   - Push shaping: snapshot from effective (scalar → one join row); parent DTO
     `category_id==nil`; **parent-only dirty budget does NOT rebuild joins** (Bug E).
   - Self-heal (Bug F): local=1 / cloud=3 / `needsSync==false` / advanced cursor →
     reconciliation resets cursor → local==3.
   - First upload of a pre-Rev-5 **local-only** budget (no cloud row) → reconciliation
     flags it → push installs its joins (no wipe).
   - Keep-local after cloud deletion → budgets re-upload with categories.
   - Injected transient category-pull failure → absent id → `pullBudgets` throws
     (cursor not advanced); recovery resolves; a concurrent name edit pushes no stale
     joins.
9. **Cloud**: **no migration** — audit proved data already clean and join-only.

## Key decisions & tradeoffs (bite here)
- **Collapse to join-only; scalar read-only legacy fallback; `category_id` pushed
  NULL; keep the column (no DDL).**
- **Category-set reconciliation is independent of parent-field LWW; driven solely by
  `categorySetDirty`** (Codex R4). `false` ⇒ cloud authoritative even when the parent
  row is locally newer — this is what heals a reduced budget that also carries a
  name/amount edit (Bug G). The false `needsSync ⇒ intent` inference is removed.
- **`categorySetDirty` is set by real change only** (Codex R5): `setTrackedCategories`
  flags dirty iff the normalized id set or target kind actually changed, so a
  name-only save (which still calls the setter) does not falsely mark a reduced set
  intentional. Verified through the real `BudgetFormView` mutation path, not a
  hand-built state.
- **`effectiveTrackedCategories` = UUID-dedup union** (one rule, accessor + tests).
- **Removed the up-front normalization pass** (Codex R1) — lazy convergence.
- **`categorySetDirty` decouples category-set push from parent push** (Codex R2/R3);
  auto-flagged at reconciliation **only** for local-only (no cloud row) budgets, plus
  keep-local and `setTrackedCategories`.
- **One-time cursor-reset reconciliation** heals reduced devices (Bug F); owner+
  store-version marker committed after success (Codex R1/R3).
- **Bounded + paginated per-budget join fetch with eager absent-fetch that fails the
  step on error** (Codex R2/R3).
- **Precedence** explicit; empty-repair gated on `cloudIDs.isEmpty`; tombstones
  authoritative.
- **Push snapshots the join id set with the parent DTO before the await** (Codex R2).
- **DEFER** the `.cascade→.nullify` delete-rule fix and full join-write atomicity —
  reasons in Risks; both accepted by Codex.

## Risks / open questions
- **Detecting "local-only" at reconciliation.** Uses "no matching cloud row in the
  full re-pull" (with `syncUserID != owner` as corroboration). If a genuinely
  cloud-owned budget were misclassified local-only it would push its local set — but
  the full cursor-reset re-pull returns every cloud budget, so a cloud-owned row is
  always matched; the risk is bounded to truly local-only rows. Covered by the
  first-upload and Bug-G tests.
- **Deferred delete-rule fix (`Category.budgets` `.cascade`).** Not reachable in
  current flows; separate SchemaV2-gated change with an on-disk upgrade test.
- **Deferred multi-device join atomicity.** Long-term: `category_ids uuid[]` column
  (atomic, inherits parent LWW, drops the join table) or a transactional revisioned
  RPC. Declined for this fix; documented for a future decision.
- **Additive property migration.** `categorySetDirty` default `false` must need no
  schema stage; verify against `SchemaVersioning`.
- **Dedupe/pull clock-skew** (Codex R2 #12) pre-existing, out of scope.
- **Production observability**: DEBUG-only prints; preserved-incomplete budgets not
  flagged. Accepted (no telemetry infra).

## Out of scope
- `Category.budgets` delete-rule change (deferred, SchemaV2-gated).
- Transactional/CAS RPC or `category_ids uuid[]` migration (deferred; documented).
- Per-row LWW on `budget_categories`; dropping `budgets.category_id`; DB constraints.
- Reordering dedupe; broader Plan-tab v2 UI, savings goals, rollover, notifications.
- Server-side data migration (not needed — cloud verified clean).
