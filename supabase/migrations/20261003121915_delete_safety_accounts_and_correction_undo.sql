-- Delete safety: what a delete changes in EVERY account, and a clear warning when the entry is a correction.
-- On 30 Sep the correction pair EV-000405/406 was deleted; that silently put the cameras (Rs 11,297) back on 1400
-- Vehicle dated 27 Sep, and no cash/stock/customer check showed it. Now:
--   * every delete preview lists each account it touches: balance before -> after (on the account's normal side);
--   * deleting a correction says "This is a correction of EV-xxxx. Deleting it brings back the original mistake",
--     names any other corrections of the same original that would stay, and needs the word UNDO typed;
--   * the database itself refuses to delete a correction without UNDO (the screen cannot skip it).
-- Deleting an original that still has corrections pointing to it stays refused (unchanged).

create function app.delete_warnings(p_plan jsonb)
returns jsonb language sql stable set search_path = '' as $$
  with g as (select (jsonb_array_elements_text(coalesce(p_plan -> 'group_ids', '[]')))::int as id),
  acc as (
    select a.code, a.name, case when a.type in ('asset', 'expense') then 1 else -1 end as s,
           (select coalesce(sum(l.debit_paisa - l.credit_paisa), 0) from app.ledger_entries l where l.account_id = a.id) as bal,
           sum(le.debit_paisa - le.credit_paisa) as grp
      from app.ledger_entries le join g on g.id = le.event_id join app.accounts a on a.id = le.account_id
     group by a.id, a.code, a.name, a.type),
  corr as (
    select e.event_ref, e.source_ref as original_ref, o.description as original_description,
           (select string_agg(x.event_ref, ', ' order by x.event_ref) from app.events x
             where x.source = 'correction' and x.source_ref = e.source_ref and not exists (select 1 from g where g.id = x.id)) as others_staying
      from app.events e join g on g.id = e.id
      left join app.events o on o.event_ref = e.source_ref
     where e.source = 'correction')
  select jsonb_build_object(
    'accounts', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'before_paisa', s * bal,
                                                              'change_paisa', -s * grp, 'after_paisa', s * (bal - grp)) order by code)
                            from acc where grp <> 0), '[]'),
    'corrections', coalesce((select jsonb_agg(jsonb_build_object('ref', event_ref, 'original_ref', original_ref,
                                                                 'original_description', original_description,
                                                                 'others_staying', others_staying) order by event_ref) from corr), '[]'),
    'needs_word', case when exists (select 1 from corr) then 'UNDO' end)
$$;
revoke all on function app.delete_warnings(jsonb) from public, anon, authenticated;

create or replace function public.delete_entry_preview(p_ref text)
returns jsonb language plpgsql stable security definer set search_path = 'app' as $$
declare v_plan jsonb;
begin
  perform app.require_user();
  v_plan := app.delete_plan(p_ref);
  return (v_plan - 'group_ids') || case when (v_plan ->> 'found')::boolean then app.delete_warnings(v_plan) else '{}' end;
end $$;

drop function public.delete_entry(text, text);
drop function app.delete_entry_impl(text, text, uuid);

create function app.delete_entry_impl(p_ref text, p_reason text, p_user uuid, p_confirm text default null)
returns jsonb language plpgsql security definer set search_path = 'app' as $function$
declare
  v_plan    jsonb;
  v_warn    jsonb;
  v_group   int[];
  v_sales   int[];
  v_disp    int[];
  v_created int[];
  v_touched int[];
  v_parties int[];
  v_snap    jsonb;
  v_ev      app.events%rowtype;
  v_del     app.deleted_entries%rowtype;
  v_refs    text[];
