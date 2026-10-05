-- Reason-rule test. Run as postgres. Always ends with an exception, so nothing is kept. Look for "REASON TEST PASS".
--   1. app.reason_problem: "x", "1234", "ab 12 !!" are refused; "baba confirmed", "test" and Urdu "بابا نے کہا" pass.
--   2. delete_entry (as Rao) refuses "x" and "1234" before touching anything, and accepts "baba confirmed".
--   3. correct_entry (as Rao) refuses "x" and "1234", and accepts "baba confirmed".
-- The entries used are the newest plain app expense with no correction (delete) and the same one (correct).
do $t$
declare
  problems text[] := '{}';
  v_ref text;
  v_lines jsonb;
  v_alt text;
  r jsonb;
  bad text;
begin
  foreach bad in array array['x', '1234', 'ab 12 !!', ''] loop
    if app.reason_problem(bad) is null then problems := problems || format('reason_problem accepted %L', bad); end if;
  end loop;
  foreach bad in array array['baba confirmed', 'test', 'بابا نے کہا'] loop
    if app.reason_problem(bad) is not null then problems := problems || format('reason_problem refused %L', bad); end if;
  end loop;

  select e.event_ref into v_ref from app.events e
   where e.source = 'app' and e.event_type = 'expense'
     and not exists (select 1 from app.events c where c.source_ref = e.event_ref) order by e.id desc limit 1;
  -- the correct version: the same lines, the debit moved to another expense account
  select jsonb_agg(jsonb_build_object('account', a.code, 'debit', le.debit_paisa, 'credit', le.credit_paisa) order by le.entry_seq),
         (select x.code from app.accounts x where x.type = 'expense' and x.code like '5%' and x.code not in (select a2.code from app.ledger_entries l2 join app.accounts a2 on a2.id = l2.account_id where l2.event_id = e.id) order by x.code limit 1)
    into v_lines, v_alt
    from app.events e join app.ledger_entries le on le.event_id = e.id join app.accounts a on a.id = le.account_id
   where e.event_ref = v_ref group by e.id;
  v_lines := (select jsonb_agg(case when (l->>'debit')::bigint > 0 then l || jsonb_build_object('account', v_alt) else l end) from jsonb_array_elements(v_lines) l);

  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;

  foreach bad in array array['x', '1234'] loop
    begin
      perform public.correct_entry(v_ref, null, v_lines, bad, 'reason-test-' || bad);
      problems := problems || format('correct_entry accepted %L', bad);
    exception when check_violation then
      if sqlerrm not like '%at least 4 letters%' then problems := problems || format('correct %L: %s', bad, sqlerrm); end if;
    end;
    begin
      perform public.delete_entry(v_ref, bad);
      problems := problems || format('delete_entry accepted %L', bad);
    exception when check_violation then
      if sqlerrm not like 'Cannot delete: Write a short reason%' then problems := problems || format('delete %L: %s', bad, sqlerrm); end if;
    end;
  end loop;

  r := public.correct_entry(v_ref, null, v_lines, 'baba confirmed', 'reason-test-ok');
  if jsonb_array_length(r->'event_refs') < 1 then problems := problems || format('correct with good reason: %s', r); end if;
  -- the correction now points to v_ref, so delete the correction itself (needs UNDO) with a good reason
  r := public.delete_entry(r->'event_refs'->>0, 'baba confirmed', 'UNDO');
  if r->>'deleted_id' is null then problems := problems || format('delete with good reason: %s', r); end if;
  reset role;

  if cardinality(problems) = 0 then
    raise exception 'REASON TEST PASS. Entry % (debit moved to %): bad reasons refused, "baba confirmed" accepted by correct and delete.', v_ref, v_alt;
  end if;
  raise exception 'REASON TEST FAIL: %', to_jsonb(problems);
end $t$;
