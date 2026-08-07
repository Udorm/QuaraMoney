-- Rollback for the 2026-08-07 pre-migration junk-row cleanup.
--
-- What was done: 28 rows were TOMBSTONED (deleted_at set), not hard-deleted.
-- All row data remains intact in public.transactions, so this restores them
-- exactly. Cleanup was balance-neutral:
--   * 24 transfers had source_wallet_id = destination_wallet_id (same wallet,
--     "Pay Credit Card" sample seed) -> net zero effect on any balance.
--   * 4 expenses had source_wallet_id IS NULL -> attached to no wallet.
--
-- NOTE: after the savings-wallet migration is applied, restoring these rows
-- puts invalid-shaped rows back in the table. They are exempt from the
-- validation trigger only while tombstoned; un-tombstoning them will fail
-- unless you also fix their shape (assign a source wallet / distinct
-- destination) in the same statement.

update public.transactions
set deleted_at = null,
    updated_at = now()
where id in (
  -- 24 same-wallet "Pay Credit Card" sample transfers
  'bb28e8f5-0cda-4014-aa54-92442c2e955c','9748e540-3a91-4309-87a6-9f2980f88ef4',
  'ae35f83a-23ab-4c28-b948-ae1acedd6d6f','7e5231b0-3895-474d-8c10-200b7278ed32',
  '8344c384-4519-4d98-970d-c2f3cc8ffe0f','2ca2b48d-0575-4439-8408-b7cde67e0837',
  '2f530cbb-96eb-43da-9a25-fe4fa55afb6a','2c8ed4c0-3526-4f28-8aa0-f058c2fb252a',
  '2b63ef42-d3ce-47f5-9d09-6fa1ff0b307d','aeb0e2c4-b21b-4d43-a357-ccee58e56263',
  '290f0fd7-4d39-487e-b13f-fbd67700c09e','8b2b558f-3b28-4b7d-bd1e-0c66c694f70c',
  'cb32409b-55e3-4632-b03d-4bd6925f01ed','7031215a-025e-467b-84d5-46ca9aabebcd',
  '37680b26-a23e-4c90-9015-173f1364adf7','1e924bdf-44ac-417a-bbd1-1f4725e347db',
  '9f46f8a1-7a40-45cd-bf5a-8151e60fa5ac','f28edbbd-ec03-43fc-92f2-6a212a656f8c',
  'f5013c64-8464-4341-86e2-54c2ff3ecfd3','29d798bd-3bfe-4ea9-a828-f0eac2277dbd',
  '93b12f07-fdd6-4729-b4ee-1c472624b057','48a851d6-fa56-4e1a-8574-57e3231dc14b',
  'eeb79104-5b60-4c8b-86c0-5103b78baa08','8bf80777-8df5-4565-8dc6-09460241db00',
  -- 4 orphan expenses (no source wallet), 2026-06-22 test debris
  'ec09af0b-0576-4b9c-83a6-5a8e1916ecc2','caab05cf-8851-421f-b8f9-cab6ac5237e7',
  '5c808eab-5728-4fd4-bc14-54376ac85347','cea7132b-2673-45b2-a969-bf18be4ebd8c'
);
