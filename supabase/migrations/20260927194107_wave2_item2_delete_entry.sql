-- Wave 2 item 2 (owner decision 2026-09-28, replaces "Correct this entry"): delete a whole entry, safely.
--  * delete_plan(ref): what would be removed, the effects (cash, stock kg, customer / supplier / advance balances)
--    and plain-language reasons it cannot be deleted yet. The preview and the delete use the same plan.
--  * delete_entry(ref, reason): one transaction - saves a full copy of every row removed or changed in
--    deleted_entries, removes the whole entry (a sale goes with its own dispatch), re-opens batches that got stock
--    back, then re-checks the books; any failed check cancels the whole delete.
--  * restore_entry(id): puts every saved row back with its original ids and refs, then runs the same checks.
-- Only allow-listed users (app.require_user); the assistant role (JARVIS) is refused. anon has no access.

create table if not exists app.deleted_entries (
  id          bigint generated always as identity primary key,
  deleted_at  timestamptz not null default now(),
  deleted_by  uuid not null references app.users(id),
  reason      text not null check (length(btrim(reason)) > 0),
  event_refs  text[] not null,
  summary     jsonb not null,  -- what changed, exactly as shown in the preview
  snapshot    jsonb not null,  -- every row removed or changed, as it was
  restored_at timestamptz,
  restored_by uuid references app.users(id)
);
alter table app.deleted_entries enable row level security;
drop policy if exists auth_read on app.deleted_entries;
create policy auth_read on app.deleted_entries for select to authenticated using (app.is_allowed_user());
revoke all on app.deleted_entries from public, anon, authenticated;
grant select on app.deleted_entries to authenticated;

-- ---------------------------------------------------------------------------------------------------------------
create or replace function app.delete_plan(p_ref text)
returns jsonb
language plpgsql
stable
security definer
set search_path = app
as $$
declare
  v_ref      text := btrim(coalesce(p_ref, ''));
  v_ev       app.events%rowtype;
  v_group    int[];
  v_sale_ref text;
  v_blockers text[] := '{}';
  v_list     text;
  v_day      date;
  r          record;
