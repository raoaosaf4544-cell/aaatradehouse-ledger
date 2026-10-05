-- Correct-the-latest-in-a-chain test. Run as postgres. Always ends with an exception, so nothing is kept.
-- Look for "CHAIN TEST PASS".
--   1. EV-000531 (Rs 100, 5950, a correction of EV-000499) opens with what it is now: Dr 5950 / Cr 1000, 20 Sep,
--      the original's wording, no blocker. It is in v_unclassified.
--   2. Move it to 5500: 5950 -100, cash unchanged, debits = credits; it leaves v_unclassified.
--   3. Correct the NEW latest again (5500 -> 5300): a chain of 3 works; 5500 back where it was.
--   4. EV-000499, EV-000531 and the step-2 entry are now refused with "replaced by".
--   5. Delete: an older version is refused ("replaced by"); the latest of the chain deletes (UNDO).
do $t$
declare
  problems text[] := '{}';
  bal0 jsonb; bal jsonb; s jsonb; r1 text; r2 text; r jsonb; ref text; msg text;
  old_delete text;
  bal_after_old_delete jsonb;
  f_bal constant text := $q$select jsonb_object_agg(a.code, coalesce((select sum(le.debit_paisa - le.credit_paisa) from app.ledger_entries le where le.account_id = a.id), 0))
                             from app.accounts a where a.code in ('1000', '5950', '5500', '5300')$q$;
begin
  execute f_bal into bal0;
  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;

  -- 1
  s := public.correct_entry_preview('EV-000531');
  if s->>'blocker' is not null or s->>'date' <> '2026-09-20' or s->>'original_ref' <> 'EV-000499'
     or s->'lines' <> '[{"account":"5950","name":"Personal/Unclassified (review)","debit":10000,"credit":0},{"account":"1000","name":"Cash on Hand","debit":0,"credit":10000}]'::jsonb then
    problems := problems || format('open EV-000531: %s', s);
  end if;
  if not exists (select 1 from public.v_unclassified where latest_ref = 'EV-000531' and amount_paisa = 10000) then
    problems := problems || 'EV-000531 not in v_unclassified'::text;
  end if;

  -- 2
  r := public.correct_entry('EV-000531', null, '[{"account":"5500","debit":10000},{"account":"1000","credit":10000}]', 'baba confirmed / بابا نے تصدیق کی', 'chain-test-1');
  r1 := r->'event_refs'->>0;
  reset role; execute f_bal into bal; set local role authenticated;
  if (bal->>'5950')::bigint <> (bal0->>'5950')::bigint - 10000 or bal->>'1000' <> bal0->>'1000' or (bal->>'5500')::bigint <> (bal0->>'5500')::bigint + 10000 then
    problems := problems || format('after move to 5500: %s (before %s)', bal, bal0);
  end if;
  if exists (select 1 from public.v_unclassified where original_ref = 'EV-000499') then problems := problems || 'EV-000499 still unclassified'::text; end if;

  -- 3
  r := public.correct_entry(r1, null, '[{"account":"5300","debit":10000},{"account":"1000","credit":10000}]', 'baba says it was fuel', 'chain-test-2');
  r2 := r->'event_refs'->>0;
  reset role; execute f_bal into bal; set local role authenticated;
  if bal->>'5500' <> bal0->>'5500' or (bal->>'5300')::bigint <> (bal0->>'5300')::bigint + 10000 or bal->>'1000' <> bal0->>'1000'
     or (bal->>'5950')::bigint <> (bal0->>'5950')::bigint - 10000 then
    problems := problems || format('after 5500 -> 5300: %s', bal);
  end if;
  if (select description from public.v_events_with_party where event_ref = r2) not like 'Correction of EV-000499 (replaces ' || r1 || ')%' then
    problems := problems || format('%s description: %s', r2, (select description from public.v_events_with_party where event_ref = r2));
  end if;

  -- 4
  foreach ref in array array['EV-000499', 'EV-000531', r1] loop
    begin
      perform public.correct_entry(ref, null, '[{"account":"5600","debit":10000},{"account":"1000","credit":10000}]', 'baba confirmed', 'chain-test-x-' || ref);
      problems := problems || format('%s corrected although replaced', ref);
    exception when check_violation then
      if sqlerrm not like '%' || ref || ' was replaced by ' || r2 || '%' then problems := problems || format('%s: %s', ref, sqlerrm); end if;
    end;
  end loop;

  -- 5 older version first (inside its own sub-transaction, always undone), then the latest
  begin
    perform public.delete_entry(r1, 'baba confirmed', 'UNDO');
    reset role; execute f_bal into bal_after_old_delete; set local role authenticated;
    old_delete := 'ALLOWED';
    raise exception 'undo-sub';
  exception when others then
    if sqlerrm <> 'undo-sub' then old_delete := 'REFUSED: ' || sqlerrm; end if;
  end;
  -- since migration delete_latest_in_chain: an older version cannot be deleted while a newer one stays
  if old_delete not like 'REFUSED: Cannot delete: ' || r1 || ' was replaced by ' || r2 || '%' then
    problems := problems || format('delete older %s: %s (balances then %s)', r1, old_delete, bal_after_old_delete);
  end if;
  r := public.delete_entry(r2, 'baba confirmed', 'UNDO');
  reset role; execute f_bal into bal;
  if r->>'deleted_id' is null or (bal->>'5500')::bigint <> (bal0->>'5500')::bigint + 10000 or bal->>'5300' <> bal0->>'5300' then
    problems := problems || format('delete latest %s: %s / %s', r2, r, bal);
  end if;
  if (select sum(debit_paisa) - sum(credit_paisa) from app.ledger_entries) <> 0 then problems := problems || 'debits <> credits'::text; end if;

  if cardinality(problems) = 0 then
    raise exception 'CHAIN TEST PASS. EV-000531 -> % (5500) -> % (5300); older versions refused "replaced by". Delete latest %: ok. Delete older %: % (balances then: %; before %)',
      r1, r2, r2, r1, old_delete, bal_after_old_delete, bal0;
  end if;
  raise exception 'CHAIN TEST FAIL: %', to_jsonb(problems);
end $t$;
