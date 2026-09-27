-- Task 5 prep: optional idempotency key on post_event and record_process_run, the same pattern as
-- record_purchase / post_correction. The same key twice returns the first entry and writes nothing.
-- Each function keeps ONE signature (old one replaced; the key defaults to NULL), so existing calls
-- without a key resolve exactly as before and there is no ambiguous overload.

CREATE OR REPLACE FUNCTION app.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb, p_party_type text DEFAULT NULL::text, p_party_name text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_ref text;
  v_event_id integer;
  v_line jsonb;
  v_dr bigint;
  v_cr bigint;
  v_total_dr bigint := 0;
  v_total_cr bigint := 0;
begin
  -- same key twice (double tap / retry on bad signal): return the first entry, write nothing
  if p_idempotency_key is not null then
    select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
    if found then
      return v_ref;
    end if;
  end if;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'INVARIANT VIOLATION: at least two ledger lines are required'
      using errcode = 'check_violation';
  end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    if (select id from app.accounts where code = v_line->>'account') is null then
      raise exception 'INVARIANT VIOLATION: unknown account code %', v_line->>'account'
        using errcode = 'check_violation';
    end if;
    v_dr := coalesce((v_line->>'debit')::bigint, 0);
    v_cr := coalesce((v_line->>'credit')::bigint, 0);
    if v_dr < 0 or v_cr < 0 or (v_dr > 0 and v_cr > 0) or (v_dr = 0 and v_cr = 0) then
      raise exception 'INVARIANT VIOLATION: each line needs exactly one positive side (account %)', v_line->>'account'
        using errcode = 'check_violation';
    end if;
    v_total_dr := v_total_dr + v_dr;
    v_total_cr := v_total_cr + v_cr;
  end loop;
  if v_total_dr <> v_total_cr then
    raise exception 'INVARIANT VIOLATION: posting not balanced (debit %, credit % paisa)', v_total_dr, v_total_cr
      using errcode = 'check_violation';
  end if;

  v_ref := app.next_event_ref();

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by, idempotency_key)
  values (v_ref, p_event_type, p_occurred_on, p_description, p_party_type, p_party_name, 'app', p_created_by, p_idempotency_key)
  returning id into v_event_id;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event_id, (row_number() over (order by t.ord))::smallint, a.id,
         coalesce((t.line->>'debit')::bigint, 0), coalesce((t.line->>'credit')::bigint, 0)
  from jsonb_array_elements(p_lines) with ordinality t(line, ord)
  join app.accounts a on a.code = t.line->>'account';

  return v_ref;
end $function$;

drop function app.post_event(text, date, text, jsonb, text, text, uuid);

drop function public.post_event(text, date, text, jsonb, text, text, uuid);
create function public.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb,
  p_party_type text default null, p_party_name text default null, p_created_by uuid default null,
  p_idempotency_key text default null)
returns text language plpgsql security definer set search_path = app as $$
begin
  return app.post_event(p_event_type, p_occurred_on, p_description, p_lines, p_party_type, p_party_name,
    app.require_user(), p_idempotency_key);
end $$;

