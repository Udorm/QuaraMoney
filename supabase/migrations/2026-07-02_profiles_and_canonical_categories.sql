-- QuaraMoney — profiles table + canonical category keys.
-- Apply to the live project (SQL editor or `supabase db push`), then keep
-- schema.sql / rls.sql mirrors in sync (already updated in this repo).
--
-- MUST be applied BEFORE shipping the build that sends `canonical_key`:
-- pushes to `categories` fail on an unknown column otherwise.

-- ---------------------------------------------------------------------------
-- 1. categories.canonical_key — language-independent identity for app-defined
--    (default/system) categories; see CategoryCatalog.swift. NULL for
--    user-created categories. The partial unique index makes duplicate defaults
--    structurally impossible per account: a second device pushing the same
--    default with a different id violates the index, and the client resolves by
--    pulling the winner and merging locally (dedupe pass).
-- ---------------------------------------------------------------------------
alter table public.categories add column if not exists canonical_key text;

create unique index if not exists categories_user_canonical_key_unique
  on public.categories (user_id, canonical_key, type)
  where deleted_at is null and canonical_key is not null;

-- ---------------------------------------------------------------------------
-- 2. profiles — single-row account profile (display name + avatar pointer).
--    Avatar bytes live in the receipts bucket at {uid}/profile/avatar.jpg
--    (covered by the existing path-prefix storage policies).
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Server-authoritative updated_at (same trigger fn as the data tables).
drop trigger if exists set_updated_at on public.profiles;
create trigger set_updated_at before insert or update on public.profiles
  for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (id = auth.uid());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "profiles_delete_own" on public.profiles;
create policy "profiles_delete_own" on public.profiles
  for delete using (id = auth.uid());
