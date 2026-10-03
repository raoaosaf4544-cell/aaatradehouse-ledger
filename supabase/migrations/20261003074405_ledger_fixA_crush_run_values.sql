-- Ledger fix A: crush runs.
-- The database now computes every value (the form's numbers are ignored), with ONE formula used by both the save and
-- the preview:
--   cost pool      = value of the salt taken out of the batch + conversion cost
--   wastage share  = pool x wastage kg / kg in                    (booked to 5250)
--   graded share   = pool - wastage share, split over the output grades by weight;
--                    the last grade takes the rounding remainder, so every total is exact to the paisa.
-- The batch value used is its true book value (all its movements), the figure the screens show.
-- Conversion cost "on credit" now needs the supplier (the crushing contractor), recorded on the entry like a purchase.

create function app.crush_run_values(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb,
                                     p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_batch   app.batches%rowtype;
  v_in      app.products%rowtype;
  v_prod    app.products%rowtype;
  v_onhand  bigint;
  v_book    numeric;
  v_input   bigint;
  v_pool    bigint;
  v_wast    bigint;
  v_share   bigint;
  v_out_g   bigint := 0;
  v_n       int;
  v_i       int := 0;
  v_val     bigint;
  v_given   bigint := 0;
  v_line    jsonb;
  v_codes   text[] := '{}';
  v_outs    jsonb := '[]';
  v_lines   jsonb;
  c_inv constant jsonb := '{"raw": "1200", "bulk_processed": "1210", "packaged": "1220", "packaging_material": "1230"}';
begin
  if p_input_qty_grams is null or p_input_qty_grams <= 0 then
    raise exception 'INVARIANT VIOLATION: kg in must be more than 0' using errcode = 'check_violation';
  end if;
  if p_wastage_grams is null or p_wastage_grams < 0 then
    raise exception 'INVARIANT VIOLATION: wastage cannot be negative' using errcode = 'check_violation';
  end if;
  if p_conversion_cost_paisa is null or p_conversion_cost_paisa < 0 then
    raise exception 'INVARIANT VIOLATION: conversion cost cannot be negative' using errcode = 'check_violation';
  end if;
  if p_outputs is null or jsonb_typeof(p_outputs) <> 'array' or jsonb_array_length(p_outputs) = 0 then
    raise exception 'INVARIANT VIOLATION: at least one output grade is required' using errcode = 'check_violation';
  end if;

  select * into v_batch from app.batches where batch_code = p_input_batch_code;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown input batch %', p_input_batch_code using errcode = 'check_violation';
  end if;
  select * into v_in from app.products where id = v_batch.product_id;
  if v_in.form <> 'raw' then
    raise exception 'INVARIANT VIOLATION: only rock salt can be crushed - % holds %', p_input_batch_code, v_in.name using errcode = 'check_violation';
  end if;

  select coalesce(sum(case m.direction when 'in' then m.qty_grams when 'out' then -m.qty_grams else 0 end), 0),
         coalesce(sum(m.value_paisa), 0)
    into v_onhand, v_book
    from app.movements m where m.batch_id = v_batch.id;
  if p_input_qty_grams > v_onhand then
    raise exception 'INVARIANT VIOLATION: only % kg of % in batch %', (v_onhand / 1000.0)::numeric(14,1), v_in.name, p_input_batch_code
      using errcode = 'check_violation';
  end if;

  v_n := jsonb_array_length(p_outputs);
  for v_line in select * from jsonb_array_elements(p_outputs) loop
    if coalesce((v_line->>'qty_grams')::bigint, 0) <= 0 then
      raise exception 'INVARIANT VIOLATION: every output grade needs kg more than 0' using errcode = 'check_violation';
    end if;
    select * into v_prod from app.products where code = v_line->>'product_code';
    if not found or not v_prod.is_active or v_prod.form <> 'bulk_processed' then
      raise exception 'INVARIANT VIOLATION: % is not a crush output grade', coalesce(v_prod.name, v_line->>'product_code') using errcode = 'check_violation';
    end if;
    if v_prod.code = any(v_codes) then
      raise exception 'INVARIANT VIOLATION: % is listed twice - put its kg on one line', v_prod.name using errcode = 'check_violation';
    end if;
    v_codes := v_codes || v_prod.code;
    v_out_g := v_out_g + (v_line->>'qty_grams')::bigint;
  end loop;
  if v_out_g + p_wastage_grams <> p_input_qty_grams then
    raise exception 'INVARIANT VIOLATION: crushed kg (%) + wastage (%) must equal kg in (%)',
      (v_out_g / 1000.0)::numeric(14,3), (p_wastage_grams / 1000.0)::numeric(14,3), (p_input_qty_grams / 1000.0)::numeric(14,3)
      using errcode = 'check_violation';
  end if;

  v_input := round(v_book * p_input_qty_grams / v_onhand);
  v_pool  := v_input + p_conversion_cost_paisa;
  v_wast  := round(v_pool::numeric * p_wastage_grams / p_input_qty_grams);
  v_share := v_pool - v_wast;

  v_lines := jsonb_build_array(jsonb_build_object('account', coalesce(c_inv->>v_in.form, '1500'), 'debit', 0, 'credit', v_input));
  for v_line in select * from jsonb_array_elements(p_outputs) loop
    v_i := v_i + 1;
    select * into v_prod from app.products where code = v_line->>'product_code';
    v_val := case when v_i < v_n then round(v_share::numeric * (v_line->>'qty_grams')::bigint / v_out_g) else v_share - v_given end;
    v_given := v_given + v_val;
    v_outs := v_outs || jsonb_build_object('product_code', v_prod.code, 'product_name', v_prod.name, 'form', v_prod.form,
                                           'qty_grams', (v_line->>'qty_grams')::bigint, 'value_paisa', v_val);
    v_lines := v_lines || jsonb_build_object('account', coalesce(c_inv->>v_prod.form, '1500'), 'debit', v_val, 'credit', 0);
  end loop;
  if v_wast > 0 then
    v_lines := v_lines || jsonb_build_object('account', '5250', 'debit', v_wast, 'credit', 0);
  end if;
  if p_conversion_cost_paisa > 0 then
    v_lines := v_lines || jsonb_build_object('account', case when p_pay_cash then '1000' else '2000' end, 'debit', 0, 'credit', p_conversion_cost_paisa);
  end if;

  return jsonb_build_object(
    'input_batch', p_input_batch_code, 'input_product_id', v_in.id, 'input_batch_id', v_batch.id, 'location_id', v_batch.location_id,
    'input_value_paisa', v_input, 'pool_paisa', v_pool, 'wastage_value_paisa', v_wast, 'graded_share_paisa', v_share,
    'output_grams', v_out_g, 'outputs', v_outs, 'lines', v_lines);
end $$;
revoke all on function app.crush_run_values(text, bigint, jsonb, bigint, bigint, boolean) from public, anon, authenticated;

drop function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text);
drop function app.record_process_run_impl(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text);

create function app.record_process_run_impl(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb,
  p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date,
  p_note text default null, p_created_by uuid default null, p_idempotency_key text default null, p_supplier text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v         jsonb;
  v_ref     text;
  v_event   integer;
  v_seq     smallint := 0;
  v_out     jsonb;
  v_grade   int := 0;
  v_code    text;
  v_batch   integer;
  v_result  jsonb := '[]';
  v_wast_mv bigint;
  v_supplier text := nullif(btrim(p_supplier), '');
begin
  -- same key twice (double tap / retry on bad signal): return the first run, write nothing
  if p_idempotency_key is not null then
    select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('duplicate', true, 'event_ref', v_ref);
    end if;
  end if;
  if not coalesce(p_pay_cash, true) and coalesce(p_conversion_cost_paisa, 0) > 0 and v_supplier is null then
    raise exception 'INVARIANT VIOLATION: on credit needs the supplier who is owed the crushing cost' using errcode = 'check_violation';
  end if;

  v := app.crush_run_values(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, p_conversion_cost_paisa, coalesce(p_pay_cash, true));

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'process_run', p_occurred_on,
          'Crush run: consumed ' || (p_input_qty_grams / 1000.0)::numeric(12,1) || ' kg of ' || p_input_batch_code ||
          ' → ' || ((v->>'output_grams')::bigint / 1000.0)::numeric(12,1) || ' kg graded output, ' ||
          (p_wastage_grams / 1000.0)::numeric(12,1) || ' kg wastage' ||
          coalesce(', crushing by ' || v_supplier, '') || coalesce(' — ' || nullif(btrim(p_note), ''), ''),
          case when v_supplier is not null then 'supplier' end, v_supplier, 'app', p_created_by, p_idempotency_key)
  returning event_ref, id into v_ref, v_event;

  -- 1) the salt taken out. Its value is split between the out row and the wastage row (attribution only).
  v_wast_mv := least((v->>'wastage_value_paisa')::bigint, (v->>'input_value_paisa')::bigint);
  v_seq := v_seq + 1;
  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  values (v_event, v_seq, (v->>'input_product_id')::smallint, (v->>'input_batch_id')::integer, (v->>'location_id')::integer, 'out',
          p_input_qty_grams, -((v->>'input_value_paisa')::bigint - v_wast_mv));

  -- 2) one new batch per output grade, at the computed value
  for v_out in select * from jsonb_array_elements(v->'outputs') loop
    v_grade := v_grade + 1;
    v_code := p_input_batch_code || '-G' || v_grade;
    while exists (select 1 from app.batches where batch_code = v_code) loop
      v_grade := v_grade + 1;
      v_code := p_input_batch_code || '-G' || v_grade;
    end loop;
    insert into app.batches (batch_code, product_id, location_id, opened_on, note)
    values (v_code, (select id from app.products where code = v_out->>'product_code'), (v->>'location_id')::integer, p_occurred_on,
            'Crush output from ' || p_input_batch_code || coalesce(' — ' || nullif(btrim(p_note), ''), ''))
    returning id into v_batch;
    v_seq := v_seq + 1;
    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    values (v_event, v_seq, (select id from app.products where code = v_out->>'product_code'), v_batch, (v->>'location_id')::integer, 'in',
            (v_out->>'qty_grams')::bigint, (v_out->>'value_paisa')::bigint);
    v_result := v_result || jsonb_build_array((v_out - 'form') || jsonb_build_object('batch_code', v_code));
  end loop;

  -- 3) wastage: a reporting row (kg + value attribution), not a second stock decrement
  if p_wastage_grams > 0 then
    v_seq := v_seq + 1;
    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    values (v_event, v_seq, (v->>'input_product_id')::smallint, (v->>'input_batch_id')::integer, (v->>'location_id')::integer, 'wastage',
            p_wastage_grams, -v_wast_mv);
  end if;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event, (row_number() over (order by t.ord))::smallint, a.id, (t.o->>'debit')::bigint, (t.o->>'credit')::bigint
    from jsonb_array_elements(v->'lines') with ordinality t(o, ord)
    join app.accounts a on a.code = t.o->>'account';

  return jsonb_build_object('event_ref', v_ref, 'input_batch', p_input_batch_code,
    'input_value_paisa', (v->>'input_value_paisa')::bigint, 'wastage_grams', p_wastage_grams,
    'wastage_value_paisa', (v->>'wastage_value_paisa')::bigint, 'wastage_expense_paisa', (v->>'wastage_value_paisa')::bigint,
    'outputs', v_result);
end $$;
revoke all on function app.record_process_run_impl(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text, text) from public, anon, authenticated;

create function public.record_process_run(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb,
  p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date,
  p_note text default null, p_created_by uuid default null, p_idempotency_key text default null, p_supplier text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return app.record_process_run_impl(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams,
    p_conversion_cost_paisa, p_pay_cash, p_occurred_on, p_note, app.require_user(), p_idempotency_key, p_supplier);
end $$;

-- The form's preview: the same numbers, nothing written.
create function public.crush_run_preview(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb,
  p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.require_user();
  return app.crush_run_values(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, p_conversion_cost_paisa, coalesce(p_pay_cash, true))
         - 'input_product_id' - 'input_batch_id' - 'location_id';
end $$;

revoke all on function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text, text),
  public.crush_run_preview(text, bigint, jsonb, bigint, bigint, boolean) from public, anon, authenticated, service_role;
grant execute on function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text, text),
  public.crush_run_preview(text, bigint, jsonb, bigint, bigint, boolean) to authenticated;
