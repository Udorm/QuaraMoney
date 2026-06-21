# QuaraMoney — SwiftData → Supabase Migration

Status: **Phase 0 complete ✅ — starting Phase 1 (auth)**
Owner: Udorm Phon
Last updated: 2026-06-21

### Phase 0 — done & verified
- Supabase project `czhkvtmpebeowipawqjk` (region ap-northeast-2 / Seoul).
- `schema.sql` applied: 15 tables, all **RLS enabled**; `rls.sql` applied (owner
  policies + private `receipts` bucket). Security advisor: **0 findings**.
- App: `supabase-swift` 2.48.0 linked; `SupabaseConfig` / `SupabaseManager` /
  `SupabaseFeatureFlags` (kill-switch, default **off**) added. Secrets via
  gitignored `secrets.local.xcconfig` → `gen-secrets.sh` → gitignored
  `SupabaseSecrets.swift`.
- **Build + full test suite green.** No runtime behavior changed (sync off).

This document is the single source of truth for migrating QuaraMoney from a
local-only SwiftData store to **Supabase** (Postgres + Auth + Storage + Realtime)
with **offline-first bidirectional sync**.

---

## 0. Decisions locked

| Decision | Choice |
|----------|--------|
| Primary goals | Multi-device sync **and** future web/other platforms |
| Offline behavior | **Offline-first + background sync** (SwiftData stays as local cache) |
| Auth | Email + password / magic link (Supabase Auth) |
| Existing user data | **Must be migrated, cannot be lost** — one-time on-device importer |
| Group events | Stay **single-owner** for now (members are labels, not real accounts). Schema leaves room for real sharing later. |

## Open decisions (still needed before some phases)

1. **Realtime** subscriptions now or deferred to Phase 5? (Recommended: deferred.)
2. **Conflict policy** — confirm row-level **last-write-wins** by `updatedAt`. Any
   special rules (e.g. "delete always wins")?
3. **Hosting / region** — Supabase Cloud vs self-host; region for Cambodian users
   (Singapore is nearest on Supabase Cloud).
4. **`supabase-swift` dependency** — adding it breaks the "no third-party deps"
   rule in `CLAUDE.md`. Confirm accepted (then update CLAUDE.md).
5. **Pro gating** (`ProFeatureGate`) — move entitlements server-side or keep local?

---

## 1. Target architecture

SwiftData is **not** removed. It becomes the local cache / offline store.
Supabase becomes the system of record. A new `SyncEngine` bridges them.

```
SwiftUI Views (@Query — unchanged)
      │
ViewModels (writes go to SwiftData — unchanged)
      │
SwiftData (local cache + offline outbox)  ←→  SyncEngine  ←→  Supabase
                                                              ├─ Auth (email / magic link)
                                                              ├─ Postgres + RLS (canonical schema)
                                                              ├─ Storage (receipt images)
                                                              └─ Realtime (Phase 5)
```

**Why:** the 25 `@Query` views and all ViewModels keep working against local
SwiftData with no rewrites. The SyncEngine is the only major new component.

---

## 2. Sync engine design

No official offline-sync SDK exists for `supabase-swift` (it provides Auth,
PostgREST, Realtime, Storage, Functions). Sync is hand-rolled.

### Per-row sync metadata (added to every model + every table)
- `id: UUID` — already client-generated everywhere ✅
- `userId: UUID` — owner
- `updatedAt: Date` — already on Transaction/Wallet; extend to all
- `deletedAt: Date?` — **soft delete / tombstone** (hard deletes cannot sync)
- local-only `syncStatus`: `synced | pendingPush | pendingDelete` (outbox)

### Conflict resolution
Row-level **last-write-wins** keyed on `updatedAt`. One person edits at a time,
so field-level merge is unnecessary.

### Sync loop
1. **Push** `pendingPush` / `pendingDelete` rows (upsert / set `deletedAt`),
   **parents before children** to satisfy FKs.
2. **Pull** `where updated_at > lastSyncCursor` per table; apply LWW into SwiftData.
3. Persist `lastSyncCursor` per table.
4. Triggered on: app foreground, debounced after local writes, pull-to-refresh.
5. Retry with backoff; never block the UI.

### Critical ordering
- Push/insert: wallets, categories → transactions → children.
- Delete: children → parents (reverse).

---

## 3. Postgres schema

Canonical, normalized schema lives in [`supabase/schema.sql`](supabase/schema.sql),
RLS policies in [`supabase/rls.sql`](supabase/rls.sql).

### Type mapping
| SwiftData | Postgres | Notes |
|-----------|----------|-------|
| `UUID` id | `uuid` PK | client-generated, keep |
| `Decimal` amount | `numeric(19,4)` | **never float8** |
| `Int64` minor units | `bigint` | event ledger |
| enum (Codable) | `text` + CHECK | store raw value |
| `[String]` tags | `text[]` | queryable from web |
| `.externalStorage` photoData | Storage bucket + `photo_path text` | no blobs in Postgres |
| `.cascade` | FK `ON DELETE CASCADE` | |
| `.nullify` | FK `ON DELETE SET NULL` | |
| `.deny` (Category→Transaction) | FK `ON DELETE RESTRICT` | |
| `createdAt/updatedAt` | `timestamptz` | trigger backstop on update |

