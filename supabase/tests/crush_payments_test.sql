-- Crushing costs + suppliers test. Run as postgres. Always ends with an exception, so nothing is kept.
-- Look for "CRUSH PAYMENTS TEST PASS".
--   A. 1,000 kg BATCH-001 -> 950 kg Fine; labour 1,200 paid now + electricity 800 later to "Electricity bill":
--      cash -1,200; 2000 +800 linked to that party; Rs 10.01/kg; 5250 unchanged.
--      Pay "Electricity bill" 1,000 -> 800 clears the debt, 200 goes to 5100; owed 0.
--   B. Labour 2,000 (1,500 now, 500 later to a test worker) + electricity 800 later to "MEPCO bijli bill" + bags 500
--      now: cash -2,000; 2000 +1,300 split worker 500 / MEPCO 800; the salt cost includes all 3,300.
--      Pay the worker 500 -> 0. Pay him 1 more -> refused.
--   C. MEPCO real bill 600 (less than the 800 estimate): 200 stays owed; "clear leftover" (reason) -> 0, 5100 -200.
--   D. Deleting crush B now (the worker is paid) is refused: he would be paid more than owed.
--   E. A 2000 line without a supplier is refused; a purchase on credit links its supplier.
--   F. Debits = credits.
do $t$
declare
  problems text[] := '{}';
  r jsonb; p jsonb; g bigint; val bigint; v_ev_b text; v_worker int; v_mepco int; v_elec int; msg text;
  cash0 bigint; s0 bigint; u0 bigint; w0 bigint; rock_ppk numeric;
  v_today date := (now() at time zone 'Asia/Karachi')::date;
  f_acc constant text := $q$select coalesce(sum(le.debit_paisa - le.credit_paisa), 0) from app.ledger_entries le join app.accounts a on a.id = le.account_id where a.code = $1$q$;
  f_val constant text := $q$select coalesce(sum(m.value_paisa), 0) from app.movements m join app.batches b on b.id = m.batch_id where b.batch_code = $1$q$;
  f_owed constant text := $q$select coalesce((select owed_paisa from public.v_supplier_balances where lower(name) = lower($1)), 0)$q$;
