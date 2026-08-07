-- STEP 3 — prove the new triggers actually fire. SAFE: everything runs inside
-- a transaction that ends in ROLLBACK, so NOTHING is persisted. Run the whole
-- file as one script in the Supabase SQL editor.
--
-- Each block should report 'PASS'. Any 'FAIL' means the trigger did not behave
-- as designed — stop and report it before shipping the client.

begin;

do $$
declare
  uid uuid;
  spend_wallet uuid;
  savings_wallet uuid;
  ok boolean;
begin
  select user_id into uid from public.wallets where deleted_at is null limit 1;
  if uid is null then raise exception 'No wallets found — cannot run smoke test.'; end if;

  -- a normal wallet and a savings wallet to test against
  insert into public.wallets (id, user_id, name, currency_code, icon, color_hex, is_archived, created_at, updated_at, kind)
  values (gen_random_uuid(), uid, 'ZZ Smoke Spend', 'USD', 'wallet.pass', '#000000', false, now(), now(), 'normal')
  returning id into spend_wallet;

  insert into public.wallets (id, user_id, name, currency_code, icon, color_hex, is_archived, created_at, updated_at, kind, target_amount)
  values (gen_random_uuid(), uid, 'ZZ Smoke Savings', 'USD', 'target', '#10B981', false, now(), now(), 'savings', 1000)
  returning id into savings_wallet;

  -- 1. savings wallet REQUIRES a positive target (NULL-safe CHECK)
  begin
    insert into public.wallets (id, user_id, name, currency_code, icon, color_hex, is_archived, created_at, updated_at, kind)
    values (gen_random_uuid(), uid, 'ZZ No Target', 'USD', 'target', '#10B981', false, now(), now(), 'savings');
    raise notice 'FAIL 1: savings wallet without a target was accepted';
  exception when others then
    raise notice 'PASS 1: savings wallet without a positive target rejected';
  end;

  -- 2. expense against a SAVINGS wallet must be rejected
  begin
    insert into public.transactions (id, user_id, type, date, amount, currency_code, exchange_rate, source_wallet_id, created_at, updated_at)
    values (gen_random_uuid(), uid, 'expense', now(), 10, 'USD', 1, savings_wallet, now(), now());
    raise notice 'FAIL 2: expense against savings wallet was accepted';
  exception when others then
    raise notice 'PASS 2: expense against savings wallet rejected';
  end;

  -- 3. expense against a NORMAL wallet must still work
  begin
    insert into public.transactions (id, user_id, type, date, amount, currency_code, exchange_rate, source_wallet_id, created_at, updated_at)
    values (gen_random_uuid(), uid, 'expense', now(), 10, 'USD', 1, spend_wallet, now(), now());
    raise notice 'PASS 3: expense against normal wallet accepted';
  exception when others then
    raise notice 'FAIL 3: expense against normal wallet was wrongly rejected';
  end;

  -- 4. transfer INTO savings must work (contribution)
  begin
    insert into public.transactions (id, user_id, type, date, amount, currency_code, exchange_rate, source_wallet_id, destination_wallet_id, created_at, updated_at)
    values (gen_random_uuid(), uid, 'transfer', now(), 100, 'USD', 1, spend_wallet, savings_wallet, now(), now());
    raise notice 'PASS 4: transfer into savings accepted';
  exception when others then
    raise notice 'FAIL 4: transfer into savings was wrongly rejected';
  end;

  -- 5. transfer OUT of savings must work (withdrawal)
  begin
    insert into public.transactions (id, user_id, type, date, amount, currency_code, exchange_rate, source_wallet_id, destination_wallet_id, created_at, updated_at)
    values (gen_random_uuid(), uid, 'transfer', now(), 50, 'USD', 1, savings_wallet, spend_wallet, now(), now());
    raise notice 'PASS 5: transfer out of savings accepted';
  exception when others then
    raise notice 'FAIL 5: transfer out of savings was wrongly rejected';
  end;

  -- 6. adjustment on savings must work (the correction escape hatch)
  begin
    insert into public.transactions (id, user_id, type, date, amount, currency_code, exchange_rate, source_wallet_id, created_at, updated_at)
    values (gen_random_uuid(), uid, 'adjustment', now(), -5, 'USD', 1, savings_wallet, now(), now());
    raise notice 'PASS 6: adjustment on savings accepted';
  exception when others then
    raise notice 'FAIL 6: adjustment on savings was wrongly rejected';
  end;

  -- 7. same-wallet transfer must be rejected
  begin
    insert into public.transactions (id, user_id, type, date, amount, currency_code, exchange_rate, source_wallet_id, destination_wallet_id, created_at, updated_at)
    values (gen_random_uuid(), uid, 'transfer', now(), 10, 'USD', 1, spend_wallet, spend_wallet, now(), now());
    raise notice 'FAIL 7: same-wallet transfer was accepted';
  exception when others then
    raise notice 'PASS 7: same-wallet transfer rejected';
  end;

  -- 8. zero-amount adjustment must be rejected
  begin
    insert into public.transactions (id, user_id, type, date, amount, currency_code, exchange_rate, source_wallet_id, created_at, updated_at)
    values (gen_random_uuid(), uid, 'adjustment', now(), 0, 'USD', 1, spend_wallet, now(), now());
    raise notice 'FAIL 8: zero adjustment was accepted';
  exception when others then
    raise notice 'PASS 8: zero adjustment rejected';
  end;

  -- 9. THE TOMBSTONE GUARD: an invalid row is allowed if it is soft-deleted.
  --    This is what lets the 28 legacy rows still be updated/re-pushed.
  begin
    insert into public.transactions (id, user_id, type, date, amount, currency_code, exchange_rate, source_wallet_id, destination_wallet_id, created_at, updated_at, deleted_at)
    values (gen_random_uuid(), uid, 'transfer', now(), 10, 'USD', 1, spend_wallet, spend_wallet, now(), now(), now());
    raise notice 'PASS 9: tombstoned invalid row accepted (legacy rows stay updatable)';
  exception when others then
    raise notice 'FAIL 9: tombstoned invalid row rejected — legacy rows are now stuck';
  end;

  -- 10. savings wallet currency is locked once it has a transaction
  begin
    update public.wallets set currency_code = 'KHR' where id = savings_wallet;
    raise notice 'FAIL 10: savings wallet currency change was accepted';
  exception when others then
    raise notice 'PASS 10: savings wallet currency locked';
  end;

  -- 11. normal wallet currency must STILL be editable (out-of-scope boundary)
  begin
    update public.wallets set currency_code = 'KHR' where id = spend_wallet;
    raise notice 'PASS 11: normal wallet currency still editable';
  exception when others then
    raise notice 'FAIL 11: normal wallet currency was wrongly locked';
  end;

  -- 12. savings kind is terminal (savings -> normal rejected)
  begin
    update public.wallets set kind = 'normal' where id = savings_wallet;
    raise notice 'FAIL 12: savings wallet was demoted to normal';
  exception when others then
    raise notice 'PASS 12: savings kind is terminal';
  end;
end $$;

rollback;

-- Confirm nothing persisted (must return 0):
select count(*) as leftover_smoke_rows
from public.wallets where name like 'ZZ Smoke%' or name = 'ZZ No Target';
