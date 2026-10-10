-- Workers test. Run as postgres. Always ends with an exception, so nothing is kept. Look for "WORKERS TEST PASS".
--   Worker Rs 1,000/day (plant): 3 days -> owed 3,000; pay 2,000 -> owed 1,000; pay 1,500 -> owed 0, advance 500;
--   1 more day -> advance used, owed 500. Cash down 3,500 in all. 5420 up 4,000. Debits = credits.
--   Refused: a 2100 line with no worker; correcting a work entry; deleting the 1,500 pay (the later work used its advance).
do $t$
declare
  problems text[] := '{}';
  w integer; r jsonb; v_pay2 text; h record; v_today date := (now() at time zone 'Asia/Karachi')::date;
  cash0 bigint; cash1 bigint; l0 bigint; l1 bigint; o bigint; a bigint;
  f_acc constant text := $q$select coalesce(sum(le.debit_paisa - le.credit_paisa), 0) from app.ledger_entries le join app.accounts a on a.id = le.account_id where a.code = $1$q$;
begin
  execute f_acc into cash0 using '1000';
  execute f_acc into l0 using '5420';
  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;
  w := public.save_worker(null, 'Test worker Aslam', '0300 0000000', 'day', 100000, 'plant');

  r := public.record_work(w, 3, 300000, v_today, null, 'worker-test-1');
  select owed_paisa, advance_paisa into o, a from public.v_workers where party_id = w;
  if o <> 300000 or a <> 0 then problems := problems || format('after 3 days: owed %s advance %s', o, a); end if;

  r := public.pay_worker(w, 200000, 'cash', v_today, null, 'worker-test-2');
  select owed_paisa, advance_paisa into o, a from public.v_workers where party_id = w;
  if o <> 100000 or a <> 0 then problems := problems || format('after pay 2,000: owed %s advance %s', o, a); end if;

  r := public.pay_worker(w, 150000, 'cash', v_today, null, 'worker-test-3');
  v_pay2 := r->>'event_ref';
  select owed_paisa, advance_paisa into o, a from public.v_workers where party_id = w;
  if o <> 0 or a <> 50000 or (r->>'advance_paisa')::bigint <> 50000 then problems := problems || format('after pay 1,500: owed %s advance %s', o, a); end if;

  r := public.record_work(w, 1, 100000, v_today, null, 'worker-test-4');
  select owed_paisa, advance_paisa into o, a from public.v_workers where party_id = w;
  if o <> 50000 or a <> 0 or (r->>'advance_used_paisa')::bigint <> 50000 then problems := problems || format('after 1 more day: owed %s advance %s', o, a); end if;

  if (select count(*) from public.v_worker_history where party_id = w) <> 4 then
    problems := problems || 'history does not have 4 rows'::text;
  end if;

  begin
    perform public.post_event('expense', v_today, 'unlinked wages', '[{"account":"5000","debit":100},{"account":"2100","credit":100}]', 'other', null, null, 'worker-test-5');
    problems := problems || 'a 2100 line with no worker was saved'::text;
  exception when check_violation then null;
  end;
  if (public.correct_entry_preview((select event_ref from app.events where idempotency_key = 'worker-test-1'), null, null))->>'blocker' is null then
    problems := problems || 'a work entry can be corrected in place'::text;
  end if;
  begin
    perform public.delete_entry(v_pay2, 'testing the worker delete safety', null);
    problems := problems || 'the 1,500 pay was deleted although the later work used its advance'::text;
  exception when check_violation then
    if sqlerrm not like '%wages of Test worker Aslam would not add up%' then
      problems := problems || ('delete refused for another reason: ' || sqlerrm);
    end if;
  end;
  reset role;

  execute f_acc into cash1 using '1000';
  if cash1 <> cash0 - 350000 then problems := problems || format('cash changed by %s, expected -350000', cash1 - cash0); end if;
  execute f_acc into l1 using '5420';
  if l1 <> l0 + 400000 then problems := problems || format('5420 changed by %s, expected 400000', l1 - l0); end if;
  select * into h from app.v_ledger_health;
  if h.total_debit_paisa <> h.total_credit_paisa or h.negative_cash_days <> 0 then
    problems := problems || format('ledger health: %s', to_jsonb(h));
  end if;
  if cardinality(problems) = 0 then
    raise exception 'WORKERS TEST PASS. owed 500, cash down 3,500, history %', (select jsonb_agg(to_jsonb(x) - 'party_id' - 'event_id') from public.v_worker_history x where x.party_id = w);
  end if;
  raise exception 'WORKERS TEST FAIL: %', to_jsonb(problems);
end $t$;