CREATE OR REPLACE FUNCTION app.record_process_run_impl(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_input_batch   app.batches%rowtype;
  v_input_product app.products%rowtype;
  v_input_loc     app.locations%rowtype;
  v_onhand        bigint;
  v_input_value   bigint;
  v_out_qty       bigint := 0;
  v_out_total     bigint := 0;
  v_leftover      bigint;
  v_wast_value    bigint := 0;
  v_wast_expense  bigint;
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
  -- same key twice (double tap / retry on bad signal): return the first run, write nothing
  if p_idempotency_key is not null then
    select event_ref into v_event_ref from app.events where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('duplicate', true, 'event_ref', v_event_ref);
    end if;
  end if;

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

  -- batch weighted-average cost of consumed quantity (numeric math: no truncation before rounding)
  select coalesce(sum(value_paisa), 0) into v_input_value
    from app.movements
   where batch_id = v_input_batch.id and direction in ('in','out');
  v_input_value := round(v_input_value::numeric * p_input_qty_grams / v_onhand);

  for v_line in select * from jsonb_array_elements(p_outputs) loop
    if coalesce((v_line->>'qty_grams')::bigint, 0) <= 0 then
      raise exception 'INVARIANT VIOLATION: output quantities must be positive' using errcode = 'check_violation';
    end if;
    v_out_qty := v_out_qty + (v_line->>'qty_grams')::bigint;
  end loop;
  if v_out_qty + p_wastage_grams <> p_input_qty_grams then
    raise exception 'INVARIANT VIOLATION: mass conservation failed — output % g + wastage % g must equal input % g',
      v_out_qty, p_wastage_grams, p_input_qty_grams using errcode = 'check_violation';
  end if;

  for v_line in select * from jsonb_array_elements(p_outputs) loop
    select * into v_prod from app.products where code = v_line->>'product_code';
    if not found then
      raise exception 'INVARIANT VIOLATION: unknown output product code %', v_line->>'product_code' using errcode = 'check_violation';
    end if;
    if coalesce((v_line->>'value_paisa')::bigint, 0) < 0 then
      raise exception 'INVARIANT VIOLATION: output values cannot be negative' using errcode = 'check_violation';
    end if;
    v_out_total := v_out_total + coalesce((v_line->>'value_paisa')::bigint, 0);
  end loop;
  if v_out_total > v_input_value + p_conversion_cost_paisa then
    raise exception 'INVARIANT VIOLATION: cost conservation failed — output value % paisa exceeds input value % + conversion cost %',
      v_out_total, v_input_value, p_conversion_cost_paisa using errcode = 'check_violation';
  end if;

  v_leftover := v_input_value + p_conversion_cost_paisa - v_out_total;
  if p_wastage_grams > 0 and v_leftover > 0 then
    v_wast_value := least(v_leftover, round(v_leftover::numeric * p_wastage_grams / (p_wastage_grams + v_out_qty)));
  end if;
  v_wast_expense := v_leftover - v_wast_value;

  insert into app.events (event_ref, event_type, occurred_on, description, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'process_run', p_occurred_on,
          'Crush run: consumed ' || (p_input_qty_grams / 1000.0)::numeric(12,1) || ' kg of ' || p_input_batch_code ||
          ' → ' || (v_out_qty / 1000.0)::numeric(12,1) || ' kg graded output, ' || (p_wastage_grams / 1000.0)::numeric(12,1) || ' kg wastage' ||
          coalesce(' — ' || nullif(btrim(p_note), ''), ''),
          'app', p_created_by, p_idempotency_key)
  returning event_ref, id into v_event_ref, v_event_id;

  -- 1) input consumption (out)
  v_seq := v_seq + 1;
  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  values (v_event_id, v_seq, v_input_product.id, v_input_batch.id, v_input_loc.id, 'out',
          p_input_qty_grams, -(v_input_value - v_wast_value));

  -- 2) graded outputs (in): new child batches
  for v_line in select * from jsonb_array_elements(p_outputs) loop
    select * into v_prod from app.products where code = v_line->>'product_code';
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

  if v_leftover > 0 then
    v_lines := v_lines || jsonb_build_object('account', '5250', 'debit', v_leftover);
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
    'wastage_value_paisa', v_wast_value, 'wastage_expense_paisa', v_wast_expense,
    'outputs', v_result);
end
$function$;

drop function app.record_process_run_impl(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid);

drop function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid);
create function public.record_process_run(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb,
  p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date,
  p_note text default null, p_created_by uuid default null, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.record_process_run_impl(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams,
    p_conversion_cost_paisa, p_pay_cash, p_occurred_on, p_note, app.require_user(), p_idempotency_key);
end $$;

revoke all on function app.post_event(text, date, text, jsonb, text, text, uuid, text) from public, anon, authenticated;
revoke all on function app.record_process_run_impl(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text) from public, anon, authenticated;
revoke all on function public.post_event(text, date, text, jsonb, text, text, uuid, text) from public, anon;
revoke all on function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text) from public, anon;
grant execute on function public.post_event(text, date, text, jsonb, text, text, uuid, text) to authenticated;
grant execute on function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text) to authenticated;
