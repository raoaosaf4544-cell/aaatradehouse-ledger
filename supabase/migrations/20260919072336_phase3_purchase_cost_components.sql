-- ============ record_purchase v2: + idempotency + traceable landed-cost components ============
-- Signature compatible with all existing callers; p_cost_components optional.
create or replace function public.record_purchase(
  p_supplier text,
  p_product_code text,
  p_location_code text,
  p_qty_grams bigint,
  p_landed_cost_paisa bigint,
  p_pay_cash boolean,
  p_occurred_on date,
  p_note text default null,
  p_created_by uuid default null,
  p_idempotency_key text default null,
  p_cost_components jsonb default null
) returns jsonb language plpgsql security definer set search_path = 'app' as $fn$
declare
  v_product app.products%rowtype;
  v_location app.locations%rowtype;
  v_batch_code text;
  v_batch_id integer;
  v_event_ref text;
  v_event_id integer;
  v_credit_account text;
  v_comp jsonb;
  v_comp_sum bigint := 0;
  v_comp_count integer := 0;
begin
  if p_idempotency_key is not null then
    if exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
      return jsonb_build_object('duplicate', true);
    end if;
  end if;
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

  -- optional component breakdown: must sum EXACTLY to the landed cost (no double counting)
  if p_cost_components is not null then
    if jsonb_typeof(p_cost_components) <> 'array' then
      raise exception 'INVARIANT VIOLATION: cost_components must be an array' using errcode = 'check_violation';
    end if;
    for v_comp in select * from jsonb_array_elements(p_cost_components) loop
      v_comp_count := v_comp_count + 1;
      if v_comp ->> 'component' not in ('purchase','freight_inbound','loading','other') then
        raise exception 'INVARIANT VIOLATION: unknown cost component %', v_comp ->> 'component' using errcode = 'check_violation';
      end if;
      if coalesce((v_comp ->> 'amount_paisa')::bigint, 0) <= 0 then
        raise exception 'INVARIANT VIOLATION: cost component % amount must be positive', v_comp ->> 'component' using errcode = 'check_violation';
      end if;
      v_comp_sum := v_comp_sum + (v_comp ->> 'amount_paisa')::bigint;
    end loop;
    if v_comp_sum <> p_landed_cost_paisa then
      raise exception 'INVARIANT VIOLATION: cost components sum to % but landed cost is % - they must match exactly (no double counting)',
        (v_comp_sum / 100.0)::numeric(14,2), (p_landed_cost_paisa / 100.0)::numeric(14,2) using errcode = 'check_violation';
    end if;
  end if;

  -- new batch code (sequence skips any existing codes)
  v_batch_code := 'BATCH-' || lpad(nextval('app.batch_ref_seq')::text, 3, '0');
  while exists (select 1 from app.batches where batch_code = v_batch_code) loop
    v_batch_code := 'BATCH-' || lpad(nextval('app.batch_ref_seq')::text, 3, '0');
  end loop;

  insert into app.batches (batch_code, product_id, location_id, opened_on, note)
  values (v_batch_code, v_product.id, v_location.id, p_occurred_on,
          'Purchased from ' || btrim(p_supplier) || coalesce(' - ' || nullif(btrim(p_note), ''), ''))
  returning id into v_batch_id;

  v_credit_account := case when p_pay_cash then '1000' else '2000' end;

  with ins as (
    insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by, idempotency_key)
    values (app.next_event_ref(), 'purchase', p_occurred_on,
            'Salt purchase from ' || btrim(p_supplier) || ' - ' || (p_qty_grams / 1000.0)::numeric(12,1) ||
            ' kg, landed cost ' || (p_landed_cost_paisa / 100.0)::numeric(14,2) || ' PKR, batch ' || v_batch_code,
            'supplier', btrim(p_supplier), 'app', p_created_by, p_idempotency_key)
    returning id, event_ref
  )
  select event_ref, id into v_event_ref, v_event_id from ins;

  -- balanced ledger (single statement for the statement-level balance trigger)
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event_id, x.seq, a.id, x.dr, x.cr
  from (values (1, case v_product.form when 'raw' then '1200' when 'bulk_processed' then '1210' when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end, p_landed_cost_paisa, 0::bigint),
               (2, v_credit_account, 0::bigint, p_landed_cost_paisa)) as x(seq, acc_code, dr, cr)
  join app.accounts a on a.code = x.acc_code;

  -- movement (value positive on receipt)
  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  values (v_event_id, 1, v_product.id, v_batch_id, v_location.id, 'in', p_qty_grams, p_landed_cost_paisa);

  -- traceable cost components bound to this purchase event
  if v_comp_count > 0 then
    insert into app.batch_cost_components (batch_id, component, amount_paisa, event_id, note)
    select v_batch_id, v_comp ->> 'component', (v_comp ->> 'amount_paisa')::bigint, v_event_id, v_comp ->> 'note'
    from jsonb_array_elements(p_cost_components) v_comp;
  end if;

  return jsonb_build_object('event_ref', v_event_ref, 'batch_code', v_batch_code);
end $fn$;

grant execute on function public.record_purchase(text, text, text, bigint, bigint, boolean, date, text, uuid, text, jsonb) to anon, authenticated;