14 models → 14 tables: transactions, wallets, categories, budgets, debts, events,
event_members, event_ledger_transactions, event_ledger_participants,
event_settlement_snapshots, event_wallet_export_records, recurring_rules,
savings_goals, transaction_locations.

---

## 4. Auth & RLS

- Email + password / magic link via Supabase Auth.
- Session tokens stored in **Keychain** (never UserDefaults).
- New product surface: account screen, sign-in/up, password reset / magic-link
  deep-link handling, signed-out empty state, onboarding account step.
- **Every table has RLS**: `using (user_id = auth.uid())` for select/update/delete,
  `with check (user_id = auth.uid())` for insert. Non-negotiable.
- Existing biometric **app-lock stays** — it is a local UX lock, orthogonal to auth.

---

## 5. Receipt images → Supabase Storage

- Private bucket, path `receipts/{user_id}/{transaction_id}.jpg`.
- Storage RLS scoped to the user.
- Row stores the **path**, not the blob. Upload during sync push; download lazily
  and cache locally.

---

## 6. One-time data migration (existing users)

Guarded, idempotent, runs once after first successful sign-in:
1. App update introduces the account step.
2. After auth: stamp every local row with `user_id`, mark `pendingPush`, upload
   receipt images to Storage.
3. Run normal push. Set `didMigrateLocalDataToCloud` flag so it never re-runs.
4. **Do not delete the local store** until first full sync succeeds.
5. Idempotency comes free from client-generated UUIDs (upsert = same rows).

Test: hundreds of transactions + images, slow connection, app backgrounded
mid-upload, re-launch.

---

## 7. Phased rollout (build + test gate between every phase)

| Phase | Scope | Done when |
|-------|-------|-----------|
| **0** | Supabase project + schema + RLS; add `supabase-swift` (SPM); config plumbing. | Backend live, app still builds |
| **1** | Auth: sign-up/in, Keychain session, account UI, onboarding step. | Users can log in; no sync yet |
| **2** | Sync metadata on all models + `SchemaV2` local migration. | Local store sync-ready; app builds & tests green |
| **3** | SyncEngine push+pull+LWW + Storage receipts. | Two devices stay in sync |
| **4** | One-time importer + heavy testing. | Existing data safely in cloud |
| **5** | Realtime, retries/backoff, observability, polish. | Instant cross-device updates |

---

## 8. Codebase-specific gotchas

1. **`@Query` freshness:** after a pull, write into the same `@MainActor` context
   the views observe (and post `.dataDidUpdate`) or views won't refresh.
2. **`Decimal` fidelity:** encode/decode `Decimal` and `numeric` as **strings**
   end-to-end. JSON-through-`Double` silently corrupts money. (#1 sync bug.)
3. **Soft deletes ripple:** every `@Query` and every service fetch
   (`TransactionProcessor`, `BudgetCalculator`, settlement engine) must filter
   `deletedAt == nil`, or deleted rows reappear in reports.
4. **FK ordering** on push/delete batches.
5. **`storedRate`** (exchange-rate-at-creation) must survive the round trip
   untouched — historical balances depend on it.
6. **Actor rules:** `ModelContext` stays on `@MainActor`; pass `PersistentIdentifier`
   across actor boundaries (existing convention).
7. **Migration plan currently empty** (`SchemaV1`, no stages). Sync columns become
   the first real `SchemaV2` + `MigrationStage`.

---

## 9. Rollback & safety

**Git:**
- Stable baseline tagged **`pre-supabase-migration`** (commit `59dc8d2`).
- All work on branch **`feature/supabase-migration`**; `main` untouched.
- Full revert: `git checkout pre-supabase-migration`.

**Runtime kill-switch (built into the app from Phase 2):**
- A single feature flag `isSupabaseSyncEnabled` (remote-config or build flag).
  When off, the app behaves exactly like the local-only version — SwiftData only,
  no network. Lets us disable sync in production without shipping a new build.

**Data safety:**
- The local SwiftData store is **never destroyed** during migration. The importer
  only reads + uploads; the corrupt-store recovery path already backs up rather
  than deletes.
- Supabase project should have **point-in-time recovery / daily backups** enabled.

**Per-phase gate:** each phase must build clean and pass the existing XCTest suite
before merging. No phase merges to `main` until verified.

---

## 10. Effort & risk

Multi-week effort. The SyncEngine (Phase 3) and the one-time importer (Phase 4)
are the correctness-critical, bug-prone parts because this is money. Schema/auth/
storage are well-trodden. Implementation proceeds **one phase at a time with a
build/test gate** — never big-bang.
