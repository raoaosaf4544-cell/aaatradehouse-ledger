-- Workers / مزدور (part-time labour), owner-approved 10 Oct 2026.
--   * A worker is a party (kind 'worker') + app.workers (pay type, rate, plant or other).
--   * Work done: Dr 5420 Plant labour (plant worker) or 5000 Labour / Cr 1320 Worker advances (what he already had)
--     + Cr 2100 Wages owed (the rest). The advance is used first.
--   * Pay: Dr 2100 (up to what he is owed) + Dr 1320 (anything more = advance, peshgi) / Cr 1000 cash or 1050 bank.
--   * Every 2100 / 1320 line carries its worker (ledger_entries.party_id), like 2000 lines carry their supplier.
--   * Entries touching 2100 / 1320 are not corrected in place: delete (reason required) and enter again. A delete
--     that would leave a worker owed less than 0 or with an advance below 0 is refused (delete the later one first).
-- 1310 "WIP - Processing Costs Pool" exists, so advances use the free code 1320. 1300 and 1310 are untouched.

alter table app.parties drop constraint parties_kind_check;
alter table app.parties add constraint parties_kind_check check (kind in ('customer', 'supplier', 'worker'));

alter table app.events drop constraint events_event_type_check;
alter table app.events add constraint events_event_type_check check (event_type in ('capital_injection', 'owner_drawing',
  'expense', 'asset_purchase', 'asset_disposal', 'purchase', 'purchase_payment', 'supplier_return', 'process_run',
  'packaging_run', 'transfer', 'stock_adjustment', 'sale', 'dispatch', 'customer_return', 'customer_payment',
  'customer_advance', 'opening_inventory', 'inventory_reval', 'other', 'work_done', 'worker_payment'));

insert into app.accounts (code, name, type, kind) values ('1320', 'Worker advances / پیشگی', 'asset', 'control');
do $$
begin
  if exists (select 1 from app.ledger_entries le join app.accounts a on a.id = le.account_id where a.code = '2100') then
    raise exception 'STOP: 2100 already has lines - not renamed';
  end if;
  update app.accounts set name = 'Wages owed / واجب الادا اجرت' where code = '2100';
end $$;

create table app.workers (
  party_id   integer primary key references app.parties(id),
  pay_type   text not null check (pay_type in ('day', 'bag', 'ton', 'fixed')),
  rate_paisa bigint not null check (rate_paisa >= 0),
  area       text not null check (area in ('plant', 'other'))
);
alter table app.workers enable row level security;
create policy auth_read on app.workers for select to authenticated using (app.is_allowed_user());

-- party on the line: 2000 -> its supplier; 2100 / 1320 -> its worker; no other line carries a party
create or replace function app.assert_supplier_line_linked() returns trigger language plpgsql set search_path = '' as $$
declare v_code text; v_kind text;
begin
  if current_setting('app.restoring', true) = 'on' then
    return new; -- a restore puts back exactly what was deleted
  end if;
  select a.code into v_code from app.accounts a where a.id = new.account_id;
  select p.kind into v_kind from app.parties p where p.id = new.party_id;
  if v_code = '2000' and new.party_id is null then
    raise exception 'INVARIANT VIOLATION: every Suppliers (2000) line needs the supplier it is owed to' using errcode = 'check_violation';
  end if;
  if v_code in ('2100', '1320') and new.party_id is null then
    raise exception 'INVARIANT VIOLATION: every wages owed / worker advance line needs its worker' using errcode = 'check_violation';
  end if;
  if new.party_id is not null and not ((v_code = '2000' and v_kind = 'supplier') or (v_code in ('2100', '1320') and v_kind = 'worker')) then
    raise exception 'INVARIANT VIOLATION: only a Suppliers (2000) line can carry a supplier, and only a wages owed / worker advance line a worker' using errcode = 'check_violation';
  end if;
  return new;
end $$;

-- what we owe him (2100) and the advance he has (1320)
create function app.worker_owed(p_party_id integer) returns bigint language sql stable set search_path = '' as $$
  select coalesce(sum(l.credit_paisa - l.debit_paisa), 0)::bigint from app.ledger_entries l
    join app.accounts a on a.id = l.account_id and a.code = '2100' where l.party_id = p_party_id
$$;
create function app.worker_advance(p_party_id integer) returns bigint language sql stable set search_path = '' as $$
  select coalesce(sum(l.debit_paisa - l.credit_paisa), 0)::bigint from app.ledger_entries l
    join app.accounts a on a.id = l.account_id and a.code = '1320' where l.party_id = p_party_id
$$;

