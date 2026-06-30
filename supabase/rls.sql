-- QuaraMoney — Row-Level Security policies
-- Every table is owner-scoped: a user can only touch rows where user_id = auth.uid().
-- Apply AFTER schema.sql. See MIGRATION.md §4.
--
-- NOTE: soft-deleted rows (deleted_at IS NOT NULL) are still selectable on
-- purpose — the sync pull needs tombstones. Filtering of deleted rows happens
-- client-side in SwiftData queries.

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
        for select using (user_id = auth.uid());
    $f$, t);

    -- INSERT
    execute format($f$
      drop policy if exists "%1$s_insert_own" on public.%1$s;
      create policy "%1$s_insert_own" on public.%1$s
        for insert with check (user_id = auth.uid());
    $f$, t);

    -- UPDATE
    execute format($f$
      drop policy if exists "%1$s_update_own" on public.%1$s;
      create policy "%1$s_update_own" on public.%1$s
        for update using (user_id = auth.uid()) with check (user_id = auth.uid());
    $f$, t);

    -- DELETE (rarely used — we soft-delete — but locked down anyway)
    execute format($f$
      drop policy if exists "%1$s_delete_own" on public.%1$s;
      create policy "%1$s_delete_own" on public.%1$s
        for delete using (user_id = auth.uid());
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
  for select using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "receipts_insert_own" on storage.objects;
create policy "receipts_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "receipts_update_own" on storage.objects;
create policy "receipts_update_own" on storage.objects
  for update using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "receipts_delete_own" on storage.objects;
create policy "receipts_delete_own" on storage.objects
  for delete using (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
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
