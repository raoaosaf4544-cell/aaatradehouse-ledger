-- record_sale v3.2: sales row now carries the money state explicitly
-- (cash_received / advance_applied / ar), consistent with the balanced event.
create or replace function public.record_sale(
  p_party text,
  p_items jsonb,
  p_cash_received_paisa bigint default 0,
  p_customer_phone text default null,
  p_occurred_on date default current_date,
  p_note text default null,
  p_idempotency_key text default null,
  p_created_by uuid default null
) returns jsonb language plpgsql security definer set search_path = 'app' as $fn$
declare
  v_party_name text := btrim(coalesce(p_party, ''));
  v_cash bigint := coalesce(p_cash_received_paisa, 0);
  v_party app.parties%rowtype;
  v_party_created boolean := false;
  v_sale_id integer;
  v_sale_ref text;
  v_event_ref text;
  v_lines jsonb := '[]'::jsonb;
  v_item jsonb;
  v_qty_grams bigint;
  v_price bigint;
  v_line_rev bigint;
  v_revenue bigint := 0;
  v_product app.products%rowtype;
  v_adv_balance bigint := 0;
  v_apply bigint := 0;
  v_ar bigint;
  i integer;
begin
  if v_party_name = '' then
    raise exception 'INVARIANT VIOLATION: customer is required' using errcode = 'check_violation';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'INVARIANT VIOLATION: at least one sale line is required' using errcode = 'check_violation';
  end if;
  if v_cash < 0 then
    raise exception 'INVARIANT VIOLATION: cash received cannot be negative' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    if exists (select 1 from app.sales where idempotency_key = p_idempotency_key) then
      select id, sale_ref, total_revenue_paisa, cash_received_paisa, advance_applied_paisa, ar_paisa
        into v_sale_id, v_sale_ref, v_revenue, v_cash, v_apply, v_ar
      from app.sales where idempotency_key = p_idempotency_key;
      return jsonb_build_object('duplicate', true, 'sale_ref', v_sale_ref, 'revenue_paisa', v_revenue,
        'cash_paisa', v_cash, 'advance_applied_paisa', v_apply, 'ar_paisa', v_ar);
    end if;
    if exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
      return jsonb_build_object('duplicate', true);
    end if;
  end if;

  select * into v_party from app.parties where kind = 'customer' and lower(name) = lower(v_party_name);
  if not found then
    v_party_created := true;
    insert into app.parties (party_ref, name, phone, kind)
    values (app.next_party_ref(), v_party_name, nullif(btrim(coalesce(p_customer_phone, '')), ''), 'customer')
    returning * into v_party;
  end if;

  for i in 0 .. jsonb_array_length(p_items) - 1 loop
    v_item := p_items -> i;
    if v_item ? 'qty_grams' then
      v_qty_grams := round((v_item ->> 'qty_grams')::numeric)::bigint;
    else
      v_qty_grams := round((v_item ->> 'qty_kg')::numeric * 1000)::bigint;
    end if;
    v_price := coalesce((v_item ->> 'unit_price_paisa_per_kg')::bigint, (v_item ->> 'unit_price_paisa')::bigint, 0);
    if v_qty_grams is null or v_qty_grams <= 0 then
      raise exception 'INVARIANT VIOLATION: quantity must be positive (line %)', i + 1 using errcode = 'check_violation';
    end if;
    if v_price <= 0 then
      raise exception 'INVARIANT VIOLATION: unit price must be positive (line %)', i + 1 using errcode = 'check_violation';
    end if;
    select * into v_product from app.products where code = v_item ->> 'product_code';
    if not found then
      raise exception 'INVARIANT VIOLATION: unknown product code %', v_item ->> 'product_code' using errcode = 'check_violation';
    end if;
    v_line_rev := round(v_qty_grams::numeric * v_price / 1000.0)::bigint;
    v_revenue := v_revenue + v_line_rev;
    v_lines := v_lines || jsonb_build_object('line_no', i + 1, 'product_id', v_product.id,
      'product_code', v_product.code, 'qty_grams', v_qty_grams,
      'unit_price_paisa_per_kg', v_price, 'revenue_paisa', v_line_rev);
  end loop;

  select coalesce(sum(case when direction = 'received' then amount_paisa else -amount_paisa end), 0)
    into v_adv_balance
  from app.customer_advances where party_id = v_party.id;
  v_apply := least(greatest(v_adv_balance, 0), v_revenue);
  if v_cash + v_apply > v_revenue then
    raise exception 'INVARIANT VIOLATION: cash (%) plus advance application (%) exceeds invoice total (%)',
      (v_cash / 100.0)::numeric(14,2), (v_apply / 100.0)::numeric(14,2), (v_revenue / 100.0)::numeric(14,2)
      using errcode = 'check_violation';
  end if;
  v_ar := v_revenue - v_cash - v_apply;

  v_sale_ref := app.next_sale_ref();

  insert into app.sales (sale_ref, party_id, status, occurred_on, total_revenue_paisa,
                         cash_received_paisa, advance_applied_paisa, ar_paisa, idempotency_key, note, created_by)
  values (v_sale_ref, v_party.id, 'invoiced', p_occurred_on, v_revenue, v_cash, v_apply, v_ar, p_idempotency_key, p_note, p_created_by)
  returning id into v_sale_id;

  insert into app.sale_lines (sale_id, line_no, product_id, qty_grams, unit_price_paisa_per_kg, revenue_paisa)
  select v_sale_id, (l ->> 'line_no')::int, (l ->> 'product_id')::smallint, (l ->> 'qty_grams')::bigint,
         (l ->> 'unit_price_paisa_per_kg')::bigint, (l ->> 'revenue_paisa')::bigint
  from jsonb_array_elements(v_lines) l;

  -- ONE event, ONE statement: Dr cash + Dr advance applied + Dr AR = Cr revenue
  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'sale', p_occurred_on,
    'Invoice ' || v_sale_ref || ' to ' || v_party.name || ' - ' || (v_revenue / 100.0)::numeric(14,2) || ' PKR'
    || case when v_cash > 0 then ' (cash ' || (v_cash / 100.0)::numeric(14,2) || ')' else '' end
    || case when v_apply > 0 then ' (advance applied ' || (v_apply / 100.0)::numeric(14,2) || ')' else '' end
    || case when v_ar > 0 then ' (receivable ' || (v_ar / 100.0)::numeric(14,2) || ')' else '' end
    || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
    'customer', v_party.id, v_party.name, 'app', p_created_by, p_idempotency_key)
  returning event_ref into v_event_ref;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select e.id, x.seq, a.id, x.dr, x.cr
  from app.events e
  join (values
    (1, '1000', v_cash, 0::bigint),
    (2, '2200', v_apply, 0::bigint),
    (3, '1100', v_ar, 0::bigint),
    (4, '4000', 0::bigint, v_revenue)
  ) as x(seq, acc_code, dr, cr) on true
  join app.accounts a on a.code = x.acc_code
  where e.event_ref = v_event_ref and x.dr > 0 or (e.event_ref = v_event_ref and x.acc_code = '4000');

  if v_apply > 0 then
    insert into app.customer_advances (event_id, party_id, direction, amount_paisa, occurred_on, note, created_by)
    select e.id, v_party.id, 'applied', v_apply, p_occurred_on, 'Applied to invoice ' || v_sale_ref, p_created_by
    from app.events e where e.event_ref = v_event_ref;
  end if;

  return jsonb_build_object('sale_ref', v_sale_ref, 'event_ref', v_event_ref,
    'party_ref', v_party.party_ref, 'party_created', v_party_created,
    'revenue_paisa', v_revenue, 'cash_paisa', v_cash,
    'advance_applied_paisa', v_apply, 'ar_paisa', v_ar,
    'lines', v_lines);
end $fn$;

-- The derivation trigger is redundant now (money state written explicitly by the RPC)
drop trigger if exists trg_set_sale_state on app.events;
drop function if exists app.set_sale_state();