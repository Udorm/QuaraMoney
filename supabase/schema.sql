-- QuaraMoney — canonical Postgres schema (full-fidelity, all 15 entities + join).
-- Source of truth is the applied Supabase migrations; this file mirrors them.
-- Conventions: money = numeric (decode as STRING in Swift); Int64 minor units =
-- bigint; enums = text; Storage blobs = *_path; soft delete = deleted_at;
-- updated_at = LWW key (trigger-maintained). needsSync is LOCAL-only (not here).

create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create table if not exists public.wallets (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  currency_code text not null,
  icon text not null,
  color_hex text not null,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.categories (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  icon text,
  color_hex text,
  type text not null,
  is_system boolean not null default false,
  -- Language-independent identity for app-defined categories (CategoryCatalog);
  -- null for user-created ones. Partial-unique per account so duplicate defaults
  -- can't exist (migration 2026-07-02_profiles_and_canonical_categories).
  canonical_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists categories_user_canonical_key_unique
  on public.categories (user_id, canonical_key, type)
  where deleted_at is null and canonical_key is not null;

create table if not exists public.events (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  start_date timestamptz not null,
  end_date timestamptz,
  total_budget numeric(19,4),
  cover_image_path text,
  notes text,
  icon text not null default 'party.popper',
  color_hex text not null default '007AFF',
  location text,
  status text not null default 'planned',
  currency_code text not null default 'USD',
  ledger_revision bigint not null default 0,
  confirmed_settlement_revision bigint,
  ledger_mode text not null default 'isolatedV1',
  latitude double precision,
  longitude double precision,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.recurring_rules (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  amount numeric(19,4) not null,
  currency_code text not null,
  type text not null default 'expense',
  frequency text not null,
  interval integer not null default 1,
  start_date timestamptz not null,
  next_due_date timestamptz not null,
  end_date timestamptz,
  is_active boolean not null default true,
  reminders_enabled boolean not null default true,
  wallet_id uuid references public.wallets(id) on delete set null,
  category_id uuid references public.categories(id) on delete set null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.savings_goals (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  goal_description text,
  target_amount numeric(19,4) not null,
  current_amount numeric(19,4) not null default 0,
  currency_code text not null,
  target_date timestamptz,
  created_date timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  icon_name text not null,
  color_hex text not null,
  is_completed boolean not null default false,
  completed_date timestamptz,
  auto_contribute_enabled boolean not null default false,
  auto_contribute_amount numeric(19,4),
  auto_contribute_period_raw text,
  priority integer not null default 0,
  linked_wallet_id uuid references public.wallets(id) on delete set null,
  deleted_at timestamptz
);

create table if not exists public.debts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  person_name text not null,
  total_amount numeric(19,4) not null,
  currency_code text not null,
  due_date timestamptz,
  type text not null,
  note text,
  date_created timestamptz not null default now(),
  is_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.transactions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  date timestamptz not null,
  note text,
  tags text[] not null default '{}',
  exclude_from_reports boolean not null default false,
  amount numeric(19,4) not null,
  currency_code text not null,
  exchange_rate numeric(19,8) not null default 1,
  stored_rate numeric(19,8),
  photo_path text,
  category_id uuid references public.categories(id) on delete restrict,
  event_id uuid references public.events(id) on delete set null,
  source_wallet_id uuid references public.wallets(id) on delete cascade,
  destination_wallet_id uuid references public.wallets(id) on delete set null,
  recurring_rule_id uuid references public.recurring_rules(id) on delete cascade,
  debt_id uuid references public.debts(id) on delete cascade,
  savings_goal_id uuid references public.savings_goals(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.transaction_locations (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  transaction_id uuid references public.transactions(id) on delete cascade,
  display_name text,
  full_address text,
  short_address text,
  latitude double precision not null,
  longitude double precision not null,
  horizontal_accuracy_meters double precision,
  captured_at timestamptz not null default now(),
  source_raw text not null,
  apple_place_id text,
  alternate_apple_place_ids text,
  point_of_interest_category_raw text,
  locality text,
  administrative_area text,
  country_code text,
  normalized_spatial_key text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.budgets (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text,
  amount_limit numeric(19,4) not null,
  currency_code text not null default 'USD',
  period_type_raw text not null default 'monthly',
  start_date timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  custom_end_date timestamptz,
  month integer not null default 1,
  year integer not null default 2026,
  is_recurring boolean not null default false,
  rollover_excess boolean not null default false,
  rollover_amount numeric(19,4) not null default 0,
  amount_type_data text,
  alert_at_50 boolean not null default false,
  alert_at_80 boolean not null default true,
  alert_at_100 boolean not null default true,
  alert_on_projected_overspend boolean not null default false,
  last_alert_triggered_date timestamptz,
  last_alert_threshold integer not null default 0,
  budget_category_type_raw text,
  category_id uuid references public.categories(id) on delete set null,
  deleted_at timestamptz
);

create table if not exists public.budget_categories (
  budget_id uuid not null references public.budgets(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (budget_id, category_id)
);

create table if not exists public.event_members (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  name text not null,
  avatar_path text,
  avatar_icon text,
  color_hex text not null default '#007AFF',
  is_archived boolean not null default false,
  is_local_user boolean not null default false,
  is_budget_pool boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.event_ledger_transactions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  kind text not null,
  title text not null,
  amount_minor bigint not null,
  paid_source text not null,
  paid_by_member_id uuid,
  split_type text not null,
  date timestamptz not null,
  note text,
  category_id uuid,
  category_name text,
  category_icon text,
  category_color_hex text,
  is_split_all boolean not null default false,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.event_ledger_participants (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  transaction_id uuid references public.event_ledger_transactions(id) on delete cascade,
  member_id uuid not null,
  event_member_id uuid references public.event_members(id) on delete set null,
  order_index integer not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.event_settlement_snapshots (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  ledger_revision bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.event_settlement_transfers (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  snapshot_id uuid references public.event_settlement_snapshots(id) on delete cascade,
  from_member_id uuid not null,
  to_member_id uuid not null,
  amount_minor bigint not null,
  sequence integer not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.event_wallet_export_records (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  snapshot_id uuid references public.event_settlement_snapshots(id) on delete set null,
  member_id uuid not null,
  wallet_transaction_id uuid not null,
  amount_minor bigint not null,
  direction text not null,
  export_type text not null default 'settlement',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- updated_at triggers
-- Fire on INSERT as well as UPDATE so updated_at is server-authoritative for
-- every write. The sync engine uses updated_at as the last-write-wins key and as
-- the pull cursor; if inserts kept the client-supplied value, a device with a
-- behind clock could insert a row whose updated_at sorts below other devices'
-- cursors and is never pulled. (Applied to prod via migration
-- set_updated_at_on_insert_or_update.)
do $$
declare t text;
begin
  foreach t in array array[
    'wallets','categories','events','recurring_rules','savings_goals','debts',
    'transactions','transaction_locations','budgets','event_members',
    'event_ledger_transactions','event_ledger_participants',
    'event_settlement_snapshots','event_settlement_transfers',
    'event_wallet_export_records'
  ]
  loop
    execute format(
      'drop trigger if exists set_updated_at on public.%I;
       create trigger set_updated_at before insert or update on public.%I
       for each row execute function public.set_updated_at();', t, t);
  end loop;
end$$;

-- sync-pull / lookup indexes
create index if not exists idx_transactions_user_updated on public.transactions(user_id, updated_at);
create index if not exists idx_transactions_user_date    on public.transactions(user_id, date);
create index if not exists idx_wallets_user_updated      on public.wallets(user_id, updated_at);
create index if not exists idx_categories_user_updated   on public.categories(user_id, updated_at);
create index if not exists idx_budgets_user_updated      on public.budgets(user_id, updated_at);
create index if not exists idx_debts_user_updated        on public.debts(user_id, updated_at);
create index if not exists idx_events_user_updated       on public.events(user_id, updated_at);
create index if not exists idx_recurring_user_updated    on public.recurring_rules(user_id, updated_at);
create index if not exists idx_savings_user_updated      on public.savings_goals(user_id, updated_at);
create index if not exists idx_txlocations_user_updated  on public.transaction_locations(user_id, updated_at);
create index if not exists idx_evmembers_user_updated    on public.event_members(user_id, updated_at);
create index if not exists idx_evledgertx_user_updated   on public.event_ledger_transactions(user_id, updated_at);
create index if not exists idx_evparticipants_user_updated on public.event_ledger_participants(user_id, updated_at);
create index if not exists idx_evsnapshots_user_updated  on public.event_settlement_snapshots(user_id, updated_at);
create index if not exists idx_evtransfers_user_updated  on public.event_settlement_transfers(user_id, updated_at);
create index if not exists idx_evexports_user_updated    on public.event_wallet_export_records(user_id, updated_at);

-- FK covering indexes (advisor: unindexed_foreign_keys — cascade deletes and
-- FK checks scan the child table without these).
-- (migration 2026-07-07_rls_initplan_and_fk_indexes)
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

-- ---------------------------------------------------------------------------
-- profiles — single-row account profile (display name + avatar pointer).
-- Avatar bytes live in the receipts bucket at {uid}/profile/avatar.jpg.
-- (migration 2026-07-02_profiles_and_canonical_categories)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists set_updated_at on public.profiles;
create trigger set_updated_at before insert or update on public.profiles
  for each row execute function public.set_updated_at();
