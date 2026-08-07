-- Savings goals become first-class wallets. Additive only: legacy goal and
-- transaction columns remain during the deprecation/recovery window.

alter table public.wallets
  add column if not exists kind text not null default 'normal',
  add column if not exists target_amount numeric(19,4),
  add column if not exists target_date timestamptz,
  add column if not exists priority integer not null default 0,
  add column if not exists has_celebrated boolean not null default false,
  add column if not exists legacy_savings_goal_id uuid,
  add column if not exists legacy_migration_completed_at timestamptz;

alter table public.transactions
  add column if not exists migration_provenance text;

alter table public.recurring_rules
  add column if not exists pause_reason text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'wallets_kind_check'
      and conrelid = 'public.wallets'::regclass
  ) then
    alter table public.wallets
      add constraint wallets_kind_check check (kind in ('normal', 'savings'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'wallets_savings_target_check'
      and conrelid = 'public.wallets'::regclass
  ) then
    alter table public.wallets
      add constraint wallets_savings_target_check
      check (kind <> 'savings' or (target_amount is not null and target_amount > 0));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'recurring_rules_pause_reason_check'
      and conrelid = 'public.recurring_rules'::regclass
  ) then
    alter table public.recurring_rules
      add constraint recurring_rules_pause_reason_check
      check (pause_reason is null or pause_reason = 'invalidSavingsWallet');
  end if;
end $$;

create unique index if not exists wallets_user_legacy_savings_goal_unique
  on public.wallets (user_id, legacy_savings_goal_id)
  where legacy_savings_goal_id is not null;

create or replace function public.validate_wallet_savings_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if old.kind = 'savings' and new.kind <> 'savings' then
      raise exception 'A savings wallet cannot be converted back to a normal wallet.';
    end if;

    if old.kind = 'savings'
       and new.currency_code is distinct from old.currency_code
       and exists (
         select 1 from public.transactions
         where source_wallet_id = old.id or destination_wallet_id = old.id
       ) then
      raise exception 'A savings wallet currency is locked after its first transaction.';
    end if;

    if old.kind <> 'savings' and new.kind = 'savings'
       and exists (
         select 1 from public.transactions
         where source_wallet_id = old.id
           and deleted_at is null
           and type in ('income', 'expense')
       ) then
      raise exception 'A wallet with spending transactions cannot become a savings wallet.';
    end if;
  end if;

  if new.kind = 'savings' then
    update public.recurring_rules
      set is_active = false,
          pause_reason = 'invalidSavingsWallet'
      where wallet_id = new.id
        and deleted_at is null
        and (is_active or pause_reason is distinct from 'invalidSavingsWallet');
  end if;

  return new;
end;
$$;

drop trigger if exists validate_wallet_savings_update on public.wallets;
create trigger validate_wallet_savings_update
before insert or update on public.wallets
for each row execute function public.validate_wallet_savings_update();

create or replace function public.validate_transaction_wallet_matrix()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  locked_wallet record;
  source_kind text;
