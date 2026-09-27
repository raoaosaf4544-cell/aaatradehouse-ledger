-- Wave 2 item 2b: a retry of a delete that already went through must answer "already deleted" also when the
-- entry was asked for by its invoice number (INV-...). The saved copy now records the number that was asked for.

create or replace function app.delete_entry_impl(p_ref text, p_reason text, p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = app
as $$
declare
  v_plan    jsonb;
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
  values (p_user, btrim(p_reason), v_refs, (v_plan - 'group_ids') || jsonb_build_object('requested_ref', btrim(p_ref)), v_snap)
  returning * into v_del;

  return jsonb_build_object('deleted_id', v_del.id, 'event_refs', to_jsonb(v_refs), 'summary', v_plan - 'group_ids');
end $$;
