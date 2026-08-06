-- Local-only regression harness for 20260806154757_savings_wallets.sql.
-- Run against `supabase start`; every fixture is rolled back.
begin;

insert into auth.users (id, email)
values ('10000000-0000-0000-0000-000000000001', 'savings-wallet-test@example.invalid');

insert into public.wallets (
  id, user_id, name, currency_code, icon, color_hex, kind, target_amount
) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
   'Spending', 'USD', 'wallet.pass', '#000000', 'normal', null),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001',
   'Goal', 'USD', 'target', '#10B981', 'savings', 100);

do $$
begin
  begin
    insert into public.transactions (
      id, user_id, type, date, amount, currency_code, source_wallet_id
    ) values (
      '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
      'income', now(), 10, 'USD', '20000000-0000-0000-0000-000000000002'
    );
    raise exception 'expected savings income rejection';
  exception when others then
    if sqlerrm not like 'Income and expense are not allowed%' then raise; end if;
  end;

  begin
    insert into public.transactions (
      id, user_id, type, date, amount, currency_code, source_wallet_id
    ) values (
      '30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001',
      'adjustment', now(), 0, 'USD', '20000000-0000-0000-0000-000000000002'
    );
    raise exception 'expected zero adjustment rejection';
  exception when others then
    if sqlerrm not like 'Adjustments require%' then raise; end if;
  end;

  begin
    update public.wallets
      set kind = 'savings', target_amount = 100
      where id = '20000000-0000-0000-0000-000000000001';
    -- The clean normal wallet may flip exactly once.
  exception when others then
    raise exception 'clean normal-to-savings flip unexpectedly failed: %', sqlerrm;
  end;

  begin
    update public.wallets
      set kind = 'normal'
      where id = '20000000-0000-0000-0000-000000000001';
    raise exception 'expected terminal savings-kind rejection';
  exception when others then
    if sqlerrm not like 'A savings wallet cannot be converted%' then raise; end if;
  end;
end;
$$;

insert into public.transactions (
  id, user_id, type, date, amount, currency_code, stored_rate,
  source_wallet_id, destination_wallet_id
) values (
  '30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001',
  'transfer', now(), 25, 'USD', 1,
  '20000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000002'
);

do $$
begin
  if not exists (
    select 1 from public.transactions
    where id = '30000000-0000-0000-0000-000000000003'
  ) then
    raise exception 'valid savings transfer was not retained';
  end if;

  -- An old client updates only columns it knows; additive savings metadata must
  -- remain intact on the row.
  update public.wallets
    set name = 'Goal renamed by old client'
    where id = '20000000-0000-0000-0000-000000000002';
  if not exists (
    select 1 from public.wallets
    where id = '20000000-0000-0000-0000-000000000002'
      and kind = 'savings' and target_amount = 100
  ) then
    raise exception 'old-client wallet update erased savings metadata';
  end if;

  begin
    update public.wallets
      set currency_code = 'KHR'
      where id = '20000000-0000-0000-0000-000000000002';
    raise exception 'expected funded savings currency-lock rejection';
  exception when others then
    if sqlerrm not like 'A savings wallet currency is locked%' then raise; end if;
  end;
end;
$$;

insert into public.savings_goals (
  id, user_id, name, target_amount, current_amount, currency_code,
  icon_name, color_hex
) values (
  '40000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'Legacy goal', 100, 25, 'USD', 'target', '#10B981'
);

insert into public.wallets (
  id, user_id, name, currency_code, icon, color_hex, kind, target_amount,
  legacy_savings_goal_id
) values (
  '20000000-0000-0000-0000-000000000003',
  '10000000-0000-0000-0000-000000000001',
  'Replacement', 'USD', 'target', '#10B981', 'savings', 100,
  '40000000-0000-0000-0000-000000000001'
);

do $$
begin
  begin
    insert into public.wallets (
      id, user_id, name, currency_code, icon, color_hex, kind, target_amount,
      legacy_savings_goal_id
    ) values (
      '20000000-0000-0000-0000-000000000004',
      '10000000-0000-0000-0000-000000000001',
      'Duplicate replacement', 'USD', 'target', '#10B981', 'savings', 100,
      '40000000-0000-0000-0000-000000000001'
    );
    raise exception 'expected legacy goal partial-unique rejection';
  exception when unique_violation then
    null;
  end;

  update public.savings_goals
    set deleted_at = now()
    where id = '40000000-0000-0000-0000-000000000001';

  begin
    update public.savings_goals
      set deleted_at = null
      where id = '40000000-0000-0000-0000-000000000001';
    raise exception 'expected migrated goal resurrection rejection';
  exception when others then
    if sqlerrm not like 'A migrated savings goal tombstone cannot be removed%' then raise; end if;
  end;

  begin
    insert into public.transactions (
      id, user_id, type, date, amount, currency_code, stored_rate,
      source_wallet_id, destination_wallet_id, savings_goal_id
    ) values (
      '30000000-0000-0000-0000-000000000004',
      '10000000-0000-0000-0000-000000000001',
      'transfer', now(), 5, 'USD', 1,
      '20000000-0000-0000-0000-000000000001',
      '20000000-0000-0000-0000-000000000002',
      '40000000-0000-0000-0000-000000000001'
    );
    raise exception 'expected stale legacy transaction rejection';
  exception when others then
    if sqlerrm not like 'This legacy savings goal has already migrated%' then raise; end if;
  end;
end;
$$;

rollback;