begin
  -- Tombstoned rows are exempt. A soft-deleted transaction contributes to no
  -- balance (every read path filters `deleted_at is null`), so validating its
  -- shape serves no purpose — and enforcing it would make pre-existing invalid
  -- legacy rows permanently un-updatable, including the act of tombstoning
  -- them or letting a client re-push the tombstone. Enforcement still applies
  -- in full to every live row.
  if new.deleted_at is not null then
    return new;
  end if;

  if new.savings_goal_id is not null then
    perform 1
      from public.savings_goals
      where id = new.savings_goal_id
      order by id
      for update;
  end if;

  for locked_wallet in
    select id
      from public.wallets
      where id in (new.source_wallet_id, new.destination_wallet_id)
      order by id
      for update
  loop
    null;
  end loop;

  if new.source_wallet_id is not null and not exists (
    select 1 from public.wallets
    where id = new.source_wallet_id and user_id = new.user_id
  ) then
    raise exception 'The source wallet is missing or belongs to another user.';
  end if;

  if new.destination_wallet_id is not null and not exists (
    select 1 from public.wallets
    where id = new.destination_wallet_id and user_id = new.user_id
  ) then
    raise exception 'The destination wallet is missing or belongs to another user.';
  end if;

  case new.type
    when 'income', 'expense' then
      if new.source_wallet_id is null or new.destination_wallet_id is not null then
        raise exception 'Income and expense require one source wallet and no destination.';
      end if;
      select kind into source_kind from public.wallets where id = new.source_wallet_id;
      if source_kind = 'savings' then
        raise exception 'Income and expense are not allowed against a savings wallet.';
      end if;
    when 'transfer' then
      if new.source_wallet_id is null or new.destination_wallet_id is null then
        raise exception 'Transfers require both source and destination wallets.';
      end if;
      if new.source_wallet_id = new.destination_wallet_id then
        raise exception 'Transfer source and destination must differ.';
      end if;
    when 'adjustment' then
      if new.source_wallet_id is null or new.destination_wallet_id is not null or new.amount = 0 then
        raise exception 'Adjustments require one source wallet, no destination, and a non-zero signed amount.';
      end if;
    else
      raise exception 'Unsupported transaction type: %', new.type;
  end case;

  if new.savings_goal_id is not null then
    if exists (
      select 1 from public.wallets
      where user_id = new.user_id
        and legacy_savings_goal_id = new.savings_goal_id
    ) then
      raise exception 'This legacy savings goal has already migrated.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists validate_transaction_wallet_matrix on public.transactions;
create trigger validate_transaction_wallet_matrix
before insert or update on public.transactions
for each row execute function public.validate_transaction_wallet_matrix();

create or replace function public.guard_migrated_savings_goal_resurrection()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.deleted_at is null and exists (
    select 1 from public.wallets
    where user_id = new.user_id and legacy_savings_goal_id = new.id
  ) then
    raise exception 'A migrated savings goal tombstone cannot be removed.';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_migrated_savings_goal_resurrection on public.savings_goals;
create trigger guard_migrated_savings_goal_resurrection
before insert or update on public.savings_goals
for each row execute function public.guard_migrated_savings_goal_resurrection();

create or replace function public.apply_savings_wallet_migration(
  p_wallet jsonb,
  p_transactions jsonb,
  p_goal_id uuid,
  p_goal_deleted_at timestamptz
)
returns table(completed_at timestamptz)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  transaction_row jsonb;
  migration_owner uuid := (p_wallet->>'user_id')::uuid;
  migration_wallet_id uuid := (p_wallet->>'id')::uuid;
  completion_time timestamptz := clock_timestamp();