begin
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'Cannot delete: a reason is required.' using errcode = 'check_violation';
  end if;

  v_plan := app.delete_plan(p_ref);
  if not (v_plan ->> 'found')::boolean then
    -- a retry after the delete already went through
    select * into v_del from app.deleted_entries
     where (btrim(p_ref) = any(event_refs) or summary ->> 'requested_ref' = btrim(p_ref))
       and restored_at is null order by id desc limit 1;
    if found then
      return jsonb_build_object('already_deleted', true, 'deleted_id', v_del.id, 'event_refs', to_jsonb(v_del.event_refs));
    end if;
    raise exception 'Cannot delete: entry % was not found.', btrim(p_ref) using errcode = 'check_violation';
  end if;
  if jsonb_array_length(v_plan -> 'blockers') > 0 then
    raise exception 'Cannot delete: %', (select string_agg(value, ' ') from jsonb_array_elements_text(v_plan -> 'blockers'))
      using errcode = 'check_violation';
  end if;

  -- a correction is only deleted when UNDO is typed: deleting it brings back the original mistake
  v_warn := app.delete_warnings(v_plan);
  if v_warn ->> 'needs_word' is not null and upper(btrim(coalesce(p_confirm, ''))) <> v_warn ->> 'needs_word' then
    raise exception 'Cannot delete: this is a correction of %. Deleting it brings back the original mistake. Type UNDO to confirm.',
      (select string_agg(distinct c ->> 'original_ref', ', ') from jsonb_array_elements(v_warn -> 'corrections') c)
      using errcode = 'check_violation';
  end if;

  v_group := array(select (jsonb_array_elements_text(v_plan -> 'group_ids'))::int);
  perform 1 from app.events where id = any(v_group) for update;
  select * into v_ev from app.events where event_ref = v_plan ->> 'ref';
  v_refs := array(select event_ref from app.events where id = any(v_group) order by id);

  v_sales := array(select s.id from app.sales s join app.events e on e.id = any(v_group)
                    where e.event_type = 'sale' and s.sale_ref = substring(e.description from '^Invoice (\S+) to '));
  v_disp := array(select d.id from app.dispatches d where d.sale_id = any(v_sales));
  v_created := array(select b.id from app.batches b
                      where exists (select 1 from app.movements m where m.batch_id = b.id and m.event_id = any(v_group) and m.direction = 'in')
                        and not exists (select 1 from app.movements m where m.batch_id = b.id and not (m.event_id = any(v_group))));
  v_touched := array(select distinct m.batch_id from app.movements m where m.event_id = any(v_group) and not (m.batch_id = any(v_created)));
  v_parties := array(select p.id from app.parties p
                      where p.id in (select e.party_id from app.events e where e.id = any(v_group))
                        and p.created_at = v_ev.created_at
                        and not exists (select 1 from app.events e where e.party_id = p.id and not (e.id = any(v_group)))
                        and not exists (select 1 from app.customer_advances c where c.party_id = p.id and not (c.event_id = any(v_group))));

  -- the full copy, taken before anything changes
  v_snap := jsonb_build_object(
    'events',                (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.events x where x.id = any(v_group)),
    'ledger_entries',        (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.ledger_entries x where x.event_id = any(v_group)),
    'movements',             (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.movements x where x.event_id = any(v_group)),
    'batch_cost_components', (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.batch_cost_components x where x.event_id = any(v_group)),
    'customer_advances',     (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.customer_advances x where x.event_id = any(v_group)),
    'sales',                 (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.sales x where x.id = any(v_sales)),
    'sale_lines',            (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.sale_lines x where x.sale_id = any(v_sales)),
    'dispatches',            (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.dispatches x where x.id = any(v_disp)),
    'dispatch_allocations',  (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.dispatch_allocations x where x.dispatch_id = any(v_disp)),
    'batches_created',       (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.batches x where x.id = any(v_created)),
    'batches_touched',       (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.batches x where x.id = any(v_touched)),
    'parties',               (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from app.parties x where x.id = any(v_parties))
  );

  delete from app.dispatch_allocations where dispatch_id = any(v_disp);
  delete from app.dispatches where id = any(v_disp);
  delete from app.customer_advances where event_id = any(v_group);
  delete from app.batch_cost_components where event_id = any(v_group);
  delete from app.movements where event_id = any(v_group);
  delete from app.ledger_entries where event_id = any(v_group);
  delete from app.sale_lines where sale_id = any(v_sales);
  delete from app.sales where id = any(v_sales);
  delete from app.events where id = any(v_group);
  delete from app.batches where id = any(v_created);
  delete from app.parties where id = any(v_parties);

  -- batches that got stock back are open again
  update app.batches b set status = 'open', closed_on = null
   where b.id = any(v_touched) and b.status = 'closed'
     and (select coalesce(sum(case when m.direction = 'in' then m.qty_grams else -m.qty_grams end), 0) from app.movements m where m.batch_id = b.id) > 0;

  perform app.check_books_after_change('delete');

  insert into app.deleted_entries (deleted_by, reason, event_refs, summary, snapshot)
  values (p_user, btrim(p_reason), v_refs, (v_plan - 'group_ids') || v_warn || jsonb_build_object('requested_ref', btrim(p_ref)), v_snap)
  returning * into v_del;

  return jsonb_build_object('deleted_id', v_del.id, 'event_refs', to_jsonb(v_refs), 'summary', (v_plan - 'group_ids') || v_warn);
end $function$;
revoke all on function app.delete_entry_impl(text, text, uuid, text) from public, anon, authenticated;

create function public.delete_entry(p_ref text, p_reason text, p_confirm text default null)
returns jsonb language plpgsql security definer set search_path = 'app' as $$
begin
  return app.delete_entry_impl(p_ref, p_reason, app.require_user(), p_confirm);
end $$;
revoke all on function public.delete_entry(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.delete_entry(text, text, text) to authenticated;