begin
  -- an invoice number means its sale entry
  if v_ref like 'INV-%' then
    select e.* into v_ev from app.events e
     where e.event_type = 'sale' and substring(e.description from '^Invoice (\S+) to ') = v_ref;
  else
    select * into v_ev from app.events where event_ref = v_ref;
  end if;
  if not found then
    return jsonb_build_object('found', false, 'ref', v_ref);
  end if;

  v_group := array[v_ev.id];
  if v_ev.event_type = 'sale' then
    v_sale_ref := substring(v_ev.description from '^Invoice (\S+) to ');
    -- a sale goes with its own dispatches (one-step sales record both)
    v_group := v_group || array(
      select e.id from app.events e
       where e.event_type = 'dispatch' and substring(e.description from 'against invoice (\S+) to ') = v_sale_ref
       order by e.id);
  end if;

  -- ---- reasons it cannot be deleted yet (plain words) ----
  if v_ev.event_type = 'opening_inventory' then
    v_blockers := v_blockers || 'This is the imported opening stock record. It cannot be deleted.'::text;
  end if;

  if v_ev.event_type = 'dispatch' and v_ev.description ~ '^Dispatch \S+ against invoice \S+ to ' then
    select e.event_ref into v_list from app.events e
     where e.event_type = 'sale'
       and substring(e.description from '^Invoice (\S+) to ') = substring(v_ev.description from 'against invoice (\S+) to ');
    v_blockers := v_blockers || format('This is the salt leaving for a sale. Delete the sale %s instead - its dispatch is removed with it.',
                                       coalesce(v_list, substring(v_ev.description from 'against invoice (\S+) to ')));
  end if;

  select string_agg(e.event_ref, ', ' order by e.event_ref) into v_list
    from app.events e join app.events g on g.id = any(v_group) and e.source_ref = g.event_ref
   where not (e.id = any(v_group));
  if v_list is not null then
    v_blockers := v_blockers || format('Correction %s points to this entry. Delete the correction first.', v_list);
  end if;

  for r in
    select b.batch_code, string_agg(distinct e.event_ref, ', ') as refs
      from app.movements mi
      join app.batches b on b.id = mi.batch_id
      join app.movements mo on mo.batch_id = b.id and not (mo.event_id = any(v_group))
      join app.events e on e.id = mo.event_id
     where mi.event_id = any(v_group) and mi.direction = 'in'
     group by b.batch_code
  loop
    v_blockers := v_blockers || format('Salt from %s was already used by %s. Delete those first.', r.batch_code, r.refs);
  end loop;

  for r in
    select e.party_id, p.name,
           (select coalesce(sum(l.debit_paisa - l.credit_paisa), 0)
              from app.ledger_entries l join app.accounts a2 on a2.id = l.account_id and a2.code = '1100'
              join app.events e2 on e2.id = l.event_id where e2.party_id = e.party_id) as owes_before,
           sum(case when a.code = '1100' then le.debit_paisa - le.credit_paisa else 0 end) as ar_change
      from app.events e
      join app.parties p on p.id = e.party_id
      join app.ledger_entries le on le.event_id = e.id
      join app.accounts a on a.id = le.account_id
     where e.id = any(v_group)
     group by e.party_id, p.name
  loop
    if r.owes_before - r.ar_change < 0 then
      select string_agg(e.event_ref, ', ' order by e.occurred_on, e.event_ref) into v_list
        from app.events e where e.party_id = r.party_id and e.event_type = 'customer_payment';
      v_blockers := v_blockers || format('%s has already paid more than they would owe without this sale. Delete the payment %s first.',
                                         r.name, coalesce(v_list, '(none found)'));
    end if;
  end loop;

  for r in
    select ca.party_id, p.name,
           (select coalesce(sum(case when c2.direction = 'received' then c2.amount_paisa else -c2.amount_paisa end), 0)
              from app.customer_advances c2 where c2.party_id = ca.party_id) as bal_before,
           sum(case when ca.direction = 'received' then ca.amount_paisa else -ca.amount_paisa end) as change
      from app.customer_advances ca join app.parties p on p.id = ca.party_id
     where ca.event_id = any(v_group)
     group by ca.party_id, p.name
  loop
    if r.bal_before - r.change < 0 then
      v_blockers := v_blockers || format('The advance from %s was already used by a later sale. Delete that sale first.', r.name);
    end if;
  end loop;

  select min(d) into v_day
    from (select d, sum(net) over (order by d) as bal
            from (select e.occurred_on as d, sum(le.debit_paisa - le.credit_paisa) as net
                    from app.ledger_entries le
                    join app.accounts a on a.id = le.account_id and a.code = '1000'
                    join app.events e on e.id = le.event_id
                   where not (e.id = any(v_group))
                   group by e.occurred_on) x) y
   where bal < 0;
  if v_day is not null then
    v_blockers := v_blockers || format('Without this entry, cash would go below zero on %s. Delete or correct the later cash-out entries first.',
                                       to_char(v_day, 'DD Mon YYYY'));
  end if;

  -- ---- effects (what will change) ----
  return jsonb_build_object(
    'found', true,
    'ref', v_ev.event_ref,
    'group_ids', to_jsonb(v_group),
    'blockers', to_jsonb(v_blockers),
    'entries', (select jsonb_agg(jsonb_build_object(
                  'ref', e.event_ref, 'type', e.event_type, 'date', e.occurred_on, 'description', e.description,
                  'amount_paisa', (select coalesce(sum(l.debit_paisa), 0) from app.ledger_entries l where l.event_id = e.id))
                  order by e.id)
                from app.events e where e.id = any(v_group)),
    'cash_before_paisa', (select coalesce(sum(le.debit_paisa - le.credit_paisa), 0) from app.ledger_entries le
                            join app.accounts a on a.id = le.account_id and a.code = '1000'),
    'cash_change_paisa', -(select coalesce(sum(le.debit_paisa - le.credit_paisa), 0) from app.ledger_entries le
                             join app.accounts a on a.id = le.account_id and a.code = '1000' where le.event_id = any(v_group)),
    'stock', (select jsonb_agg(jsonb_build_object('batch', x.batch_code, 'kg_before', x.kg_before, 'kg_change', x.kg_change,
                                                   'value_change_paisa', x.value_change) order by x.batch_code)
              from (select b.batch_code,
                           (select coalesce(sum(case when m2.direction = 'in' then m2.qty_grams else -m2.qty_grams end), 0)
                              from app.movements m2 where m2.batch_id = b.id) / 1000.0 as kg_before,
                           -sum(case when m.direction = 'in' then m.qty_grams else -m.qty_grams end) / 1000.0 as kg_change,
                           -sum(m.value_paisa) as value_change
                      from app.movements m join app.batches b on b.id = m.batch_id
                     where m.event_id = any(v_group)
                     group by b.id, b.batch_code) x),
    'customers', (select jsonb_agg(jsonb_build_object('name', x.name, 'owes_before_paisa', x.owes_before, 'owes_after_paisa', x.owes_before - x.ar_change))
                  from (select p.name,
                               (select coalesce(sum(l.debit_paisa - l.credit_paisa), 0)
                                  from app.ledger_entries l join app.accounts a2 on a2.id = l.account_id and a2.code = '1100'
                                  join app.events e2 on e2.id = l.event_id where e2.party_id = e.party_id) as owes_before,
                               sum(case when a.code = '1100' then le.debit_paisa - le.credit_paisa else 0 end) as ar_change
                          from app.events e join app.parties p on p.id = e.party_id
                          join app.ledger_entries le on le.event_id = e.id join app.accounts a on a.id = le.account_id
                         where e.id = any(v_group) group by e.party_id, p.name) x
                 where x.ar_change <> 0),
    'suppliers_owed_before_paisa', (select coalesce(sum(le.credit_paisa - le.debit_paisa), 0) from app.ledger_entries le
                                      join app.accounts a on a.id = le.account_id and a.code = '2000'),
    'suppliers_owed_change_paisa', -(select coalesce(sum(le.credit_paisa - le.debit_paisa), 0) from app.ledger_entries le
                                       join app.accounts a on a.id = le.account_id and a.code = '2000' where le.event_id = any(v_group)),
    'advances_change_paisa', -(select coalesce(sum(le.credit_paisa - le.debit_paisa), 0) from app.ledger_entries le
                                 join app.accounts a on a.id = le.account_id and a.code = '2200' where le.event_id = any(v_group)),
    'batches_removed', (select jsonb_agg(b.batch_code order by b.batch_code) from app.batches b
                         where exists (select 1 from app.movements m where m.batch_id = b.id and m.event_id = any(v_group) and m.direction = 'in')
                           and not exists (select 1 from app.movements m where m.batch_id = b.id and not (m.event_id = any(v_group)))),
    'customers_removed', (select jsonb_agg(p.name order by p.name) from app.parties p
                           where p.id in (select e.party_id from app.events e where e.id = any(v_group))
                             and p.created_at = v_ev.created_at
                             and not exists (select 1 from app.events e where e.party_id = p.id and not (e.id = any(v_group)))
                             and not exists (select 1 from app.customer_advances c where c.party_id = p.id and not (c.event_id = any(v_group))))
  );