begin
  execute f_acc into cash0 using '1000';
  execute f_acc into s0 using '2000';
  execute f_acc into u0 using '5100';
  execute f_acc into w0 using '5250';
  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;

  -- A ------------------------------------------------------------------------------------------------------------
  p := public.crush_preview('BATCH-001', 1000000, '[{"product_code":"SALT_BULK","qty_grams":950000}]', 50000,
         '[{"kind":"labour","amount_paisa":120000,"paid_now_paisa":120000},{"kind":"electricity","amount_paisa":80000,"paid_now_paisa":0,"owed_to":"Electricity bill"}]');
  r := public.record_crush('BATCH-001', 1000000, '[{"product_code":"SALT_BULK","qty_grams":950000}]', 50000,
         '[{"kind":"labour","amount_paisa":120000,"paid_now_paisa":120000},{"kind":"electricity","amount_paisa":80000,"paid_now_paisa":0,"owed_to":"Electricity bill"}]',
         v_today, 'crush payments test A', 'crush-pay-test-a');
  if p->'outputs'->0->>'value_paisa' <> r->'outputs'->0->>'value_paisa' then problems := problems || format('A preview %s <> saved %s', p->'outputs', r->'outputs'); end if;
  execute f_val into val using r->'outputs'->0->>'batch_code';
  if round(val / 100.0 / 950, 2) <> 10.01 then problems := problems || format('A Rs/kg %s', round(val / 100.0 / 950, 2)); end if;
  execute f_acc into g using '1000';  if g <> cash0 - 120000 then problems := problems || format('A cash %s', g - cash0); end if;
  execute f_acc into g using '2000';  if g <> s0 - 80000 then problems := problems || format('A 2000 %s', g - s0); end if;
  execute f_owed into g using 'Electricity bill'; if g <> 80000 then problems := problems || format('A owed to Electricity bill %s', g); end if;
  execute f_acc into g using '5250';  if g <> w0 then problems := problems || '5250 changed'::text; end if;
  select party_id into v_elec from public.v_supplier_balances where name = 'Electricity bill';
  r := public.pay_supplier(v_elec, 100000, v_today, 'real bill', 'crush-pay-test-a-pay');
  if (r->>'cleared_paisa')::bigint <> 80000 or (r->>'extra_paisa')::bigint <> 20000 or r->>'extra_account' <> '5100' then problems := problems || format('A pay %s', r); end if;
  execute f_owed into g using 'Electricity bill'; if g <> 0 then problems := problems || format('A owed after pay %s', g); end if;
  execute f_acc into g using '5100';  if g <> u0 + 20000 then problems := problems || format('A 5100 %s', g - u0); end if;
  execute f_acc into g using '1000';  if g <> cash0 - 220000 then problems := problems || format('A cash after pay %s', g - cash0); end if;

  -- B ------------------------------------------------------------------------------------------------------------
  execute f_acc into cash0 using '1000';
  execute f_acc into s0 using '2000';
  r := public.record_crush('BATCH-001', 1000000, '[{"product_code":"SALT_BULK","qty_grams":700000},{"product_code":"SALT_ROCK_COARSE","qty_grams":250000}]', 50000,
         '[{"kind":"labour","amount_paisa":200000,"paid_now_paisa":150000,"owed_to":"Test worker (crush test)","expected_on":"2026-10-12"},
           {"kind":"electricity","amount_paisa":80000,"paid_now_paisa":0,"owed_to":"MEPCO bijli bill"},
           {"kind":"bags","amount_paisa":50000,"paid_now_paisa":50000}]',
         v_today, 'crush payments test B', 'crush-pay-test-b');
  v_ev_b := r->>'event_ref';
  if (r->>'cost_paisa')::bigint <> 330000 or (r->>'pool_paisa')::bigint <> (r->>'input_value_paisa')::bigint + 330000
     or (r->'outputs'->0->>'value_paisa')::bigint + (r->'outputs'->1->>'value_paisa')::bigint <> (r->>'pool_paisa')::bigint then
    problems := problems || format('B cost %s', r);
  end if;
  execute f_acc into g using '1000';  if g <> cash0 - 200000 then problems := problems || format('B cash %s', g - cash0); end if;
  execute f_acc into g using '2000';  if g <> s0 - 130000 then problems := problems || format('B 2000 %s', g - s0); end if;
  execute f_owed into g using 'Test worker (crush test)'; if g <> 50000 then problems := problems || format('B worker owed %s', g); end if;
  execute f_owed into g using 'MEPCO bijli bill'; if g <> 80000 then problems := problems || format('B MEPCO owed %s', g); end if;
  if (select count(*) from public.v_ledger_lines l join public.v_events_with_party e on e.id = l.event_id where e.event_ref = v_ev_b and l.account_code = '2000') <> 2 then
    problems := problems || 'B: expected two 2000 lines'::text;
  end if;
  select party_id into v_worker from public.v_supplier_balances where name = 'Test worker (crush test)';
  select party_id into v_mepco from public.v_supplier_balances where name = 'MEPCO bijli bill';
  r := public.pay_supplier(v_worker, 50000, v_today, null, 'crush-pay-test-b-pay');
  execute f_owed into g using 'Test worker (crush test)'; if g <> 0 then problems := problems || format('B worker after pay %s', g); end if;
  begin
    perform public.pay_supplier(v_worker, 100, v_today, null, 'crush-pay-test-b-over');
    problems := problems || 'B: paid the worker more than owed'::text;
  exception when check_violation then msg := sqlerrm;
  end;

  -- C ------------------------------------------------------------------------------------------------------------
  execute f_acc into u0 using '5100';
  r := public.pay_supplier(v_mepco, 60000, v_today, 'bill smaller than estimate', 'crush-pay-test-c-pay');
  if (r->>'owed_after_paisa')::bigint <> 20000 or (r->>'extra_paisa')::bigint <> 0 then problems := problems || format('C pay %s', r); end if;
  begin
    perform public.clear_supplier_leftover(v_mepco, v_today, 'x', 'crush-pay-test-c-x');
    problems := problems || 'C: leftover cleared with a 1-letter reason'::text;
  exception when check_violation then null;
  end;
  r := public.clear_supplier_leftover(v_mepco, v_today, 'real bill was Rs 600', 'crush-pay-test-c-clear');
  execute f_owed into g using 'MEPCO bijli bill'; if g <> 0 then problems := problems || format('C MEPCO after clear %s', g); end if;
  execute f_acc into g using '5100';  if g <> u0 - 20000 then problems := problems || format('C 5100 %s', g - u0); end if;
  begin
    perform public.clear_supplier_leftover(v_worker, v_today, 'not a bill at all', 'crush-pay-test-c-worker');
    problems := problems || 'C: a worker debt was cleared as a bill leftover'::text;
  exception when check_violation then null;
  end;

  -- D ------------------------------------------------------------------------------------------------------------
  begin
    perform public.delete_entry(v_ev_b, 'crush test delete');
    problems := problems || 'D: crush deleted although its worker was already paid'::text;
  exception when check_violation then
    -- MEPCO is named too: it was paid 600 and its 200 leftover cleared, so without the crush it would be below 0
    if sqlerrm not like 'Cannot delete: we would have paid %Test worker (crush test) more than we owe%' then problems := problems || format('D: %s', sqlerrm); end if;
  end;
  reset role;

  -- E ------------------------------------------------------------------------------------------------------------
  begin
    insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
    values ((select id from app.events where event_ref = v_ev_b), 99, (select id from app.accounts where code = '2000'), 0, 1);
    problems := problems || 'E: unlinked 2000 line accepted'::text;
  exception when check_violation then
    if sqlerrm not like '%needs the supplier%' then problems := problems || format('E: %s', sqlerrm); end if;
  end;
  set local role authenticated;
  r := public.record_purchase('Test salt seller (crush test)', 'SALT_ROCK', 'KHANEWAL_PLANT', 100000, 75000, false, v_today, null, null, 'crush-pay-test-e', null);
  reset role;
  if (select l.party_id from app.ledger_entries l join app.events e on e.id = l.event_id join app.accounts a on a.id = l.account_id
       where e.event_ref = r->>'event_ref' and a.code = '2000') is distinct from (select id from app.parties where name = 'Test salt seller (crush test)' and kind = 'supplier') then
    problems := problems || format('E: purchase on credit not linked: %s', r);
  end if;

  -- F ------------------------------------------------------------------------------------------------------------
  if (select sum(debit_paisa) - sum(credit_paisa) from app.ledger_entries) <> 0 then problems := problems || 'debits <> credits'::text; end if;

  if cardinality(problems) = 0 then
    raise exception 'CRUSH PAYMENTS TEST PASS. Overpay refused: "%"', msg;
  end if;
  raise exception 'CRUSH PAYMENTS TEST FAIL: %', to_jsonb(problems);
end $t$;
