-- "Correct this entry" test (Wave 2 item 2). Run as postgres. Always ends with an exception, so nothing is kept
-- (it uses up entry numbers). Look for "CORRECT TEST PASS".
--   1. Wrong account, same date: one correction moving only the difference; preview = saved lines; points to the original.
--   2. Wrong amount: one correction for the difference.
--   3. Later date: a reversal on the original date + the correct entry on the later date, saved together.
--   4. A future date is refused and NOTHING is saved (no half correction).
--   5. Same key again: no new entries. Nothing changed: refused. Correcting again on top: refused.
--   6. Not offered: a sale, a correction itself, an entry already corrected.
--   7. The books still balance.
do $t$
declare
  problems text[] := '{}'; refs text[]; p jsonb; r jsonb; v jsonb; dl jsonb; q text; n_before int; n_after int; h record; msgs jsonb := '[]';
  v_today date := (now() at time zone 'Asia/Karachi')::date;
begin
  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;
  -- three uncorrected cash expenses (Dr expense / Cr 1000), oldest first, dated before today
  select array_agg(e.event_ref order by e.id) into refs from (
    select e.id, e.event_ref from public.v_events_with_party e
     where e.event_type = 'expense' and e.occurred_on < v_today and (public.correct_entry_preview(e.event_ref)) ->> 'blocker' is null
       and (select count(*) from public.v_ledger_lines l where l.event_id = e.id and l.account_code = '1000' and l.credit_paisa > 0) = 1
     order by e.id limit 4) e;

  -- 1. wrong account: move it to 5900
  v := public.correct_entry_preview(refs[1]);
  select x into dl from jsonb_array_elements(v->'lines') x where (x->>'debit')::bigint > 0;
  p := jsonb_build_array(jsonb_build_object('account', '5900', 'debit', (dl->>'debit')::bigint),
                         jsonb_build_object('account', '1000', 'credit', (dl->>'debit')::bigint));
  if dl->>'account' = '5900' then
    p := jsonb_set(p, '{0,account}', '"5800"');
  end if;
  v := public.correct_entry_preview(refs[1], null, p);
  r := public.correct_entry(refs[1], null, p, 'wrong account (test)', 'test-correct-1');
  if jsonb_array_length(r->'event_refs') <> 1 or v->'plan' is distinct from r->'plan' or jsonb_array_length(r->'plan'->0->'lines') <> 2 then
    problems := problems || format('case 1: preview %s saved %s', v->'plan', r);
  end if;
  if (select source_ref from public.v_events_with_party where event_ref = r->'event_refs'->>0) is distinct from refs[1] then
    problems := problems || 'case 1 correction does not point to the original'::text;
  end if;

  -- 2. wrong amount: +Rs 1 on the same accounts
  v := public.correct_entry_preview(refs[2]);
  select x into dl from jsonb_array_elements(v->'lines') x where (x->>'debit')::bigint > 0;
  p := jsonb_build_array(jsonb_build_object('account', dl->>'account', 'debit', (dl->>'debit')::bigint + 100),
                         jsonb_build_object('account', '1000', 'credit', (dl->>'debit')::bigint + 100));
  r := public.correct_entry(refs[2], null, p, 'wrong amount (test)', 'test-correct-2');
  if r->'plan'->0->'lines' is distinct from jsonb_build_array(jsonb_build_object('account', dl->>'account', 'debit', 100, 'credit', 0),
                                                              jsonb_build_object('account', '1000', 'debit', 0, 'credit', 100)) then
    problems := problems || format('case 2 lines: %s', r->'plan');
  end if;

  -- 4. (before 3) a future date: refused, nothing saved
  v := public.correct_entry_preview(refs[3]);
  select x into dl from jsonb_array_elements(v->'lines') x where (x->>'debit')::bigint > 0;
  p := jsonb_build_array(jsonb_build_object('account', dl->>'account', 'debit', (dl->>'debit')::bigint),
                         jsonb_build_object('account', '1000', 'credit', (dl->>'debit')::bigint));
  select count(*) into n_before from public.v_events_with_party;
  begin
    perform public.correct_entry(refs[3], v_today + 1, p, 'future (test)', 'test-correct-4');
    problems := problems || 'a correction dated tomorrow was accepted'::text;
  exception when check_violation then msgs := msgs || to_jsonb(sqlerrm);
  end;
  select count(*) into n_after from public.v_events_with_party;
  if n_after <> n_before then problems := problems || 'a refused correction left entries behind'::text; end if;

  -- 3. later date: reversal on the original date + correct entry one day later
  r := public.correct_entry(refs[3], (v->>'date')::date + 1, p, 'wrong date (test)', 'test-correct-3');
  if jsonb_array_length(r->'event_refs') <> 2
     or (select occurred_on from public.v_events_with_party where event_ref = r->'event_refs'->>0) <> (v->>'date')::date
     or (select occurred_on from public.v_events_with_party where event_ref = r->'event_refs'->>1) <> (v->>'date')::date + 1 then
    problems := problems || format('case 3: %s', r);
  end if;

  -- 5. retry, nothing changed, on top of a correction
  r := public.correct_entry(refs[3], (v->>'date')::date + 1, p, 'wrong date (test)', 'test-correct-3');
  if not coalesce((r->>'duplicate')::boolean, false) then problems := problems || format('retry not recognised: %s', r); end if;
  foreach q in array array[
    -- nothing changed (an untouched entry, given back exactly as it is)
    format('select public.correct_entry_preview(%L, null, %L)', refs[4], (select jsonb_agg(jsonb_build_object('account', l.account_code, 'debit', l.debit_paisa, 'credit', l.credit_paisa))
                                                                         from public.v_ledger_lines l join public.v_events_with_party e on e.id = l.event_id where e.event_ref = refs[4])),
    format('select public.correct_entry(%L, null, %L, %L, %L)', refs[2], p, 'again (test)', 'test-correct-5')] loop
    begin
      execute q;
      problems := problems || ('not refused: ' || left(q, 80));
    exception when check_violation then msgs := msgs || to_jsonb(sqlerrm);
    end;
  end loop;

  -- 6. not offered
  if public.correct_entry_preview((select event_ref from public.v_events_with_party where event_type = 'sale' order by id limit 1)) ->> 'blocker' is null
     or public.correct_entry_preview('EV-000400') ->> 'blocker' not like '%is itself a correction%'
     or public.correct_entry_preview('EV-000237') ->> 'blocker' not like '%already corrected by EV-000400%' then
    problems := problems || 'a sale, a correction or a corrected entry was offered'::text;
  end if;
  reset role;

  select * into h from app.v_ledger_health;
  if h.total_debit_paisa <> h.total_credit_paisa or h.negative_cash_days <> 0 then problems := problems || format('ledger health %s', to_jsonb(h)); end if;

  if cardinality(problems) = 0 then
    raise exception 'CORRECT TEST PASS on %. Refusals: %', to_jsonb(refs), msgs;
  end if;
  raise exception 'CORRECT TEST FAIL: % (refusals: %)', to_jsonb(problems), msgs;
end $t$;
