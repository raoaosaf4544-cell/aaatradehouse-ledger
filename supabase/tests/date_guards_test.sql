-- Date-guard test (Wave 2 item 3). Run as postgres. Always ends with an exception, so nothing is kept
-- (it uses up entry numbers). Look for "DATE TEST PASS".
--   1. A new entry dated tomorrow is refused; dated 22 Aug 2026 is refused; dated today is accepted.
--   2. A sale of Fine Powder dated 10 Sep (before BATCH-075 arrived on 14 Sep) is refused.
--   3. Restore is exempt: a deleted sale whose salt left BATCH-075 before 14 Sep is restored without complaint.
--   4. The 14 old lines (owner decision: left as they are) are untouched.
do $t$
declare
  problems text[] := '{}'; msgs jsonb := '[]'; q text; v_today date := (now() at time zone 'Asia/Karachi')::date;
  v_inv text; v_del jsonb; v_res jsonb; n int;
begin
  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;
  foreach q in array array[
    format($q$select public.post_event('expense', %L, 'date test', '[{"account": "5900", "debit": 100}, {"account": "1000", "credit": 100}]', null, null, null, 'test-date-1')$q$, v_today + 1),
    $q$select public.post_event('expense', '2026-08-22', 'date test', '[{"account": "5900", "debit": 100}, {"account": "1000", "credit": 100}]', null, null, null, 'test-date-2')$q$,
    $q$select public.record_udhaar_sale('Test Customer D', '[{"product_code": "SALT_BULK", "qty_kg": 40, "line_total_paisa": 50000}]', 0, null, '2026-09-10', 'date test', 'test-date-3', null)$q$] loop
    begin
      execute q;
      problems := problems || ('not refused: ' || q);
    exception when check_violation then msgs := msgs || to_jsonb(sqlerrm);
    end;
  end loop;
  perform public.post_event('expense', v_today, 'date test', '[{"account": "5900", "debit": 100}, {"account": "1000", "credit": 100}]', null, null, null, 'test-date-4');

  -- restore is exempt: delete a sale whose salt left BATCH-075 before 14 Sep, then put it back
  select substring(e.description from 'against invoice (\S+) to ') into v_inv
    from public.v_events_with_party e join app.movements m on m.event_id = e.id join app.batches b on b.id = m.batch_id
   where e.event_type = 'dispatch' and m.direction = 'out' and e.occurred_on < b.opened_on
     and jsonb_array_length(public.delete_entry_preview(substring(e.description from 'against invoice (\S+) to ')) -> 'blockers') = 0
   order by e.id limit 1;
  if v_inv is null then
    problems := problems || 'no early BATCH-075 sale could be deleted for the restore test'::text;
  else
    v_del := public.delete_entry(v_inv, 'date guard test');
    v_res := public.restore_entry((v_del->>'deleted_id')::bigint);
    if not coalesce((v_res->>'restored')::boolean, false) then problems := problems || format('restore failed: %s', v_res); end if;
  end if;
  reset role;

  select count(*) into n from app.movements m join app.events e on e.id = m.event_id join app.batches b on b.id = m.batch_id
   where m.direction in ('out', 'wastage') and e.occurred_on < b.opened_on;
  if n <> 14 then problems := problems || format('old lines before arrival: %s, expected 14', n); end if;

  if cardinality(problems) = 0 then
    raise exception 'DATE TEST PASS. Refusals: %. Restore of % (salt out before arrival) went through.', msgs, v_inv;
  end if;
  raise exception 'DATE TEST FAIL: % (refusals seen: %)', to_jsonb(problems), msgs;
end $t$;