begin
  if migration_owner is distinct from (select auth.uid()) then
    raise exception 'Savings migration owner does not match the authenticated user.';
  end if;
  if (p_wallet->>'legacy_savings_goal_id')::uuid is distinct from p_goal_id then
    raise exception 'Savings migration goal key does not match the wallet.';
  end if;
  if not exists (
    select 1 from public.savings_goals
    where id = p_goal_id and user_id = migration_owner
    for update
  ) then
    raise exception 'Legacy savings goal is missing or belongs to another user.';
  end if;

  insert into public.wallets (
    id, user_id, name, currency_code, icon, color_hex, is_archived,
    kind, target_amount, target_date, priority, has_celebrated,
    legacy_savings_goal_id, legacy_migration_completed_at,
    created_at, updated_at, deleted_at
  ) values (
    migration_wallet_id, migration_owner, p_wallet->>'name',
    p_wallet->>'currency_code', p_wallet->>'icon', p_wallet->>'color_hex',
    coalesce((p_wallet->>'is_archived')::boolean, false),
    p_wallet->>'kind', (p_wallet->>'target_amount')::numeric,
    (p_wallet->>'target_date')::timestamptz,
    coalesce((p_wallet->>'priority')::integer, 0),
    coalesce((p_wallet->>'has_celebrated')::boolean, false),
    p_goal_id, null,
    coalesce((p_wallet->>'created_at')::timestamptz, now()), now(),
    (p_wallet->>'deleted_at')::timestamptz
  )
  on conflict (id) do update set
    name = excluded.name,
    currency_code = excluded.currency_code,
    icon = excluded.icon,
    color_hex = excluded.color_hex,
    is_archived = excluded.is_archived,
    kind = excluded.kind,
    target_amount = excluded.target_amount,
    target_date = excluded.target_date,
    priority = excluded.priority,
    has_celebrated = excluded.has_celebrated,
    legacy_savings_goal_id = excluded.legacy_savings_goal_id,
    deleted_at = excluded.deleted_at;

  for transaction_row in select value from jsonb_array_elements(p_transactions)
  loop
    if coalesce(transaction_row->>'migration_provenance', '') like '%:untag:%' then
      update public.transactions
        set savings_goal_id = null,
            savings_is_withdrawal = false,
            migration_provenance = transaction_row->>'migration_provenance'
        where id = (transaction_row->>'id')::uuid
          and user_id = migration_owner;
      if found then continue; end if;
    end if;

    insert into public.transactions (
      id, user_id, type, date, note, tags, exclude_from_reports,
      amount, currency_code, exchange_rate, stored_rate, photo_path,
      category_id, event_id, source_wallet_id, destination_wallet_id,
      recurring_rule_id, debt_id, savings_goal_id, savings_is_withdrawal,
      migration_provenance, created_at, updated_at, deleted_at
    ) values (
      (transaction_row->>'id')::uuid, migration_owner,
      transaction_row->>'type', (transaction_row->>'date')::timestamptz,
      transaction_row->>'note',
      coalesce(array(select jsonb_array_elements_text(transaction_row->'tags')), '{}'),
      coalesce((transaction_row->>'exclude_from_reports')::boolean, false),
      (transaction_row->>'amount')::numeric, transaction_row->>'currency_code',
      coalesce((transaction_row->>'exchange_rate')::numeric, 1),
      (transaction_row->>'stored_rate')::numeric,
      transaction_row->>'photo_path',
      (transaction_row->>'category_id')::uuid,
      (transaction_row->>'event_id')::uuid,
      (transaction_row->>'source_wallet_id')::uuid,
      (transaction_row->>'destination_wallet_id')::uuid,
      (transaction_row->>'recurring_rule_id')::uuid,
      (transaction_row->>'debt_id')::uuid,
      null, false,
      transaction_row->>'migration_provenance',
      coalesce((transaction_row->>'created_at')::timestamptz, now()), now(),
      (transaction_row->>'deleted_at')::timestamptz
    )
    on conflict (id) do update set
      type = excluded.type,
      date = excluded.date,
      note = excluded.note,
      tags = excluded.tags,
      exclude_from_reports = excluded.exclude_from_reports,
      amount = excluded.amount,
      currency_code = excluded.currency_code,
      exchange_rate = excluded.exchange_rate,
      stored_rate = excluded.stored_rate,
      source_wallet_id = excluded.source_wallet_id,
      destination_wallet_id = excluded.destination_wallet_id,
      savings_goal_id = null,
      savings_is_withdrawal = false,
      migration_provenance = excluded.migration_provenance,
      deleted_at = excluded.deleted_at;
  end loop;

  update public.savings_goals
    set deleted_at = p_goal_deleted_at
    where id = p_goal_id and user_id = migration_owner;
  if not found then
    raise exception 'Legacy savings goal tombstone could not be written.';
  end if;

  update public.wallets
    set legacy_migration_completed_at = completion_time
    where id = migration_wallet_id and user_id = migration_owner;
  if not found then
    raise exception 'Savings migration completion marker could not be written.';
  end if;

  return query select completion_time;
end;
$$;

revoke execute on function public.apply_savings_wallet_migration(jsonb, jsonb, uuid, timestamptz) from public, anon;
grant execute on function public.apply_savings_wallet_migration(jsonb, jsonb, uuid, timestamptz) to authenticated, service_role;
