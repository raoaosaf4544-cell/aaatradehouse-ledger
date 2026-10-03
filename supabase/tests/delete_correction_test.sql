-- Delete-safety test. Run as postgres. Always ends with an exception, so nothing is kept. Look for "DELETE TEST PASS".
--   1. The camera correction pair EV-000405/406 (restored first if still deleted): the preview of deleting EV-000405
--      says it corrects EV-000404, that EV-000406 would stay, needs UNDO, and lists each account's change.
--   2. Deleting it without UNDO is refused by the database; with UNDO it goes through.
--   3. An ordinary entry: accounts listed, no correction warning, no UNDO.
--   4. The original EV-000404 still cannot be deleted while corrections point to it.
do $t$
declare
  problems text[] := '{}'; p jsonb; r jsonb; plain jsonb; msg text; v_plain text;
begin
  perform set_config('request.jwt.claims', '{"sub":"d0bd34c0-2de1-4281-8d0f-7cb165f4e889","role":"authenticated"}', true);
  set local role authenticated;
  if not exists (select 1 from public.v_events_with_party where event_ref = 'EV-000405') then
    perform public.restore_entry((select id from public.v_deleted_entries where 'EV-000405' = any(event_refs) and restored_at is null order by id desc limit 1));
  end if;
  if not exists (select 1 from public.v_events_with_party where event_ref = 'EV-000406') then
    perform public.restore_entry((select id from public.v_deleted_entries where 'EV-000406' = any(event_refs) and restored_at is null order by id desc limit 1));
  end if;

  p := public.delete_entry_preview('EV-000405');
  if p->>'needs_word' is distinct from 'UNDO' or p->'corrections'->0->>'original_ref' is distinct from 'EV-000404'
     or p->'corrections'->0->>'others_staying' is distinct from 'EV-000406' or jsonb_array_length(p->'accounts') < 2 then
    problems := problems || format('preview of EV-000405: %s', p - 'entries');
  end if;
  begin
    perform public.delete_entry('EV-000405', 'test');
    problems := problems || 'correction deleted without UNDO'::text;
  exception when check_violation then msg := sqlerrm;
  end;
  r := public.delete_entry('EV-000405', 'test', 'undo');
  if r->>'deleted_id' is null then problems := problems || format('delete with UNDO failed: %s', r); end if;

  select e.event_ref into v_plain from public.v_events_with_party e
   where e.source = 'app' and e.event_type = 'expense'
     and not exists (select 1 from public.v_events_with_party c where c.source_ref = e.event_ref) order by e.id desc limit 1;
  plain := public.delete_entry_preview(v_plain);
  if plain->>'needs_word' is not null or jsonb_array_length(plain->'corrections') <> 0 or jsonb_array_length(plain->'accounts') < 2 then
    problems := problems || format('plain preview %s: %s', v_plain, plain - 'entries');
  end if;

  r := public.delete_entry_preview('EV-000404');
  if not (r->>'blockers' like '%points to this entry%') then problems := problems || format('original not blocked: %s', r->'blockers'); end if;
  reset role;

  if cardinality(problems) = 0 then
    raise exception 'DELETE TEST PASS. EV-000405 preview: corrections %, accounts %. Without UNDO: "%". Plain entry % accounts: %',
      p->'corrections', p->'accounts', msg, v_plain, plain->'accounts';
  end if;
  raise exception 'DELETE TEST FAIL: %', to_jsonb(problems);
end $t$;
