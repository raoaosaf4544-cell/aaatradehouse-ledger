-- =====================================================================
-- AAA Trade House Ledger — Phase 2: Inventory operations
-- =====================================================================
-- Shipped to the live database on 2026-09-18 and verified with
-- assertion-based rollback tests (all passed; live books untouched:
-- 1 batch, 101 events after every test run).
--
-- Contents:
--   * Corrected stock semantics: on-hand = SUM(in) - SUM(out) only.
--     'wastage' movement rows are value-attribution REPORTING rows —
--     they never decrement quantity twice.
--   * app.v_stock_onhand / app.v_batches (+ public wrappers) with
--     wastage qty/value columns.
--   * public.record_purchase(...): creates a new batch (BATCH-00n),
--     posts Dr Inventory / Cr Cash-or-AP, logs the receipt movement.
--   * public.record_process_run(...) v6: consumes an input batch at its
--     TRUE book value (SUM of ALL movement values — prevents re-adding
--     previously expensed wastage to the remaining basis), prices output
--     grades by weight-share with cumulative rounding (sums EXACTLY),
--     gives wastage its direct weight-share of the cost pool, closes a
--     fully consumed batch to exactly zero, supports multi-generation
--     batch chains (BATCH-001 -> G1 -> G1-G1).
--
-- Invariants enforced elsewhere (Phase 0) still apply: statement-level
-- Dr=Cr trigger, cash >= 0, stock >= 0, unique event_ref.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Stock views (quantity = in - out only; wastage reported separately)
-- ---------------------------------------------------------------------

create or replace view app.v_stock_onhand as
select b.batch_code, p.code as product_code, p.name as product_name, l.code as location_code, l.name as location_name,
       sum(case when m.direction = 'in' then m.qty_grams
                when m.direction = 'out' then -m.qty_grams
                else 0 end) as qty_grams,
       sum(m.value_paisa) as value_paisa,
       sum(case when m.direction = 'wastage' then m.qty_grams else 0 end) as wastage_qty_grams,
       sum(case when m.direction = 'wastage' then -m.value_paisa else 0 end) as wastage_value_paisa
from app.movements m
join app.batches b on b.id = m.batch_id
join app.products p on p.id = m.product_id
join app.locations l on l.id = m.location_id
group by b.batch_code, p.code, p.name, l.code, l.name;

create or replace view public.v_stock_onhand with (security_invoker = true) as
  select * from app.v_stock_onhand;

create or replace view app.v_batches as
  select b.id, b.batch_code, b.product_id, p.code as product_code, p.name as product_name,
         b.location_id, l.code as location_code, l.name as location_name,
         b.status, b.opened_on, b.note,
         coalesce(sum(case when m.direction = 'in' then m.qty_grams
                           when m.direction = 'out' then -m.qty_grams
                           else 0 end), 0) as onhand_grams,
         coalesce(sum(m.value_paisa), 0) as value_paisa,
         coalesce(sum(case when m.direction = 'wastage' then m.qty_grams else 0 end), 0) as wastage_grams,
         coalesce(sum(case when m.direction = 'wastage' then -m.value_paisa else 0 end), 0) as wastage_value_paisa
  from app.batches b
  join app.products p on p.id = b.product_id
  join app.locations l on l.id = b.location_id
  left join app.movements m on m.batch_id = b.id
  group by b.id, b.batch_code, b.product_id, p.code, p.name, b.location_id, l.code, l.name, b.status, b.opened_on, b.note;

create or replace view public.v_batches with (security_invoker = true) as
  select * from app.v_batches;

-- ---------------------------------------------------------------------
-- 2) record_purchase
-- ---------------------------------------------------------------------

