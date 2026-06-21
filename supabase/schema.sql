-- QuaraMoney — canonical Postgres schema
-- Generated for the SwiftData → Supabase migration. See MIGRATION.md.
--
-- Conventions:
--   * id            uuid PRIMARY KEY — client-generated (matches SwiftData UUIDs)
--   * user_id       uuid NOT NULL    — owner, FK to auth.users; drives RLS
--   * created_at    timestamptz
--   * updated_at    timestamptz      — LWW sync key (trigger keeps it honest)
--   * deleted_at    timestamptz NULL — soft delete / tombstone (NULL = live)
--   * money         numeric(19,4)    — NEVER float; decode as string in Swift
--   * minor units   bigint           — event ledger (Int64)
--   * enums         text + CHECK     — store the Swift rawValue
--
-- Apply with: supabase db push   (or paste into the SQL editor / MCP apply_migration)

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "pgcrypto"; -- gen_random_uuid (server-side fallback)

-- ---------------------------------------------------------------------------
-- updated_at trigger (server backstop; client also sets it for LWW)
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''               -- pinned: avoids function_search_path_mutable advisor
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- wallets
-- ---------------------------------------------------------------------------
create table if not exists public.wallets (
  id            uuid primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  name          text not null,
  currency_code text not null check (char_length(currency_code) = 3),
  icon          text not null,
  color_hex     text not null,
  is_archived   boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- ---------------------------------------------------------------------------
-- categories
-- ---------------------------------------------------------------------------
create table if not exists public.categories (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  icon        text,
  color_hex   text,
  type        text not null check (type in ('income','expense')),
  is_system   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- ---------------------------------------------------------------------------
-- events  (group expense splitting; single-owner for now)
-- ---------------------------------------------------------------------------
create table if not exists public.events (
  id           uuid primary key,
  user_id      uuid not null references auth.users (id) on delete cascade,
  name         text not null,
  ledger_mode  text not null default 'isolatedV1' check (ledger_mode in ('legacyLinked','isolatedV1')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

-- ---------------------------------------------------------------------------
-- recurring_rules
-- ---------------------------------------------------------------------------
create table if not exists public.recurring_rules (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  category_id uuid references public.categories (id) on delete set null,
  wallet_id   uuid references public.wallets (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- ---------------------------------------------------------------------------
-- savings_goals
-- ---------------------------------------------------------------------------
create table if not exists public.savings_goals (
  id               uuid primary key,
  user_id          uuid not null references auth.users (id) on delete cascade,
  linked_wallet_id uuid references public.wallets (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);

-- ---------------------------------------------------------------------------
-- debts
-- ---------------------------------------------------------------------------
create table if not exists public.debts (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- ---------------------------------------------------------------------------
-- transactions  (core table)
-- ---------------------------------------------------------------------------
create table if not exists public.transactions (
  id                   uuid primary key,
  user_id              uuid not null references auth.users (id) on delete cascade,
  type                 text not null check (type in ('income','expense','transfer','adjustment')),
  date                 timestamptz not null,
  note                 text,
  tags                 text[] not null default '{}',
  exclude_from_reports boolean not null default false,

  amount               numeric(19,4) not null,
  currency_code        text not null check (char_length(currency_code) = 3),
  exchange_rate        numeric(19,8) not null default 1,
  stored_rate          numeric(19,8),

  photo_path           text,                -- Supabase Storage object path

  -- Relationships (FK delete rules mirror SwiftData @Relationship)
  category_id          uuid references public.categories (id)   on delete restrict, -- .deny
  event_id             uuid references public.events (id)       on delete set null, -- .nullify
  source_wallet_id     uuid references public.wallets (id)      on delete cascade,  -- .cascade
  destination_wallet_id uuid references public.wallets (id)     on delete set null, -- .nullify
  recurring_rule_id    uuid references public.recurring_rules (id) on delete cascade,
  debt_id              uuid references public.debts (id)        on delete cascade,
  savings_goal_id      uuid references public.savings_goals (id) on delete set null,

  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);

-- ---------------------------------------------------------------------------
-- transaction_locations  (1:1 with transaction, cascade)
-- ---------------------------------------------------------------------------
create table if not exists public.transaction_locations (
  id             uuid primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  transaction_id uuid not null references public.transactions (id) on delete cascade,
  latitude       double precision,
  longitude      double precision,
  name           text,
  address        text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

-- ---------------------------------------------------------------------------
-- budgets
-- ---------------------------------------------------------------------------
create table if not exists public.budgets (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  category_id uuid references public.categories (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- budgets ↔ categories many-to-many (Budget.categories array)
create table if not exists public.budget_categories (
  budget_id   uuid not null references public.budgets (id) on delete cascade,
  category_id uuid not null references public.categories (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  primary key (budget_id, category_id)
);

-- ---------------------------------------------------------------------------
-- event_members
-- ---------------------------------------------------------------------------
create table if not exists public.event_members (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  event_id    uuid not null references public.events (id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- ---------------------------------------------------------------------------
-- event_ledger_transactions  (amounts as Int64 minor units → bigint)
-- ---------------------------------------------------------------------------
create table if not exists public.event_ledger_transactions (
  id            uuid primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  event_id      uuid not null references public.events (id) on delete cascade,
  amount_minor  bigint not null,
  currency_code text not null check (char_length(currency_code) = 3),
  split_type    text not null check (split_type in ('equal','custom','payerOnly')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- ---------------------------------------------------------------------------
-- event_ledger_participants
-- ---------------------------------------------------------------------------
create table if not exists public.event_ledger_participants (
  id             uuid primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  transaction_id uuid not null references public.event_ledger_transactions (id) on delete cascade,
  member_id      uuid references public.event_members (id) on delete set null,
  share_minor    bigint,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);

-- ---------------------------------------------------------------------------
-- event_settlement_snapshots
-- ---------------------------------------------------------------------------
create table if not exists public.event_settlement_snapshots (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  event_id    uuid not null references public.events (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- ---------------------------------------------------------------------------
-- event_wallet_export_records
-- ---------------------------------------------------------------------------
create table if not exists public.event_wallet_export_records (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  event_id    uuid not null references public.events (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

-- ---------------------------------------------------------------------------
-- Triggers: keep updated_at fresh on every UPDATE
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'wallets','categories','events','recurring_rules','savings_goals','debts',
    'transactions','transaction_locations','budgets','event_members',
    'event_ledger_transactions','event_ledger_participants',
    'event_settlement_snapshots','event_wallet_export_records'
  ]
  loop
    execute format(
      'drop trigger if exists set_updated_at on public.%I;
       create trigger set_updated_at before update on public.%I
       for each row execute function public.set_updated_at();', t, t);
  end loop;
end$$;

-- ---------------------------------------------------------------------------
-- Indexes for sync pull (updated_at) + common lookups
-- ---------------------------------------------------------------------------
create index if not exists idx_transactions_user_updated on public.transactions (user_id, updated_at);
create index if not exists idx_transactions_user_date    on public.transactions (user_id, date);
create index if not exists idx_wallets_user_updated      on public.wallets (user_id, updated_at);
create index if not exists idx_categories_user_updated   on public.categories (user_id, updated_at);
create index if not exists idx_budgets_user_updated      on public.budgets (user_id, updated_at);
create index if not exists idx_debts_user_updated        on public.debts (user_id, updated_at);
create index if not exists idx_events_user_updated       on public.events (user_id, updated_at);
