-- QuaraMoney — Row-Level Security policies
-- Every table is owner-scoped: a user can only touch rows where user_id = auth.uid().
-- Apply AFTER schema.sql. See MIGRATION.md §4.
--
-- NOTE: soft-deleted rows (deleted_at IS NOT NULL) are still selectable on
-- purpose — the sync pull needs tombstones. Filtering of deleted rows happens
-- client-side in SwiftData queries.
--
-- Policy conventions (migration 2026-07-07_rls_initplan_and_fk_indexes):
--   * `(select auth.uid())` not bare `auth.uid()` — evaluated once per query
--     (InitPlan) instead of per row.
--   * `to authenticated` — anon-key requests skip policy evaluation entirely.

do $$
declare t text;
begin
  foreach t in array array[
    'wallets','categories','events','recurring_rules','savings_goals','debts',
    'transactions','transaction_locations','budgets','budget_categories',
    'event_members','event_ledger_transactions','event_ledger_participants',
    'event_settlement_snapshots','event_settlement_transfers',
    'event_wallet_export_records'
  ]
  loop
    execute format('alter table public.%I enable row level security;', t);

    -- SELECT
    execute format($f$
      drop policy if exists "%1$s_select_own" on public.%1$s;
      create policy "%1$s_select_own" on public.%1$s
        for select to authenticated using (user_id = (select auth.uid()));
    $f$, t);

    -- INSERT
    execute format($f$
      drop policy if exists "%1$s_insert_own" on public.%1$s;
      create policy "%1$s_insert_own" on public.%1$s
        for insert to authenticated with check (user_id = (select auth.uid()));
    $f$, t);

    -- UPDATE
    execute format($f$
      drop policy if exists "%1$s_update_own" on public.%1$s;
      create policy "%1$s_update_own" on public.%1$s
        for update to authenticated
        using (user_id = (select auth.uid()))
        with check (user_id = (select auth.uid()));
    $f$, t);

    -- DELETE (rarely used — we soft-delete — but locked down anyway)
    execute format($f$
      drop policy if exists "%1$s_delete_own" on public.%1$s;
      create policy "%1$s_delete_own" on public.%1$s
        for delete to authenticated using (user_id = (select auth.uid()));
    $f$, t);
  end loop;
end$$;

-- ---------------------------------------------------------------------------
-- Storage: private receipts bucket, owner-scoped by path prefix
--   path layout: receipts/{user_id}/{transaction_id}.jpg
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

drop policy if exists "receipts_select_own" on storage.objects;
create policy "receipts_select_own" on storage.objects
  for select to authenticated using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "receipts_insert_own" on storage.objects;
create policy "receipts_insert_own" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "receipts_update_own" on storage.objects;
create policy "receipts_update_own" on storage.objects
  for update to authenticated using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "receipts_delete_own" on storage.objects;
create policy "receipts_delete_own" on storage.objects
  for delete to authenticated using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Enable Realtime for all synced tables
alter publication supabase_realtime add table
  public.wallets,
  public.categories,
  public.events,
  public.recurring_rules,
  public.savings_goals,
  public.debts,
  public.transactions,
  public.transaction_locations,
  public.budgets,
  public.budget_categories,
  public.event_members,
  public.event_ledger_transactions,
  public.event_ledger_participants,
  public.event_settlement_snapshots,
  public.event_settlement_transfers,
  public.event_wallet_export_records;

-- ---------------------------------------------------------------------------
-- profiles: owner-scoped by id (= auth.uid), not user_id
-- (migration 2026-07-02_profiles_and_canonical_categories)
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = (select auth.uid()));

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own" on public.profiles
  for delete to authenticated using (id = (select auth.uid()));