end $$;

-- ---------------------------------------------------------------------------------------------------------------
create or replace function app.check_books_after_change(p_what text)
returns void
language plpgsql
security definer
set search_path = app
as $$
declare h record; v_bad text;
begin
  select * into h from app.v_ledger_health;
  if h.total_debit_paisa <> h.total_credit_paisa then
    raise exception 'Cannot %: debits would not equal credits. Nothing was changed.', p_what using errcode = 'check_violation';
  end if;
  if h.negative_cash_days > 0 then
    raise exception 'Cannot %: cash would go below zero on % day(s). Nothing was changed.', p_what, h.negative_cash_days using errcode = 'check_violation';
  end if;
  if h.stock_mismatched_accounts > 0 or h.stock_ledger_paisa <> h.stock_movements_paisa then
    raise exception 'Cannot %: the stock value would not match the batch records. Nothing was changed.', p_what using errcode = 'check_violation';
  end if;
  select string_agg(b.batch_code, ', ') into v_bad from app.batches b
   where (select coalesce(sum(case when m.direction = 'in' then m.qty_grams else -m.qty_grams end), 0) from app.movements m where m.batch_id = b.id) < 0;
  if v_bad is not null then
    raise exception 'Cannot %: stock of % would go below zero. Nothing was changed.', p_what, v_bad using errcode = 'check_violation';
  end if;
  select string_agg(p.name, ', ') into v_bad from app.parties p
   where (select coalesce(sum(l.debit_paisa - l.credit_paisa), 0) from app.ledger_entries l
            join app.accounts a on a.id = l.account_id and a.code = '1100'
            join app.events e on e.id = l.event_id where e.party_id = p.id) < 0;
  if v_bad is not null then
    raise exception 'Cannot %: % would owe a negative amount. Nothing was changed.', p_what, v_bad using errcode = 'check_violation';
  end if;
  select string_agg(p.name, ', ') into v_bad from app.parties p
   where (select coalesce(sum(case when c.direction = 'received' then c.amount_paisa else -c.amount_paisa end), 0)
            from app.customer_advances c where c.party_id = p.id) < 0;
  if v_bad is not null then
    raise exception 'Cannot %: the advance of % would go below zero. Nothing was changed.', p_what, v_bad using errcode = 'check_violation';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------------
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
     where btrim(p_ref) = any(event_refs) and restored_at is null order by id desc limit 1;
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
  values (p_user, btrim(p_reason), v_refs, v_plan - 'group_ids', v_snap)
  returning * into v_del;

  return jsonb_build_object('deleted_id', v_del.id, 'event_refs', to_jsonb(v_refs), 'summary', v_plan - 'group_ids');
end $$;

