-- STEP 1 of 2 — run this BEFORE applying 20260806154757_savings_wallets.sql
--
-- Tombstones 28 pre-existing rows that violate the new transaction-matrix
-- trigger. Reversible via ROLLBACK_junk_row_cleanup.sql (rows are soft-deleted,
-- not removed). Balance-neutral:
--   * 24 transfers, note "Pay Credit Card", $500/mo 2024-07..2026-06, where
--     source_wallet_id = destination_wallet_id (both "Bank Account") -> the
--     money never moved anywhere, so tombstoning changes no balance.
--   * 4 expenses from 2026-06-22 with source_wallet_id IS NULL (no wallet, no
--     category, no note; amounts 89 / 7777 / 89 / 999999) -> attached to no
--     wallet, so they were already invisible to every balance.
--
-- ORDER MATTERS: run this first. If the migration's trigger is already live,
-- this UPDATE would be rejected by the very rule it exists to clear.

update public.transactions
set deleted_at = now(),
    updated_at = now()
where deleted_at is null
  and (
    (type in ('income','expense') and source_wallet_id is null)
    or (type = 'transfer' and source_wallet_id = destination_wallet_id)
  );

-- Expected result: UPDATE 28

-- Verify zero LIVE violations remain (every count must be 0):
select 'expense/income missing source' as violation, count(*) as rows
from public.transactions
where deleted_at is null and type in ('income','expense') and source_wallet_id is null
union all
select 'expense/income has destination', count(*)
from public.transactions
where deleted_at is null and type in ('income','expense') and destination_wallet_id is not null
union all
select 'transfer missing an endpoint', count(*)
from public.transactions
where deleted_at is null and type = 'transfer'
  and (source_wallet_id is null or destination_wallet_id is null)
union all
select 'transfer same wallet both sides', count(*)
from public.transactions
where deleted_at is null and type = 'transfer' and source_wallet_id = destination_wallet_id
union all
select 'adjustment invalid shape', count(*)
from public.transactions
where deleted_at is null and type = 'adjustment'
  and (source_wallet_id is null or destination_wallet_id is not null or amount = 0)
union all
select 'source wallet cross-owner/missing', count(*)
from public.transactions t
where t.deleted_at is null and t.source_wallet_id is not null
  and not exists (select 1 from public.wallets w
                  where w.id = t.source_wallet_id and w.user_id = t.user_id)
union all
select 'dest wallet cross-owner/missing', count(*)
from public.transactions t
where t.deleted_at is null and t.destination_wallet_id is not null
  and not exists (select 1 from public.wallets w
                  where w.id = t.destination_wallet_id and w.user_id = t.user_id);
