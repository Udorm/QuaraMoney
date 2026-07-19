-- Additive-only Plan tab rework. Existing columns remain for older clients.
alter table public.budgets
  add column if not exists target_kind text,
  add column if not exists alert_mode text,
  add column if not exists last_alert_period_key text,
  add column if not exists week_start_day integer;

alter table public.savings_goals
  add column if not exists starting_balance_currency_code text;

alter table public.transactions
  add column if not exists savings_is_withdrawal boolean not null default false;

alter table public.budgets
  drop constraint if exists budgets_target_kind_check,
  add constraint budgets_target_kind_check check (target_kind is null or target_kind in ('total', 'categories')),
  drop constraint if exists budgets_alert_mode_check,
  add constraint budgets_alert_mode_check check (alert_mode is null or alert_mode in ('off', 'nearing', 'overOnly', 'nearingOver')),
  drop constraint if exists budgets_week_start_day_check,
  add constraint budgets_week_start_day_check check (week_start_day is null or week_start_day between 1 and 7);
