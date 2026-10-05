-- Delete only the LATEST version of a corrected entry (5 Oct 2026, found by the correct-chain test).
-- Deleting an older correction while a newer one of the same original stays scrambles accounts: in the test,
-- deleting the middle of 5950 -> 5500 -> 5300 left 5500 Rs 100 below where it started. The 30 Sep camera incident
-- (EV-000405 deleted, EV-000406 kept) was the same mistake. Now such a delete is refused with a plain blocker
-- ("EV-x was replaced by EV-y. Delete EV-y first, or correct EV-y instead."): undo a chain newest first.
-- app.delete_plan_checked = app.delete_plan + this blocker; the preview and the delete swap their one call to
-- app.delete_plan for it (exact text replace; stops if the call is not found). Nothing else changes.

create function app.delete_plan_checked(p_ref text) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_plan  jsonb := app.delete_plan(p_ref);
  v_group int[];
  v_msg   text;
begin
  if not coalesce((v_plan ->> 'found')::boolean, false) then
    return v_plan;
  end if;
  v_group := array(select (jsonb_array_elements_text(coalesce(v_plan -> 'group_ids', '[]')))::int);
  select format('%s was replaced by %s. Delete %s first, or correct %s instead.', e.event_ref, n.event_ref, n.event_ref, n.event_ref)
    into v_msg
    from app.events e
    cross join lateral (select x.event_ref from app.events x
                         where x.source = 'correction' and x.source_ref = e.source_ref and x.id > e.id and not (x.id = any(v_group))
                         order by x.id desc limit 1) n
   where e.id = any(v_group) and e.source = 'correction' and e.source_ref is not null
   order by e.id limit 1;
  if v_msg is not null then
    v_plan := jsonb_set(v_plan, '{blockers}', coalesce(v_plan -> 'blockers', '[]') || to_jsonb(v_msg));
  end if;
  return v_plan;
end $$;
revoke all on function app.delete_plan_checked(text) from public, anon, authenticated;

do $m$
declare
  v_fn  regprocedure;
  v_def text;
begin
  foreach v_fn in array array['public.delete_entry_preview(text)'::regprocedure, 'app.delete_entry_impl(text,text,uuid,text)'::regprocedure] loop
    v_def := pg_get_functiondef(v_fn);
    if (length(v_def) - length(replace(v_def, 'v_plan := app.delete_plan(p_ref);', ''))) <> length('v_plan := app.delete_plan(p_ref);') then
      raise exception 'delete latest in chain: % does not call app.delete_plan exactly once - function changed, migration stopped', v_fn;
    end if;
    execute replace(v_def, 'v_plan := app.delete_plan(p_ref);', 'v_plan := app.delete_plan_checked(p_ref);');
  end loop;
end $m$;
