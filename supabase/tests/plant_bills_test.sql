-- Plant bills test. Run as postgres. Always ends with an exception, so nothing is kept. Look for "PLANT BILLS TEST PASS".
--   1. Plant electricity Rs 1,000 paid from cash: Dr 5410 / Cr 1000.
--   2. Plant labour Rs 2,000 on credit to "Plant test worker": Dr 5420 / Cr 2000 linked to that supplier; the
--      supplier list shows Rs 2,000 owed. A 2000 line with no supplier is refused.
--   3. Crush 1,000 kg of BATCH-001 at Rs 2/kg -> 5490 credited Rs 2,000.
--   4. v_plant_rate_check this month: bills 3,000, charged 2,000, under-charged 1,000, rock 1,000 kg, suggested Rs 3/kg.
--   5. Books balance.
do $t$
declare
  problems text[] := '{}';
  r record; h record; v_month date := date_trunc('month', (now() at time zone 'Asia/Karachi')::date)::date;
  v_today date := (now() at time zone 'Asia/Karachi')::date;
  b0 bigint; c0 bigint; k0 bigint; cash0 bigint; cash1 bigint;
  f_acc constant text := $q$select coalesce(sum(le.debit_paisa - le.credit_paisa), 0) from app.ledger_entries le join app.accounts a on a.id = le.account_id where a.code = $1$q$;
begin
  select coalesce(actual_bills_paisa, 0), coalesce(charged_paisa, 0), coalesce(rock_crushed_grams, 0) into b0, c0, k0
    from public.v_plant_rate_check where month = v_month;
  b0 := coalesce(b0, 0); c0 := coalesce(c0, 0); k0 := coalesce(k0, 0);
  execute f_acc into cash0 using '1000';

  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;
  perform public.post_event('expense', v_today, 'plant test electricity',
    '[{"account":"5410","debit":100000},{"account":"1000","credit":100000}]', 'other', null, null, 'plant-test-1');
  perform public.post_event('expense', v_today, 'plant test labour on credit',
    '[{"account":"5420","debit":200000},{"account":"2000","credit":200000,"party":"Plant test worker"}]', 'other', null, null, 'plant-test-2');
  begin
    perform public.post_event('expense', v_today, 'plant test no supplier',
      '[{"account":"5420","debit":100},{"account":"2000","credit":100}]', 'other', null, null, 'plant-test-3');
    problems := problems || 'a 2000 line with no supplier was saved'::text;
  exception when check_violation then null;
  end;
  perform public.record_crush('BATCH-001', 1000000, '[{"product_code":"SALT_BULK","qty_grams":950000}]', 50000, 200, v_today, 'plant test', 'plant-test-4');
  if (select owed_paisa from public.v_supplier_balances where name = 'Plant test worker') is distinct from 200000 then
    problems := problems || format('supplier owed %s', (select owed_paisa from public.v_supplier_balances where name = 'Plant test worker'));
  end if;
  select * into r from public.v_plant_rate_check where month = v_month;
  reset role;

  if r.actual_bills_paisa - b0 <> 300000 or r.charged_paisa - c0 <> 200000 or r.rock_crushed_grams - k0 <> 1000000 then
    problems := problems || format('rate check row %s', to_jsonb(r));
  end if;
  if b0 = 0 and c0 = 0 and k0 = 0 and (r.under_charged_paisa <> 100000 or r.suggested_rate_paisa_per_kg <> 300) then
    problems := problems || format('difference / suggested rate %s', to_jsonb(r));
  end if;
  execute f_acc into cash1 using '1000';
  if cash1 <> cash0 - 100000 then problems := problems || format('cash changed by %s, expected -100000', cash1 - cash0); end if;

  select * into h from app.v_ledger_health;
  if h.total_debit_paisa <> h.total_credit_paisa or h.stock_ledger_paisa <> h.stock_movements_paisa
     or h.stock_mismatched_accounts <> 0 or h.negative_cash_days <> 0 then
    problems := problems || format('ledger health: %s', to_jsonb(h));
  end if;
  if cardinality(problems) = 0 then
    raise exception 'PLANT BILLS TEST PASS. %', to_jsonb(r);
  end if;
  raise exception 'PLANT BILLS TEST FAIL: %', to_jsonb(problems);
end $t$;