create function public.save_worker(p_party_id integer, p_name text, p_phone text, p_pay_type text, p_rate_paisa bigint,
  p_area text, p_active boolean default true) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_id integer := p_party_id; v_name text := btrim(coalesce(p_name, ''));
begin
  perform app.require_user();
  if v_name = '' then
    raise exception 'INVARIANT VIOLATION: worker name is required' using errcode = 'check_violation';
  end if;
  if exists (select 1 from app.parties p where p.kind = 'worker' and lower(btrim(p.name)) = lower(v_name) and p.id is distinct from v_id) then
    raise exception 'INVARIANT VIOLATION: a worker called % already exists', v_name using errcode = 'check_violation';
  end if;
  if v_id is null then
    insert into app.parties (party_ref, name, phone, kind) values (app.next_party_ref(), v_name, nullif(btrim(p_phone), ''), 'worker')
    returning id into v_id;
    insert into app.workers (party_id, pay_type, rate_paisa, area) values (v_id, p_pay_type, p_rate_paisa, p_area);
  else
    update app.parties set name = v_name, phone = nullif(btrim(p_phone), ''), is_active = coalesce(p_active, true)
     where id = v_id and kind = 'worker';
    if not found then
      raise exception 'INVARIANT VIOLATION: unknown worker' using errcode = 'check_violation';
    end if;
    update app.workers set pay_type = p_pay_type, rate_paisa = p_rate_paisa, area = p_area where party_id = v_id;
  end if;
  return v_id;
end $$;

create function app.record_work_impl(p_party_id integer, p_qty numeric, p_wage_paisa bigint, p_occurred_on date, p_note text,
  p_user uuid, p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ref text; v_id integer; v_name text; w app.workers%rowtype; v_adv bigint; v_used bigint; v_unit text;
begin
  if p_idempotency_key is not null then
    select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
    if found then return jsonb_build_object('duplicate', true, 'event_ref', v_ref); end if;
  end if;
  select p.name into v_name from app.parties p where p.id = p_party_id and p.kind = 'worker' for update;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown worker' using errcode = 'check_violation';
  end if;
  select * into w from app.workers where party_id = p_party_id;
  if p_wage_paisa is null or p_wage_paisa <= 0 then
    raise exception 'INVARIANT VIOLATION: the wage must be more than 0' using errcode = 'check_violation';
  end if;
  v_adv := greatest(app.worker_advance(p_party_id), 0);
  v_used := least(v_adv, p_wage_paisa);
  v_unit := case w.pay_type when 'day' then 'days' when 'bag' then 'bags' when 'ton' then 'tons' else 'x fixed' end;

  v_ref := app.next_event_ref();
  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by, idempotency_key)
  values (v_ref, 'work_done', p_occurred_on,
          'Work done: ' || v_name || coalesce(', ' || trim(trailing '.' from trim(trailing '0' from p_qty::text)) || ' ' || v_unit, '')
            || ' = Rs ' || (p_wage_paisa / 100.0)::numeric(14,2)
            || case when v_used > 0 then ' (Rs ' || (v_used / 100.0)::numeric(14,2) || ' from his advance)' else '' end
            || coalesce(' - ' || nullif(btrim(p_note), ''), ''),
          'employee', v_name, 'app', p_user, p_idempotency_key)
  returning id into v_id;
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa, party_id)
  select v_id, (row_number() over (order by x.seq))::smallint, a.id, x.dr, x.cr, x.party
    from (values (1, case w.area when 'plant' then '5420' else '5000' end, p_wage_paisa, 0::bigint, null::integer),
                 (2, '1320', 0::bigint, v_used, p_party_id),
                 (3, '2100', 0::bigint, p_wage_paisa - v_used, p_party_id)) x(seq, code, dr, cr, party)
    join app.accounts a on a.code = x.code
   where x.dr > 0 or x.cr > 0;
  return jsonb_build_object('event_ref', v_ref, 'worker', v_name, 'wage_paisa', p_wage_paisa, 'advance_used_paisa', v_used,
                            'owed_after_paisa', app.worker_owed(p_party_id), 'advance_after_paisa', app.worker_advance(p_party_id));
end $$;