-- ---------------------------------------------------------------------------------------------------------------
create or replace function app.restore_entry_impl(p_deleted_id bigint, p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = app
as $$
declare
  v_del app.deleted_entries%rowtype;
  s     jsonb;
  x     jsonb;
begin
  select * into v_del from app.deleted_entries where id = p_deleted_id for update;
  if not found then
    raise exception 'Cannot restore: deleted record % was not found.', p_deleted_id using errcode = 'check_violation';
  end if;
  if v_del.restored_at is not null then
    return jsonb_build_object('already_restored', true, 'event_refs', to_jsonb(v_del.event_refs));
  end if;
  s := v_del.snapshot;

  if exists (select 1 from app.events e, jsonb_array_elements(s -> 'events') j
              where e.id = (j ->> 'id')::int or e.event_ref = j ->> 'event_ref'
                 or (j ->> 'idempotency_key' is not null and e.idempotency_key = j ->> 'idempotency_key')) then
    raise exception 'Cannot restore: an entry with the same number already exists.' using errcode = 'check_violation';
  end if;

  insert into app.parties overriding system value
    select * from jsonb_populate_recordset(null::app.parties, s -> 'parties');
  insert into app.batches overriding system value
    select * from jsonb_populate_recordset(null::app.batches, s -> 'batches_created');
  for x in select value from jsonb_array_elements(s -> 'events') loop
    insert into app.events overriding system value select * from jsonb_populate_record(null::app.events, x);
  end loop;
  insert into app.ledger_entries overriding system value
    select * from jsonb_populate_recordset(null::app.ledger_entries, s -> 'ledger_entries');
  insert into app.batch_cost_components overriding system value
    select * from jsonb_populate_recordset(null::app.batch_cost_components, s -> 'batch_cost_components');
  -- stock in before stock out (the stock trigger checks each row)
  for x in select value from jsonb_array_elements(s -> 'movements')
            order by (value ->> 'direction' = 'in') desc, (value ->> 'id')::bigint loop
    insert into app.movements overriding system value select * from jsonb_populate_record(null::app.movements, x);
  end loop;
  insert into app.sales overriding system value
    select * from jsonb_populate_recordset(null::app.sales, s -> 'sales');
  insert into app.sale_lines overriding system value
    select * from jsonb_populate_recordset(null::app.sale_lines, s -> 'sale_lines');
  insert into app.dispatches overriding system value
    select * from jsonb_populate_recordset(null::app.dispatches, s -> 'dispatches');
  insert into app.dispatch_allocations overriding system value
    select * from jsonb_populate_recordset(null::app.dispatch_allocations, s -> 'dispatch_allocations');
  insert into app.customer_advances overriding system value
    select * from jsonb_populate_recordset(null::app.customer_advances, s -> 'customer_advances');
  -- batch status exactly as it was (e.g. closed by the restored dispatch)
  update app.batches b set status = t.status, closed_on = t.closed_on
    from jsonb_populate_recordset(null::app.batches, s -> 'batches_touched') t where b.id = t.id;

  perform app.check_books_after_change('restore');

  update app.deleted_entries set restored_at = now(), restored_by = p_user where id = p_deleted_id;
  return jsonb_build_object('restored', true, 'event_refs', to_jsonb(v_del.event_refs));
end $$;

-- ---------------------------------------------------------------------------------------------------------------
create or replace function public.delete_entry_preview(p_ref text)
returns jsonb language plpgsql stable security definer set search_path = app as $$
begin
  perform app.require_user();
  return app.delete_plan(p_ref) - 'group_ids';
end $$;

create or replace function public.delete_entry(p_ref text, p_reason text)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.delete_entry_impl(p_ref, p_reason, app.require_user());
end $$;

create or replace function public.restore_entry(p_deleted_id bigint)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.restore_entry_impl(p_deleted_id, app.require_user());
end $$;

create or replace view app.v_deleted_entries with (security_invoker = true) as
select d.id, d.deleted_at, u.name as deleted_by_name, d.reason, d.event_refs, d.summary, d.restored_at, r.name as restored_by_name
from app.deleted_entries d
left join app.users u on u.id = d.deleted_by
left join app.users r on r.id = d.restored_by;
create or replace view public.v_deleted_entries with (security_invoker = true) as select * from app.v_deleted_entries;

-- functions: only through the guarded public wrappers, only for signed-in users
revoke all on function app.delete_plan(text), app.check_books_after_change(text), app.delete_entry_impl(text, text, uuid),
  app.restore_entry_impl(bigint, uuid) from public, anon, authenticated;
revoke all on function public.delete_entry_preview(text), public.delete_entry(text, text), public.restore_entry(bigint) from public, anon;
grant execute on function public.delete_entry_preview(text), public.delete_entry(text, text), public.restore_entry(bigint) to authenticated;
revoke all on app.v_deleted_entries, public.v_deleted_entries from public, anon, authenticated;
grant select on app.v_deleted_entries to authenticated;
grant select on public.v_deleted_entries to authenticated, service_role;
