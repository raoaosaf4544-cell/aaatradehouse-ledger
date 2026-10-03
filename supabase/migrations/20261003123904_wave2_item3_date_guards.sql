-- Wave 2 item 3: date guards on NEW entries (owner decisions, 3 Oct 2026).
--   * no entry dated in the future (Asia/Karachi date);
--   * no entry dated before the books start, 23 Aug 2026;
--   * no salt leaving a batch (out / wastage) dated before that batch arrived (batches.opened_on).
-- Existing entries are untouched: the guards run only when a row is inserted (or an entry date is changed).
-- Restoring from "Deleted entries" is exempt: it puts back exactly what was accepted before, so the restore function
-- marks its own transaction (app.restoring) and the guards let it through. Known old exception, left as it is by
-- owner decision: 14 dispatch lines (6-13 Sep, 732.5 kg) took salt from BATCH-075 before its recorded 14 Sep arrival.

create function app.guard_entry_date() returns trigger language plpgsql set search_path = '' as $$
declare
  v_today date := (now() at time zone 'Asia/Karachi')::date;
begin
  if current_setting('app.restoring', true) = 'on' then
    return new;
  end if;
  if new.occurred_on > v_today then
    raise exception 'INVARIANT VIOLATION: date % is in the future (today is %)', new.occurred_on, v_today using errcode = 'check_violation';
  end if;
  if new.occurred_on < date '2026-08-23' then
    raise exception 'INVARIANT VIOLATION: date % is before the books start (23 Aug 2026)', new.occurred_on using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger trg_events_date_guard before insert or update of occurred_on on app.events
  for each row execute function app.guard_entry_date();

create function app.guard_salt_out_date() returns trigger language plpgsql set search_path = '' as $$
declare
  v_on    date;
  v_batch app.batches%rowtype;
begin
  if new.direction not in ('out', 'wastage') or current_setting('app.restoring', true) = 'on' then
    return new;
  end if;
  select e.occurred_on into v_on from app.events e where e.id = new.event_id;
  select * into v_batch from app.batches b where b.id = new.batch_id;
  if v_on < v_batch.opened_on then
    raise exception 'INVARIANT VIOLATION: batch % did not exist yet on % (it arrived %)', v_batch.batch_code, v_on, v_batch.opened_on
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger trg_movements_batch_date_guard before insert on app.movements
  for each row execute function app.guard_salt_out_date();

revoke all on function app.guard_entry_date(), app.guard_salt_out_date() from public, anon, authenticated;

-- restore: same as before, plus the marker that exempts it from the date guards
create or replace function app.restore_entry_impl(p_deleted_id bigint, p_user uuid)
returns jsonb language plpgsql security definer set search_path = 'app' as $function$
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

  -- putting back what was accepted before: the date guards do not apply (this transaction only)
  perform set_config('app.restoring', 'on', true);

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

  perform set_config('app.restoring', 'off', true);
  perform app.check_books_after_change('restore');

  update app.deleted_entries set restored_at = now(), restored_by = p_user where id = p_deleted_id;
  return jsonb_build_object('restored', true, 'event_refs', to_jsonb(v_del.event_refs));
end $function$;