create function public.record_work(p_party_id integer, p_qty numeric, p_wage_paisa bigint, p_occurred_on date,
  p_note text default null, p_idempotency_key text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  return app.record_work_impl(p_party_id, p_qty, p_wage_paisa, p_occurred_on, p_note, app.require_user(), p_idempotency_key);
end $$;

create function app.pay_worker_impl(p_party_id integer, p_amount_paisa bigint, p_from text, p_occurred_on date, p_note text,
  p_user uuid, p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ref text; v_id integer; v_name text; v_owed bigint; v_debt bigint; v_extra bigint; v_acc text; v_bank bigint;
begin
  if p_idempotency_key is not null then
    select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
    if found then return jsonb_build_object('duplicate', true, 'event_ref', v_ref); end if;
  end if;
  select p.name into v_name from app.parties p where p.id = p_party_id and p.kind = 'worker' for update;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown worker' using errcode = 'check_violation';
  end if;
  if p_amount_paisa is null or p_amount_paisa <= 0 then
    raise exception 'INVARIANT VIOLATION: payment amount must be positive' using errcode = 'check_violation';
  end if;
  v_acc := case p_from when 'cash' then '1000' when 'bank' then '1050' end;
  if v_acc is null then
    raise exception 'INVARIANT VIOLATION: pay from cash or bank' using errcode = 'check_violation';
  end if;
  if v_acc = '1050' then
    select coalesce(sum(l.debit_paisa - l.credit_paisa), 0) into v_bank from app.ledger_entries l join app.accounts a on a.id = l.account_id and a.code = '1050';
    if v_bank < p_amount_paisa then
      raise exception 'INVARIANT VIOLATION: only Rs % in the bank', (v_bank / 100.0)::numeric(14,2) using errcode = 'check_violation';
    end if;
  end if;
  v_owed := greatest(app.worker_owed(p_party_id), 0);
  v_debt := least(v_owed, p_amount_paisa);
  v_extra := p_amount_paisa - v_debt;

  v_ref := app.next_event_ref();
  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by, idempotency_key)
  values (v_ref, 'worker_payment', p_occurred_on,
          'Paid ' || v_name || ' Rs ' || (p_amount_paisa / 100.0)::numeric(14,2) || case when v_acc = '1050' then ' from bank' else '' end
            || case when v_extra > 0 then ' (Rs ' || (v_extra / 100.0)::numeric(14,2) || ' advance / peshgi)' else '' end
            || coalesce(' - ' || nullif(btrim(p_note), ''), ''),
          'employee', v_name, 'app', p_user, p_idempotency_key)
  returning id into v_id;
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa, party_id)
  select v_id, (row_number() over (order by x.seq))::smallint, a.id, x.dr, x.cr, x.party
    from (values (1, '2100', v_debt, 0::bigint, p_party_id),
                 (2, '1320', v_extra, 0::bigint, p_party_id),
                 (3, v_acc, 0::bigint, p_amount_paisa, null::integer)) x(seq, code, dr, cr, party)
    join app.accounts a on a.code = x.code
   where x.dr > 0 or x.cr > 0;
  return jsonb_build_object('event_ref', v_ref, 'worker', v_name, 'paid_paisa', p_amount_paisa, 'cleared_paisa', v_debt,
                            'advance_paisa', v_extra, 'owed_after_paisa', app.worker_owed(p_party_id),
                            'advance_after_paisa', app.worker_advance(p_party_id));
end $$;

