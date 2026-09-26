-- ============ Phase 3 helpers, advances, hardened payment ============

-- Generic idempotency on the audit trail (nullable; unique when present)
alter table app.events add column if not exists idempotency_key text;
create unique index if not exists uq_events_idem on app.events (idempotency_key) where idempotency_key is not null;

-- Reference generators
create or replace function app.next_sale_ref() returns text
language sql set search_path = 'app' as
$$ select 'INV-' || lpad(nextval('app.sale_ref_seq')::text, 5, '0') $$;

create or replace function app.next_dispatch_ref() returns text
language sql set search_path = 'app' as
$$ select 'DSP-' || lpad(nextval('app.dispatch_ref_seq')::text, 5, '0') $$;

-- Exact batch unit cost (paisa per kg) from the batch's own movement book value
create or replace function app.batch_unit_cost_paisa_per_kg(p_batch_id integer)
returns bigint language plpgsql stable set search_path = 'app' as $fn$
declare
  v_qty bigint; v_val bigint;
begin
  select coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0),
         coalesce(sum(m.value_paisa), 0)
    into v_qty, v_val
  from app.movements m where m.batch_id = p_batch_id;
  if v_qty is null or v_qty <= 0 then return 0; end if;
  return round(v_val::numeric / (v_qty / 1000.0));
end $fn$;

-- Belt-and-braces: reject multi-row event inserts (silent trigger bypass)
create or replace function app.restrict_single_statement_insert()
returns trigger language plpgsql set search_path = 'app' as $fn$
begin
  if tg_n_rows > 1 then
    raise exception 'INVARIANT VIOLATION: multi-row insert into app.% bypasses per-event balance trigger', tg_table_name
      using errcode = 'feature_not_supported';
  end if;
  return null;
end $fn$;

drop trigger if exists trg_events_single_row on app.events;
create trigger trg_events_single_row
after insert on app.events
referencing new table as inserted
for each statement execute function app.restrict_single_statement_insert();

-- Derive and freeze sale money state from the ledger (no stored drift)
create or replace function app.set_sale_state()
returns trigger language plpgsql set search_path = 'app' as $fn$
declare
  v_rev bigint; v_cash bigint; v_adv bigint;
begin
  select coalesce(sum(le.credit_paisa - le.debit_paisa), 0) into v_rev
  from app.ledger_entries le join app.accounts a on a.id = le.account_id
  where le.event_id = new.id and a.code = '4000';
  select coalesce(sum(le.debit_paisa), 0) into v_cash
  from app.ledger_entries le join app.accounts a on a.id = le.account_id
  where le.event_id = new.id and a.code = '1000';
  select coalesce(sum(le.debit_paisa), 0) into v_adv
  from app.ledger_entries le join app.accounts a on a.id = le.account_id
  where le.event_id = new.id and a.code = '2200';
  update app.sales set
    total_revenue_paisa = coalesce(v_rev, 0),
    cash_received_paisa = coalesce(v_cash, 0),
    advance_applied_paisa = coalesce(v_adv, 0),
    ar_paisa = coalesce(v_rev, 0) - coalesce(v_cash, 0) - coalesce(v_adv, 0)
  where id = new.idempotency_key::integer;
  return null;
end $fn$;

drop trigger if exists trg_set_sale_state on app.events;
create trigger trg_set_sale_state
after insert on app.events
referencing new table as inserted
for each statement execute function app.set_sale_state();

-- FIFO pool: oldest open batches of the EXACT product at the EXACT location
create or replace function app.fifo_pool(p_product_id smallint, p_location_id smallint)
returns table (batch_id integer, batch_code text, opened_on date,
               onhand_grams bigint, unit_cost_ppk bigint)
language sql stable set search_path = 'app' as $fn$
  select b.id, b.batch_code, b.opened_on,
         coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0)::bigint,
         app.batch_unit_cost_paisa_per_kg(b.id)
  from app.batches b join app.movements m on m.batch_id = b.id
  where b.product_id = p_product_id and b.location_id = p_location_id
    and b.status = 'open'
  group by b.id, b.batch_code, b.opened_on
  having coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0) > 0
  order by b.opened_on, b.id
$fn$;

-- Customer advance: Dr Cash / Cr 2200 (never revenue)
create or replace function app.record_advance(
  p_party text,
  p_amount_paisa bigint,
  p_occurred_on date default current_date,
  p_note text default null,
  p_idempotency_key text default null,
  p_created_by uuid default null
) returns jsonb language plpgsql security definer set search_path = 'app' as $fn$
declare
  v_party app.parties%rowtype;
  v_amt bigint := coalesce(p_amount_paisa, 0);
  v_ref text;