create or replace function public.record_purchase(
  p_supplier text,
  p_product_code text,
  p_location_code text,
  p_qty_grams bigint,
  p_landed_cost_paisa bigint,
  p_pay_cash boolean,
  p_occurred_on date,
  p_note text default null,
  p_created_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'app'
as $fn$
declare
  v_product app.products%rowtype;
  v_location app.locations%rowtype;
  v_batch_code text;
  v_batch_id integer;
  v_event_ref text;
  v_credit_account text;
begin
  -- validation
  if p_supplier is null or btrim(p_supplier) = '' then
    raise exception 'INVARIANT VIOLATION: supplier name is required' using errcode = 'check_violation';
  end if;
  if p_qty_grams is null or p_qty_grams <= 0 then
    raise exception 'INVARIANT VIOLATION: quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_landed_cost_paisa is null or p_landed_cost_paisa <= 0 then
    raise exception 'INVARIANT VIOLATION: landed cost must be positive' using errcode = 'check_violation';
  end if;

  select * into v_product from app.products where code = p_product_code;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown product code %', p_product_code using errcode = 'check_violation';
  end if;
  select * into v_location from app.locations where code = p_location_code;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown location code %', p_location_code using errcode = 'check_violation';
  end if;

  -- new batch code (sequence skips any existing codes, e.g. BATCH-001)
  v_batch_code := 'BATCH-' || lpad(nextval('app.batch_ref_seq')::text, 3, '0');
  while exists (select 1 from app.batches where batch_code = v_batch_code) loop
    v_batch_code := 'BATCH-' || lpad(nextval('app.batch_ref_seq')::text, 3, '0');
  end loop;

  insert into app.batches (batch_code, product_id, location_id, opened_on, note)
  values (v_batch_code, v_product.id, v_location.id, p_occurred_on,
          'Purchased from ' || btrim(p_supplier) || coalesce(' — ' || nullif(btrim(p_note), ''), ''))
  returning id into v_batch_id;

  v_credit_account := case when p_pay_cash then '1000' else '2000' end;

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by)
  values (app.next_event_ref(), 'purchase', p_occurred_on,
          'Salt purchase from ' || btrim(p_supplier) || ' — ' || (p_qty_grams / 1000.0)::numeric(12,1) || ' kg, landed cost ' || (p_landed_cost_paisa / 100.0)::numeric(14,2) || ' PKR, batch ' || v_batch_code,
          'supplier', btrim(p_supplier), 'app', p_created_by)
  returning event_ref into v_event_ref;

  -- balanced ledger (single statement for the statement-level balance trigger)
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select e.id, x.seq, a.id, x.dr, x.cr
  from app.events e,
       (values (1, (select code from app.accounts where kind = 'inventory' and code = case v_product.form when 'raw' then '1200' when 'bulk_processed' then '1210' when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end), p_landed_cost_paisa, 0::bigint),
               (2, v_credit_account, 0::bigint, p_landed_cost_paisa)) as x(seq, acc_code, dr, cr)
  join app.accounts a on a.code = x.acc_code
  where e.event_ref = v_event_ref;

  -- movement (value positive on receipt)
  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  select e.id, 1, v_product.id, v_batch_id, v_location.id, 'in', p_qty_grams, p_landed_cost_paisa
  from app.events e where e.event_ref = v_event_ref;

  return jsonb_build_object('event_ref', v_event_ref, 'batch_code', v_batch_code);
end $fn$;

-- ---------------------------------------------------------------------
-- 3) record_process_run (v6)
-- ---------------------------------------------------------------------

