-- Crush-run test (ledger fix A). Run as postgres. It ALWAYS ends with an exception, so nothing is kept
-- (it does use up event numbers). Look for "CRUSH TEST PASS".
--   1. Rao's case: BATCH-001, 1000 kg in, 1 kg wastage, 999 kg out, Rs 3 conversion on credit
--      -> Cr 1200 7,512.85 · Dr 1210 7,508.33 · Dr 5250 7.52 · Cr 2000 3.00; the preview gives the same lines;
--      the value sent by the form is ignored; the supplier is on the entry.
--   2. Two grades with wastage: exact to the paisa, last grade takes the remainder.
--   3. Zero wastage: no 5250 line, the whole pool goes to the output.
--   4. Refusals: credit without supplier, kg that do not add up, a grade that is not a crush output,
--      more kg than the batch holds.
--   5. The books still balance and stock still ties to the ledger.
do $test$
declare
  c_rao constant text := '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}';
  problems text[] := '{}'; r jsonb; p jsonb; lines jsonb; ev record; h record; q text;
  v_pool bigint; v_wast bigint; v_share bigint; v_first bigint; v_out jsonb;
begin
  perform set_config('request.jwt.claims', c_rao, true);
  set local role authenticated;

  -- 1. Rao's case
  p := public.crush_run_preview('BATCH-001', 1000000, '[{"product_code": "SALT_ROCK_MESH", "qty_grams": 999000}]', 1000, 300, false);
  r := public.record_process_run('BATCH-001', 1000000, '[{"product_code": "SALT_ROCK_MESH", "qty_grams": 999000, "value_paisa": 1}]',
                                 1000, 300, false, (now() at time zone 'Asia/Karachi')::date, 'crush test', null, 'test-crush-1', 'Test Contractor');
  select jsonb_agg(jsonb_build_object('account', l.account_code, 'debit', l.debit_paisa, 'credit', l.credit_paisa) order by l.entry_seq)
    into lines from public.v_ledger_lines l join app.events e on e.id = l.event_id where e.event_ref = r->>'event_ref';
  if lines is distinct from '[{"account": "1200", "debit": 0, "credit": 751285}, {"account": "1210", "debit": 750833, "credit": 0},
                              {"account": "5250", "debit": 752, "credit": 0}, {"account": "2000", "debit": 0, "credit": 300}]'::jsonb then
    problems := problems || format('case 1 lines: %s', lines);
  end if;
  if p->'lines' is distinct from lines then problems := problems || format('case 1 preview %s differs from saved %s', p->'lines', lines); end if;
  select e.party_type, e.party_name into ev from app.events e where e.event_ref = r->>'event_ref';
  if ev.party_type is distinct from 'supplier' or ev.party_name is distinct from 'Test Contractor' then
    problems := problems || format('case 1 supplier not on entry: %s / %s', ev.party_type, ev.party_name);
  end if;

  -- 2. two grades with wastage
  p := public.crush_run_preview('BATCH-001', 1000000,
         '[{"product_code": "SALT_BULK", "qty_grams": 600000}, {"product_code": "SALT_ROCK_COARSE", "qty_grams": 390000}]', 10000, 500000, true);
  r := public.record_process_run('BATCH-001', 1000000,
         '[{"product_code": "SALT_BULK", "qty_grams": 600000}, {"product_code": "SALT_ROCK_COARSE", "qty_grams": 390000}]',
         10000, 500000, true, (now() at time zone 'Asia/Karachi')::date, 'crush test', null, 'test-crush-2', null);
  v_pool := (p->>'input_value_paisa')::bigint + 500000;
  v_wast := round(v_pool::numeric * 10000 / 1000000);
  v_share := v_pool - v_wast;
  v_first := round(v_share::numeric * 600000 / 990000);
  if (p->>'pool_paisa')::bigint <> v_pool or (p->>'wastage_value_paisa')::bigint <> v_wast
     or (p->'outputs'->0->>'value_paisa')::bigint <> v_first or (p->'outputs'->1->>'value_paisa')::bigint <> v_share - v_first then
    problems := problems || format('case 2 values: %s', p);
  end if;
  select jsonb_agg(jsonb_build_object('account', l.account_code, 'debit', l.debit_paisa, 'credit', l.credit_paisa) order by l.entry_seq)
    into lines from public.v_ledger_lines l join app.events e on e.id = l.event_id where e.event_ref = r->>'event_ref';
  if p->'lines' is distinct from lines then problems := problems || format('case 2 preview %s differs from saved %s', p->'lines', lines); end if;
  if (select sum((x->>'value_paisa')::bigint) from jsonb_array_elements(r->'outputs') x) <> v_share then
    problems := problems || format('case 2 saved outputs do not add up: %s', r->'outputs');
  end if;

  -- 3. zero wastage
  p := public.crush_run_preview('BATCH-001', 500000, '[{"product_code": "SALT_BULK", "qty_grams": 500000}]', 0, 0, true);
  if jsonb_array_length(p->'lines') <> 2 or (p->'lines'->1->>'debit')::bigint <> (p->>'input_value_paisa')::bigint
     or (p->>'wastage_value_paisa')::bigint <> 0 then
    problems := problems || format('case 3: %s', p);
  end if;

  -- 4. refusals, each with its reason
  foreach q in array array[
    $q$select public.record_process_run('BATCH-001', 1000000, '[{"product_code": "SALT_BULK", "qty_grams": 999000}]', 1000, 300, false, current_date, null, null, 'test-crush-r1', null)$q$,
    $q$select public.crush_run_preview('BATCH-001', 1000000, '[{"product_code": "SALT_BULK", "qty_grams": 990000}]', 1000, 0, true)$q$,
    $q$select public.crush_run_preview('BATCH-001', 1000000, '[{"product_code": "SALT_RAW", "qty_grams": 1000000}]', 0, 0, true)$q$,
    $q$select public.crush_run_preview('BATCH-001', 99000000, '[{"product_code": "SALT_BULK", "qty_grams": 99000000}]', 0, 0, true)$q$,
    $q$select public.crush_run_preview('BATCH-075', 1000000, '[{"product_code": "SALT_BULK", "qty_grams": 1000000}]', 0, 0, true)$q$] loop
    begin
      execute q;
      problems := problems || ('not refused: ' || q);
    exception when check_violation then
      v_out := coalesce(v_out, '[]') || to_jsonb(sqlerrm); -- refused as expected; keep the reason for the report
    end;
  end loop;
  reset role;

  -- 5. books still balance; stock ties to the ledger
  select * into h from app.v_ledger_health;
  if h.total_debit_paisa <> h.total_credit_paisa or h.stock_ledger_paisa <> h.stock_movements_paisa
     or h.stock_mismatched_accounts <> 0 or h.negative_cash_days <> 0 then
    problems := problems || format('ledger health: %s', to_jsonb(h));
  end if;

  if cardinality(problems) = 0 then
    raise exception 'CRUSH TEST PASS. Refusals: %', v_out;
  end if;
  raise exception 'CRUSH TEST FAIL: %', to_jsonb(problems);
end $test$;