create function public.pay_worker(p_party_id integer, p_amount_paisa bigint, p_from text, p_occurred_on date,
  p_note text default null, p_idempotency_key text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  return app.pay_worker_impl(p_party_id, p_amount_paisa, p_from, p_occurred_on, p_note, app.require_user(), p_idempotency_key);
end $$;

create view public.v_workers with (security_invoker = true) as
select p.id as party_id, p.party_ref, p.name, p.phone, p.is_active, w.pay_type, w.rate_paisa, w.area,
       app.worker_owed(p.id) as owed_paisa, app.worker_advance(p.id) as advance_paisa,
       (select max(e.occurred_on) from app.events e join app.ledger_entries l on l.event_id = e.id
         where l.party_id = p.id and e.event_type = 'work_done') as last_work_on,
       (select max(e.occurred_on) from app.events e join app.ledger_entries l on l.event_id = e.id
         where l.party_id = p.id and e.event_type = 'worker_payment') as last_paid_on
  from app.parties p join app.workers w on w.party_id = p.id
 where p.kind = 'worker';

-- one row per entry per worker: what it did to what we owe him and to his advance
create view public.v_worker_history with (security_invoker = true) as
select l.party_id, e.id as event_id, e.event_ref, e.occurred_on, e.event_type, e.description,
       sum(case when a.code = '2100' then l.credit_paisa - l.debit_paisa else 0 end)::bigint as owed_change_paisa,
       sum(case when a.code = '1320' then l.debit_paisa - l.credit_paisa else 0 end)::bigint as advance_change_paisa
  from app.ledger_entries l join app.accounts a on a.id = l.account_id and a.code in ('2100', '1320')
  join app.events e on e.id = l.event_id
  join app.parties p on p.id = l.party_id and p.kind = 'worker'
 group by l.party_id, e.id, e.event_ref, e.occurred_on, e.event_type, e.description;

-- entries with wages owed / worker advance lines: delete and enter again (never corrected in place)
create or replace function app.correct_entry_blocker(p_orig app.events) returns text language plpgsql stable set search_path = '' as $$
declare
  v_root   app.events%rowtype;
  v_latest app.events%rowtype;
begin
  select * into v_root from app.events o
   where o.event_ref = case when p_orig.source = 'correction' and p_orig.source_ref is not null then p_orig.source_ref else p_orig.event_ref end;
  if not found then v_root := p_orig; end if;
  select * into v_latest from app.events e
   where e.id = v_root.id or (e.source = 'correction' and e.source_ref = v_root.event_ref) order by e.id desc limit 1;
  if v_latest.id <> p_orig.id then
    return format('%s was replaced by %s - correct %s instead.', p_orig.event_ref, v_latest.event_ref, v_latest.event_ref);
  end if;
  if v_root.event_type not in ('expense', 'asset_purchase', 'asset_disposal', 'capital_injection', 'owner_drawing', 'other')
     or exists (select 1 from app.movements m join app.events e on e.id = m.event_id
                 where e.id = v_root.id or (e.source = 'correction' and e.source_ref = v_root.event_ref))
     or exists (select 1 from app.ledger_entries le join app.accounts a on a.id = le.account_id join app.events e on e.id = le.event_id
                 where (e.id = v_root.id or (e.source = 'correction' and e.source_ref = v_root.event_ref))
                   and (a.code in ('1100', '2000', '2100', '2200', '1320') or a.code like '12%')) then
    return 'Only money entries can be corrected here. For sales, purchases, crush runs and payments: delete it and enter it again.';
  end if;
  return null;
end $$;

-- the correct version of a money entry may not use the worker accounts either (exact text replace; stops if not found)
do $$
declare v_def text := pg_get_functiondef('app.correct_entry_impl(text,date,jsonb,text,text,uuid,boolean)'::regprocedure);
begin
  if position($q$v_line->>'account' in ('1100', '2000', '2200')$q$ in v_def) = 0 then
    raise exception 'STOP: correct_entry_impl text not found';
  end if;
  execute replace(v_def, $q$v_line->>'account' in ('1100', '2000', '2200')$q$, $q$v_line->>'account' in ('1100', '2000', '2100', '2200', '1320')$q$);
end $$;

-- after a delete / restore: no worker owed less than 0, no advance below 0
do $$
declare v_def text := pg_get_functiondef('app.check_books_after_change(text)'::regprocedure);
        v_anchor text := $q$  select string_agg(p.name, ', ') into v_bad from app.parties p
   where (select coalesce(sum(case when c.direction = 'received' then c.amount_paisa else -c.amount_paisa end), 0)$q$;
begin
  if position(v_anchor in v_def) = 0 then
    raise exception 'STOP: check_books_after_change text not found';
  end if;
  execute replace(v_def, v_anchor, $q$  select string_agg(p.name, ', ') into v_bad from app.parties p
   where p.kind = 'worker' and (app.worker_owed(p.id) < 0 or app.worker_advance(p.id) < 0);
  if v_bad is not null then
    raise exception 'Cannot %: the wages of % would not add up (a later work or pay entry uses this one). Delete the later one first. Nothing was changed.', p_what, v_bad using errcode = 'check_violation';
  end if;
$q$ || v_anchor);
end $$;

revoke all on function app.worker_owed(integer), app.worker_advance(integer),
  app.record_work_impl(integer, numeric, bigint, date, text, uuid, text),
  app.pay_worker_impl(integer, bigint, text, date, text, uuid, text) from public, anon, authenticated;
revoke all on function public.save_worker(integer, text, text, text, bigint, text, boolean),
  public.record_work(integer, numeric, bigint, date, text, text),
  public.pay_worker(integer, bigint, text, date, text, text) from public, anon, authenticated, service_role;
grant execute on function public.save_worker(integer, text, text, text, bigint, text, boolean),
  public.record_work(integer, numeric, bigint, date, text, text),
  public.pay_worker(integer, bigint, text, date, text, text) to authenticated;
-- the views read these as the signed-in person
grant execute on function app.worker_owed(integer), app.worker_advance(integer) to authenticated, service_role;
revoke all on public.v_workers, public.v_worker_history from public, anon;
grant select on public.v_workers, public.v_worker_history to authenticated, service_role;
grant select on app.workers to authenticated;