create or replace function public.record_process_run(
  p_input_batch_code text,
  p_input_qty_grams bigint,
  p_outputs jsonb,
  p_wastage_grams bigint,
  p_conversion_cost_paisa bigint,
  p_pay_cash boolean,
  p_occurred_on date,
  p_note text default null,
  p_created_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'app'
as $fn$
declare
  v_input_batch   app.batches%rowtype;
  v_input_product app.products%rowtype;
  v_input_loc     app.locations%rowtype;
  v_onhand        bigint;
  v_input_value   bigint;
  v_pool          bigint;
  v_out_qty       bigint := 0;
  v_out_total     bigint := 0;
  v_wast_value    bigint := 0;
  v_remaining     bigint;
  v_cum           bigint := 0;
  v_target_cum    bigint := 0;
  v_assigned_cum  bigint := 0;
  v_assigned      bigint := 0;
  v_i             int := 0;
  v_explicit      boolean := false;
  v_event_ref     text;
  v_event_id      integer;
  v_line          jsonb;
  v_prod          app.products%rowtype;
  v_batch_code    text;
  v_batch_id      integer;
  v_lines         jsonb := '[]'::jsonb;
  v_result        jsonb := '[]'::jsonb;
  v_grade         int := 0;
  v_seq           smallint := 0;
  v_inv_account   text;
begin
  if p_input_qty_grams is null or p_input_qty_grams <= 0 then
    raise exception 'INVARIANT VIOLATION: input quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_wastage_grams is null or p_wastage_grams < 0 then
    raise exception 'INVARIANT VIOLATION: wastage cannot be negative' using errcode = 'check_violation';
  end if;
  if p_outputs is null or jsonb_typeof(p_outputs) <> 'array' or jsonb_array_length(p_outputs) = 0 then
    raise exception 'INVARIANT VIOLATION: at least one output grade is required' using errcode = 'check_violation';
  end if;
  if p_conversion_cost_paisa is null or p_conversion_cost_paisa < 0 then
    raise exception 'INVARIANT VIOLATION: conversion cost cannot be negative' using errcode = 'check_violation';
  end if;

  select * into v_input_batch from app.batches where batch_code = p_input_batch_code;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown input batch %', p_input_batch_code using errcode = 'check_violation';
  end if;
  select * into v_input_product from app.products where id = v_input_batch.product_id;
  select * into v_input_loc from app.locations where id = v_input_batch.location_id;

  -- on-hand: ONLY 'out' decrements ('wastage' rows are value-attribution records)
  select coalesce(sum(case when direction = 'in' then qty_grams
                           when direction = 'out' then -qty_grams
                           else 0 end), 0)
    into v_onhand
    from app.movements where batch_id = v_input_batch.id;

  if p_input_qty_grams > v_onhand then
    raise exception 'INVARIANT VIOLATION: cannot consume % g from batch % — only % g on hand',
      p_input_qty_grams, p_input_batch_code, v_onhand using errcode = 'check_violation';
  end if;

  -- TRUE book value of the consumed quantity = SUM of ALL movement values
  -- ('in' positive; 'out' and 'wastage' stored negative). Filtering to in+out
  -- only would re-add previously expensed wastage to the remaining basis.
  select coalesce(sum(value_paisa), 0) into v_input_value
    from app.movements where batch_id = v_input_batch.id;
  v_input_value := round(v_input_value::numeric * p_input_qty_grams / v_onhand);
  v_pool := v_input_value + p_conversion_cost_paisa;

  for v_line in select * from jsonb_array_elements(p_outputs) loop
    if coalesce((v_line->>'qty_grams')::bigint, 0) <= 0 then
      raise exception 'INVARIANT VIOLATION: output quantities must be positive' using errcode = 'check_violation';
    end if;
    v_out_qty := v_out_qty + (v_line->>'qty_grams')::bigint;
    if coalesce((v_line->>'value_paisa')::bigint, 0) > 0 then
      v_explicit := true;
    end if;
  end loop;
  if v_out_qty + p_wastage_grams <> p_input_qty_grams then
    raise exception 'INVARIANT VIOLATION: mass conservation failed — output % g + wastage % g must equal input % g',
      v_out_qty, p_wastage_grams, p_input_qty_grams using errcode = 'check_violation';
  end if;

  -- wastage takes its direct weight-share of the total cost pool (material + conversion)
  if p_wastage_grams > 0 then
    v_wast_value := round(v_pool::numeric * p_wastage_grams / (p_wastage_grams + v_out_qty));
  end if;
  v_remaining := v_pool - v_wast_value;

  if v_explicit then
    -- explicit mode: caller-specified values (specific identification); residual is expensed
    for v_line in select * from jsonb_array_elements(p_outputs) loop
      if coalesce((v_line->>'value_paisa')::bigint, 0) < 0 then
        raise exception 'INVARIANT VIOLATION: output values cannot be negative' using errcode = 'check_violation';
      end if;
      v_out_total := v_out_total + coalesce((v_line->>'value_paisa')::bigint, 0);
    end loop;
    if v_out_total + v_wast_value > v_pool then
      raise exception 'INVARIANT VIOLATION: cost conservation failed — outputs % + wastage % paisa exceed pool %',
        v_out_total, v_wast_value, v_pool using errcode = 'check_violation';
    end if;
  else
    -- AUTO mode (the form default): the engine prices each grade by weight-share.
    -- Cumulative targets minus already-assigned keep the sum EXACTLY v_remaining.
    v_i := 0;
    v_assigned_cum := 0;
    for v_line in select * from jsonb_array_elements(p_outputs) loop
      v_i := v_i + 1;
      v_cum := v_cum + (v_line->>'qty_grams')::bigint;
      if v_i < jsonb_array_length(p_outputs) then
        v_target_cum := round(v_remaining::numeric * v_cum / v_out_qty);
        v_assigned := v_target_cum - v_assigned_cum;
      else
        v_assigned := v_remaining - v_assigned_cum;  -- last grade takes the exact remainder
      end if;
      v_assigned_cum := v_assigned_cum + v_assigned;
      v_out_total := v_out_total + v_assigned;
      p_outputs := jsonb_set(p_outputs, array[(v_i - 1)::text, 'value_paisa'], to_jsonb(v_assigned));
    end loop;
  end if;

  insert into app.events (event_ref, event_type, occurred_on, description, source, created_by)
  values (app.next_event_ref(), 'process_run', p_occurred_on,
          'Crush run: consumed ' || (p_input_qty_grams / 1000.0)::numeric(12,1) || ' kg of ' || p_input_batch_code ||
          ' → ' || (v_out_qty / 1000.0)::numeric(12,1) || ' kg graded output, ' || (p_wastage_grams / 1000.0)::numeric(12,1) || ' kg wastage' ||
          coalesce(' — ' || nullif(btrim(p_note), ''), ''),
          'app', p_created_by)
  returning event_ref, id into v_event_ref, v_event_id;

  -- 1) input consumption (out)
  v_seq := v_seq + 1;
  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  values (v_event_id, v_seq, v_input_product.id, v_input_batch.id, v_input_loc.id, 'out',
          p_input_qty_grams, -(v_input_value - v_wast_value));

  -- 2) graded outputs (in): new child batches
  v_i := 0;
  for v_line in select * from jsonb_array_elements(p_outputs) loop
    select * into v_prod from app.products where code = v_line->>'product_code';
    if not found then
      raise exception 'INVARIANT VIOLATION: unknown output product code %', v_line->>'product_code' using errcode = 'check_violation';
    end if;
    v_i := v_i + 1;
    v_grade := v_grade + 1;
    v_batch_code := p_input_batch_code || '-G' || v_grade::text;
    while exists (select 1 from app.batches where batch_code = v_batch_code) loop
      v_grade := v_grade + 1;
      v_batch_code := p_input_batch_code || '-G' || v_grade::text;
    end loop;
    insert into app.batches (batch_code, product_id, location_id, opened_on, note)
    values (v_batch_code, v_prod.id, v_input_batch.location_id, p_occurred_on,
            'Crush output from ' || p_input_batch_code || coalesce(' — ' || nullif(btrim(p_note), ''), ''))
    returning id into v_batch_id;

    v_seq := v_seq + 1;
    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    values (v_event_id, v_seq, v_prod.id, v_batch_id, v_input_batch.location_id, 'in',
            (v_line->>'qty_grams')::bigint, (v_line->>'value_paisa')::bigint);

    v_result := v_result || jsonb_build_object(
      'batch_code', v_batch_code, 'product_code', v_prod.code, 'product_name', v_prod.name,
      'qty_grams', (v_line->>'qty_grams')::bigint, 'value_paisa', (v_line->>'value_paisa')::bigint);
  end loop;

  -- 3) wastage — REPORTING row: quantity + value attribution, NOT a second quantity decrement
  if p_wastage_grams > 0 then
    v_seq := v_seq + 1;
    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    values (v_event_id, v_seq, v_input_product.id, v_input_batch.id, v_input_loc.id, 'wastage',
            p_wastage_grams, -v_wast_value);
  end if;

  v_lines := v_lines || jsonb_build_object('account',
    case v_input_product.form when 'raw' then '1200' when 'bulk_processed' then '1210' when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end,
    'credit', v_input_value);

  for v_line in select * from jsonb_array_elements(p_outputs) loop
    select * into v_prod from app.products where code = v_line->>'product_code';
    v_inv_account := case v_prod.form when 'raw' then '1200' when 'bulk_processed' then '1210' when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end;
    v_lines := v_lines || jsonb_build_object('account', v_inv_account, 'debit', (v_line->>'value_paisa')::bigint);
  end loop;

  if v_wast_value > 0 then
    v_lines := v_lines || jsonb_build_object('account', '5250', 'debit', v_wast_value);
  end if;
  if p_conversion_cost_paisa > 0 then
    v_lines := v_lines || jsonb_build_object('account', case when p_pay_cash then '1000' else '2000' end, 'credit', p_conversion_cost_paisa);
  end if;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event_id, (row_number() over (order by t.ord))::smallint, a.id,
         coalesce((t.o->>'debit')::bigint, 0), coalesce((t.o->>'credit')::bigint, 0)
  from jsonb_array_elements(v_lines) with ordinality t(o, ord)
  join app.accounts a on a.code = t.o->>'account';

  return jsonb_build_object('event_ref', v_event_ref, 'input_batch', p_input_batch_code,
    'input_value_paisa', v_input_value, 'wastage_grams', p_wastage_grams,
    'wastage_value_paisa', v_wast_value, 'outputs', v_result);
end
$fn$;

-- ---------------------------------------------------------------------
-- 4) Grants
-- ---------------------------------------------------------------------

grant execute on function public.record_purchase(text, text, text, bigint, bigint, boolean, date, text, uuid) to anon, authenticated;
grant execute on function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid) to anon, authenticated;