begin
  if v_amt <= 0 then
    raise exception 'INVARIANT VIOLATION: advance amount must be positive' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is not null and exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
    return jsonb_build_object('duplicate', true);
  end if;
  select * into v_party from app.parties
  where kind = 'customer' and (party_ref = p_party or lower(name) = lower(p_party));
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown customer %', p_party using errcode = 'check_violation';
  end if;

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'customer_advance', p_occurred_on,
    'Customer advance from ' || v_party.name || ' - ' || (v_amt / 100.0)::numeric(14,2) || ' PKR held as liability (not revenue)'
    || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
    'customer', v_party.id, v_party.name, 'app', p_created_by, p_idempotency_key)
  returning event_ref into v_ref;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select e.id, x.seq, a.id, x.dr, x.cr
  from app.events e,
       (values (1, '1000', v_amt, 0::bigint), (2, '2200', 0::bigint, v_amt)) as x(seq, acc_code, dr, cr)
  join app.accounts a on a.code = x.acc_code
  where e.event_ref = v_ref;

  insert into app.customer_advances (event_id, party_id, direction, amount_paisa, occurred_on, idempotency_key, note, created_by)
  select e.id, v_party.id, 'received', v_amt, p_occurred_on, p_idempotency_key, p_note, p_created_by
  from app.events e where e.event_ref = v_ref;

  return jsonb_build_object('event_ref', v_ref, 'party_ref', v_party.party_ref, 'amount_paisa', v_amt);
end $fn$;

-- Harden record_customer_payment: + idempotency (replace v1, same signature + optional key)
create or replace function public.record_customer_payment(
  p_customer text,
  p_amount_paisa bigint,
  p_occurred_on date default current_date,
  p_note text default null,
  p_created_by uuid default null,
  p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path = 'app' as $fn$
declare
  v_customer text := btrim(coalesce(p_customer, ''));
  v_amount bigint := coalesce(p_amount_paisa, 0);
  v_party app.parties%rowtype;
  v_outstanding bigint;
  v_event_ref text;
begin
  if v_customer = '' then
    raise exception 'INVARIANT VIOLATION: customer is required' using errcode = 'check_violation';
  end if;
  if v_amount <= 0 then
    raise exception 'INVARIANT VIOLATION: payment amount must be positive' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is not null and exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
    return jsonb_build_object('duplicate', true);
  end if;

  select * into v_party from app.parties
  where kind = 'customer' and (party_ref = v_customer or lower(name) = lower(v_customer));
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown customer %', v_customer using errcode = 'check_violation';
  end if;

  select coalesce(sum(le.debit_paisa - le.credit_paisa), 0)::bigint into v_outstanding
  from app.ledger_entries le
  join app.accounts a on a.id = le.account_id and a.code = '1100'
  join app.events e on e.id = le.event_id
  where e.party_id = v_party.id;

  if v_amount > v_outstanding then
    raise exception 'INVARIANT VIOLATION: payment % exceeds %s outstanding receivable of % - overpayments belong on Customer Advances, not here',
      (v_amount / 100.0)::numeric(14,2), v_party.name, (v_outstanding / 100.0)::numeric(14,2)
      using errcode = 'check_violation';
  end if;

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'customer_payment', p_occurred_on,
    'Customer payment from ' || v_party.name || ' - ' || (v_amount / 100.0)::numeric(14,2) ||
    ' PKR against receivable' || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
    'customer', v_party.id, v_party.name, 'app', p_created_by, p_idempotency_key)
  returning event_ref into v_event_ref;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select e.id, x.seq, a.id, x.dr, x.cr
  from app.events e,
       (values (1, '1000', v_amount, 0::bigint), (2, '1100', 0::bigint, v_amount)) as x(seq, acc_code, dr, cr)
  join app.accounts a on a.code = x.acc_code
  where e.event_ref = v_event_ref;

  return jsonb_build_object('event_ref', v_event_ref, 'party_ref', v_party.party_ref,
    'amount_paisa', v_amount, 'remaining_ar_paisa', v_outstanding - v_amount);
end $fn$;

create or replace function public.create_customer(p_name text, p_phone text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = 'app' as $fn$
declare
  v_name text := btrim(p_name);
  v_id integer;
  v_ref text;
begin
  if v_name is null or v_name = '' then
    raise exception 'INVARIANT VIOLATION: customer name is required' using errcode = 'check_violation';
  end if;
  select id, party_ref into v_id, v_ref from app.parties where lower(name) = lower(v_name) and kind = 'customer';
  if found then
    return jsonb_build_object('party_id', v_id, 'party_ref', v_ref, 'created', false);
  end if;
  v_ref := app.next_party_ref();
  insert into app.parties (party_ref, name, phone, kind, note)
  values (v_ref, v_name, nullif(btrim(coalesce(p_phone, '')), ''), 'customer', nullif(btrim(coalesce(p_note, '')), ''))
  returning id into v_id;
  return jsonb_build_object('party_id', v_id, 'party_ref', v_ref, 'created', true);
end $fn$;