-- Crush cost test (one crushing rate per kg of rock, loss absorbed). Run as postgres. Always ends with an exception,
-- so nothing is kept. Look for "CRUSH COST TEST PASS".
--   1. Rao's example: 1,000 kg of BATCH-001 at Rs 2/kg of rock -> plant cost Rs 2,000; 950 kg Fine, 50 kg loss.
--      Output batch: 950 kg, value = rock value used + 2,000, Rs 10.01/kg. Preview = saved. Cash unchanged.
--      5490 credited 2,000. 5250 unchanged. BATCH-001 -1,000 kg. The loss row has no value. v_last_crush_rate = 200.
--   2. Same run split Fine 700 + Daana 250: both outputs at Rs 10.01/kg, values add up to the same total.
--   3. Refusals: a negative rate, kg that do not add up, not a crush output, too many kg, not rock salt.
--   4. Books balance; stock ties to the ledger.
do $t$
declare
  problems text[] := '{}';
  r jsonb; p jsonb; v_fine text; v_daana text;
  rock0 bigint; cash0 bigint; w0 bigint; c0 bigint; rockval0 bigint; rockval_used bigint;
  f_kg constant text := $q$select coalesce(sum(case m.direction when 'in' then m.qty_grams when 'out' then -m.qty_grams else 0 end), 0)
                           from app.movements m join app.batches b on b.id = m.batch_id where b.batch_code = $1$q$;
  f_val constant text := $q$select coalesce(sum(m.value_paisa), 0) from app.movements m join app.batches b on b.id = m.batch_id where b.batch_code = $1$q$;
  f_acc constant text := $q$select coalesce(sum(le.debit_paisa - le.credit_paisa), 0) from app.ledger_entries le join app.accounts a on a.id = le.account_id where a.code = $1$q$;
  g bigint; val bigint; ppk numeric; q text; h record; refusals jsonb := '[]';
  v_today date := (now() at time zone 'Asia/Karachi')::date;
