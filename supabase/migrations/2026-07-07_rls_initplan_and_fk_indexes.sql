-- 2026-07-07 — security-audit follow-up
--
-- 1. RLS policy tuning (68 `auth_rls_initplan` advisor warnings):
--    * `auth.uid()` → `(select auth.uid())` so Postgres evaluates it once per
--      query (InitPlan) instead of once per row — big win on large sync pulls.
--    * `to authenticated` so anon-key requests skip policy evaluation entirely.
--    Behavior is identical for signed-in users; anon had no access before either
--    (auth.uid() is null), it just short-circuits earlier now.
--
-- 2. Covering indexes for the 22 unindexed foreign keys flagged by the advisor
--    (cascade deletes and FK checks otherwise scan the child table).

-- --------------------------------------------------------------------------
-- 1a. Owner-scoped table policies
-- --------------------------------------------------------------------------
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
    execute format($f$
      drop policy if exists "%1$s_select_own" on public.%1$s;
      create policy "%1$s_select_own" on public.%1$s
        for select to authenticated using (user_id = (select auth.uid()));
    $f$, t);

    execute format($f$
      drop policy if exists "%1$s_insert_own" on public.%1$s;
      create policy "%1$s_insert_own" on public.%1$s
        for insert to authenticated with check (user_id = (select auth.uid()));
    $f$, t);

    execute format($f$
      drop policy if exists "%1$s_update_own" on public.%1$s;
      create policy "%1$s_update_own" on public.%1$s
        for update to authenticated
        using (user_id = (select auth.uid()))
        with check (user_id = (select auth.uid()));
    $f$, t);

    execute format($f$
      drop policy if exists "%1$s_delete_own" on public.%1$s;
      create policy "%1$s_delete_own" on public.%1$s
        for delete to authenticated using (user_id = (select auth.uid()));
    $f$, t);
  end loop;
end$$;

-- 1b. profiles (owner-scoped by id, not user_id)
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

-- 1c. Storage: receipts bucket
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

-- --------------------------------------------------------------------------
-- 2. Foreign-key covering indexes
-- --------------------------------------------------------------------------
create index if not exists idx_budget_categories_category   on public.budget_categories(category_id);
create index if not exists idx_budget_categories_user       on public.budget_categories(user_id);
create index if not exists idx_budgets_category             on public.budgets(category_id);
create index if not exists idx_evparticipants_event_member  on public.event_ledger_participants(event_member_id);
create index if not exists idx_evparticipants_transaction   on public.event_ledger_participants(transaction_id);
create index if not exists idx_evledgertx_event             on public.event_ledger_transactions(event_id);
create index if not exists idx_evmembers_event              on public.event_members(event_id);
create index if not exists idx_evsnapshots_event            on public.event_settlement_snapshots(event_id);
create index if not exists idx_evtransfers_snapshot         on public.event_settlement_transfers(snapshot_id);
create index if not exists idx_evexports_event              on public.event_wallet_export_records(event_id);
create index if not exists idx_evexports_snapshot           on public.event_wallet_export_records(snapshot_id);
create index if not exists idx_recurring_category           on public.recurring_rules(category_id);
create index if not exists idx_recurring_wallet             on public.recurring_rules(wallet_id);
create index if not exists idx_savings_linked_wallet        on public.savings_goals(linked_wallet_id);
create index if not exists idx_txlocations_transaction      on public.transaction_locations(transaction_id);
create index if not exists idx_transactions_category        on public.transactions(category_id);
create index if not exists idx_transactions_debt            on public.transactions(debt_id);
create index if not exists idx_transactions_dest_wallet     on public.transactions(destination_wallet_id);
create index if not exists idx_transactions_event           on public.transactions(event_id);
create index if not exists idx_transactions_recurring_rule  on public.transactions(recurring_rule_id);
create index if not exists idx_transactions_savings_goal    on public.transactions(savings_goal_id);
create index if not exists idx_transactions_source_wallet   on public.transactions(source_wallet_id);