begin
  execute f_kg into rock0 using 'BATCH-001';
  execute f_val into rockval0 using 'BATCH-001';
  execute f_acc into cash0 using '1000';
  execute f_acc into w0 using '5250';
  execute f_acc into c0 using '5490';
  rockval_used := round(rockval0::numeric * 1000000 / rock0);

  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;

  -- 1
  p := public.crush_preview('BATCH-001', 1000000, '[{"product_code":"SALT_BULK","qty_grams":950000}]', 50000, 200);
  r := public.record_crush('BATCH-001', 1000000, '[{"product_code":"SALT_BULK","qty_grams":950000}]', 50000, 200, v_today, 'crush cost test', 'crush-cost-test-1');
  if (p->>'plant_cost_paisa')::bigint <> 200000 or p->'outputs'->0->>'value_paisa' <> r->'outputs'->0->>'value_paisa' then
    problems := problems || format('preview %s vs saved %s', p, r);
  end if;
  if (select rate_paisa_per_kg from public.v_last_crush_rate) is distinct from 200 then
    problems := problems || format('last rate %s', (select rate_paisa_per_kg from public.v_last_crush_rate));
  end if;
  v_fine := r->'outputs'->0->>'batch_code';
  reset role;
  execute f_kg into g using v_fine;
  execute f_val into val using v_fine;
  ppk := round(val / 100.0 / (g / 1000.0), 2);
  if g <> 950000 or val <> rockval_used + 200000 or ppk <> 10.01 then
    problems := problems || format('example: %s g, value %s (expected %s), Rs %s/kg', g, val, rockval_used + 200000, ppk);
  end if;
  execute f_acc into g using '1000';
  if g <> cash0 then problems := problems || format('cash changed by %s', g - cash0); end if;
  execute f_acc into g using '5490';
  if g <> c0 - 200000 then problems := problems || format('5490 changed by %s, expected -200000', g - c0); end if;
  execute f_acc into g using '5250';
  if g <> w0 then problems := problems || format('5250 changed: %s -> %s', w0, g); end if;
  execute f_kg into g using 'BATCH-001';
  if g <> rock0 - 1000000 then problems := problems || format('BATCH-001 %s g, expected %s', g, rock0 - 1000000); end if;
  if (select sum(m.value_paisa) from app.movements m join app.events e on e.id = m.event_id where e.event_ref = r->>'event_ref' and m.direction = 'wastage') <> 0 then
    problems := problems || 'loss movement has a value'::text;
  end if;
  if exists (select 1 from app.ledger_entries le join app.events e on e.id = le.event_id join app.accounts a on a.id = le.account_id
              where e.event_ref = r->>'event_ref' and a.code in ('1000', '1050', '2000')) then
    problems := problems || 'the crush touched cash, bank or suppliers'::text;
  end if;

  -- 2
  set local role authenticated;
  r := public.record_crush('BATCH-001', 1000000, '[{"product_code":"SALT_BULK","qty_grams":700000},{"product_code":"SALT_ROCK_COARSE","qty_grams":250000}]',
                           50000, 200, v_today, 'crush cost test 2', 'crush-cost-test-2');
  reset role;
  v_fine := r->'outputs'->0->>'batch_code';
  v_daana := r->'outputs'->1->>'batch_code';
  execute f_kg into g using v_fine;  execute f_val into val using v_fine;
  if g <> 700000 or round(val / 100.0 / (g / 1000.0), 2) <> 10.01 then problems := problems || format('fine %s g value %s', g, val); end if;
  execute f_kg into g using v_daana; execute f_val into val using v_daana;
  if g <> 250000 or round(val / 100.0 / (g / 1000.0), 2) <> 10.01 then problems := problems || format('daana %s g value %s', g, val); end if;
  if ((r->'outputs'->0->>'value_paisa')::bigint + (r->'outputs'->1->>'value_paisa')::bigint)
     <> round((rockval0 - rockval_used)::numeric * 1000000 / (rock0 - 1000000)) + 200000 then
    problems := problems || format('split total %s', r->'outputs');
  end if;

  -- 3
  set local role authenticated;
  foreach q in array array[
    $q$select public.crush_preview('BATCH-001', 1000000, '[{"product_code": "SALT_BULK", "qty_grams": 999000}]', 1000, -1)$q$,
    $q$select public.crush_preview('BATCH-001', 1000000, '[{"product_code": "SALT_BULK", "qty_grams": 990000}]', 1000, 200)$q$,
    $q$select public.crush_preview('BATCH-001', 1000000, '[{"product_code": "SALT_RAW", "qty_grams": 1000000}]', 0, 200)$q$,
    $q$select public.crush_preview('BATCH-001', 99000000, '[{"product_code": "SALT_BULK", "qty_grams": 99000000}]', 0, 200)$q$,
    $q$select public.crush_preview('BATCH-075', 1000000, '[{"product_code": "SALT_BULK", "qty_grams": 1000000}]', 0, 200)$q$] loop
    begin
      execute q;
      problems := problems || ('not refused: ' || q);
    exception when check_violation then
      refusals := refusals || to_jsonb(sqlerrm);
    end;
  end loop;
  reset role;

  -- 4
  select * into h from app.v_ledger_health;
  if h.total_debit_paisa <> h.total_credit_paisa or h.stock_ledger_paisa <> h.stock_movements_paisa
     or h.stock_mismatched_accounts <> 0 or h.negative_cash_days <> 0 then
    problems := problems || format('ledger health: %s', to_jsonb(h));
  end if;
  if cardinality(problems) = 0 then
    raise exception 'CRUSH COST TEST PASS. 950 kg at Rs %/kg (value %), plant cost 2,000 to 5490, split %. Refusals: %', ppk, rockval_used + 200000, r->'outputs', refusals;
  end if;
  raise exception 'CRUSH COST TEST FAIL: %', to_jsonb(problems);
end $t$;
