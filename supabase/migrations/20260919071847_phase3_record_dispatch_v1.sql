-- ============ record_dispatch v1: the ONLY inventory deduction point ============
-- Lines: [{product_code, location_code, qty_kg | qty_grams,
--          allocations?: [{batch_code, qty_kg | qty_grams, override_reason?}]}]
-- FIFO = oldest OPEN batch of the EXACT product at the EXACT location.
-- Manual mode: allocations must cover the line exactly; reason required.
create or replace function app.inventory_account(p_product_id smallint) returns text
language sql stable set search_path = 'app' as $fn$
  select case form when 'raw' then '1200' when 'bulk_processed' then '1210'
                   when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end
  from app.products where id = p_product_id
$fn$;

create or replace function public.record_dispatch(
  p_sale_ref text,
  p_lines jsonb,
  p_occurred_on date default current_date,
  p_note text default null,
  p_idempotency_key text default null,
  p_created_by uuid default null
) returns jsonb language plpgsql security definer set search_path = 'app' as $fn$
declare
  v_sale app.sales%rowtype;
  v_party app.parties%rowtype;
  v_dispatch_id integer;
  v_dispatch_ref text;
  v_event_ref text;
  v_line jsonb;
  v_alloc jsonb;
  v_product app.products%rowtype;
  v_location smallint;
  v_qty_grams bigint;
  v_remaining bigint;
  v_sale_line app.sale_lines%rowtype;
  v_mode text;
  v_allocs jsonb := '[]'::jsonb;
  v_pool record;
  v_need bigint;
  v_batch app.batches%rowtype;
  v_onhand bigint;
  v_cost bigint;
  v_cogs bigint;
  v_total_cogs bigint := 0;
  v_line_no integer;
  v_seq integer := 0;
  v_revenue bigint;
  i integer;
  j integer;
  v_reason text;
  v_manual_sum bigint;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'INVARIANT VIOLATION: at least one dispatch line is required' using errcode = 'check_violation';
  end if;

  select * into v_sale from app.sales where sale_ref = btrim(coalesce(p_sale_ref, ''));
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown sale %', p_sale_ref using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    if exists (select 1 from app.dispatches where idempotency_key = p_idempotency_key) then
      select id, dispatch_ref, total_cogs_paisa into v_dispatch_id, v_dispatch_ref, v_total_cogs
      from app.dispatches where idempotency_key = p_idempotency_key;
      return jsonb_build_object('duplicate', true, 'dispatch_ref', v_dispatch_ref, 'cogs_paisa', v_total_cogs);
    end if;
    if exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
      return jsonb_build_object('duplicate', true);
    end if;
  end if;

  select * into v_party from app.parties where id = v_sale.party_id;
  v_revenue := v_sale.total_revenue_paisa;

  begin
    -- serializable: two concurrent dispatches cannot both pass the stock checks
    set transaction_isolation = 'serializable';

    for i in 0 .. jsonb_array_length(p_lines) - 1 loop
      v_line := p_lines -> i;
      v_line_no := i + 1;
      select * into v_product from app.products where code = v_line ->> 'product_code';
      if not found then
        raise exception 'INVARIANT VIOLATION: unknown product code % (line %)', v_line ->> 'product_code', v_line_no using errcode = 'check_violation';
      end if;
      select * into v_sale_line from app.sale_lines
      where sale_id = v_sale.id and product_id = v_product.id
      order by line_no limit 1;
      if not found then
        raise exception 'INVARIANT VIOLATION: product % is not on invoice % (line %)', v_product.code, v_sale.sale_ref, v_line_no using errcode = 'check_violation';
      end if;
      v_remaining := v_sale_line.qty_grams - v_sale_line.dispatched_grams;
      if v_line ? 'qty_grams' then
        v_qty_grams := round((v_line ->> 'qty_grams')::numeric)::bigint;
      else
        v_qty_grams := round((v_line ->> 'qty_kg')::numeric * 1000)::bigint;
      end if;
      if v_qty_grams is null or v_qty_grams <= 0 then
        raise exception 'INVARIANT VIOLATION: dispatch quantity must be positive (line %)', v_line_no using errcode = 'check_violation';
      end if;
      if v_qty_grams > v_remaining then
        raise exception 'INVARIANT VIOLATION: line % requests % kg but invoice % has only % kg left to dispatch for %',
          v_line_no, (v_qty_grams / 1000.0)::numeric(12,1), v_sale.sale_ref, (v_remaining / 1000.0)::numeric(12,1), v_product.code
          using errcode = 'check_violation';
      end if;
      if v_line ->> 'location_code' is null or btrim(v_line ->> 'location_code') = '' then
        raise exception 'INVARIANT VIOLATION: dispatch location is required (line %) - stock at one location is never available at another', v_line_no using errcode = 'check_violation';
      end if;
      select id into v_location from app.locations where code = v_line ->> 'location_code';
      if not found then
        raise exception 'INVARIANT VIOLATION: unknown location % (line %)', v_line ->> 'location_code', v_line_no using errcode = 'check_violation';
      end if;

      if v_line ? 'allocations' and jsonb_array_length(v_line -> 'allocations') > 0 then
        -- MANUAL mode: must cover the line exactly
        v_mode := 'manual';
        v_reason := btrim(coalesce(v_line ->> 'override_reason', ''));
        if v_reason = '' then
          raise exception 'INVARIANT VIOLATION: manual batch selection requires an override reason (line %)', v_line_no using errcode = 'check_violation';
        end if;
        v_manual_sum := 0;
        for j in 0 .. jsonb_array_length(v_line -> 'allocations') - 1 loop
          v_alloc := v_line -> 'allocations' -> j;
          select * into v_batch from app.batches where batch_code = v_alloc ->> 'batch_code';
          if not found then
            raise exception 'INVARIANT VIOLATION: unknown batch % (line %)', v_alloc ->> 'batch_code', v_line_no using errcode = 'check_violation';
          end if;
          if v_batch.product_id <> v_product.id then
            raise exception 'INVARIANT VIOLATION: batch % holds a different product, not % - incompatible substitution rejected (line %)',
              v_batch.batch_code, v_product.code, v_line_no using errcode = 'check_violation';
          end if;
          if v_batch.location_id <> v_location then
            raise exception 'INVARIANT VIOLATION: batch % is at another location - it cannot serve a dispatch from % (line %)',
              v_batch.batch_code, (v_line ->> 'location_code'), v_line_no using errcode = 'check_violation';
          end if;
          if v_batch.status <> 'open' then
            raise exception 'INVARIANT VIOLATION: batch % is % and cannot be dispatched (line %)', v_batch.batch_code, v_batch.status, v_line_no using errcode = 'check_violation';
          end if;
          if v_alloc ? 'qty_grams' then
            v_need := round((v_alloc ->> 'qty_grams')::numeric)::bigint;
          else
            v_need := round((v_alloc ->> 'qty_kg')::numeric * 1000)::bigint;
          end if;
          if v_need is null or v_need <= 0 then
            raise exception 'INVARIANT VIOLATION: allocation quantity must be positive (line %)', v_line_no using errcode = 'check_violation';
          end if;
          select coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0)
            into v_onhand from app.movements m where m.batch_id = v_batch.id;
          if v_need > v_onhand then
            raise exception 'INVARIANT VIOLATION: batch % has only % kg on hand, allocation requests % kg (line %)',
              v_batch.batch_code, (v_onhand / 1000.0)::numeric(12,1), (v_need / 1000.0)::numeric(12,1), v_line_no using errcode = 'check_violation';
          end if;
          v_manual_sum := v_manual_sum + v_need;
          v_cost := app.batch_unit_cost_paisa_per_kg(v_batch.id);
          v_cogs := round(v_need::numeric * v_cost / 1000.0)::bigint;
          v_seq := v_seq + 1;
          v_allocs := v_allocs || jsonb_build_object('sale_line_id', v_sale_line.id, 'product_id', v_product.id,
            'batch_id', v_batch.id, 'batch_code', v_batch.batch_code, 'qty_grams', v_need,
            'unit_cost_ppk', v_cost, 'cogs_paisa', v_cogs, 'mode', 'manual', 'reason', v_reason);
        end loop;
        if v_manual_sum <> v_qty_grams then
          raise exception 'INVARIANT VIOLATION: manual allocations (%) must exactly cover the line quantity (line %)',
            (v_manual_sum / 1000.0)::numeric(12,1), v_line_no using errcode = 'check_violation';
        end if;
      else
        -- FIFO mode: oldest eligible batch first, continuing into the next
        v_mode := 'fifo';
        v_need := v_qty_grams;
        for v_pool in
          select batch_id, batch_code, onhand_grams, unit_cost_ppk from app.fifo_pool(v_product.id, v_location)
        loop
          exit when v_need <= 0;
          if v_pool.onhand_grams > 0 then
            v_qty_grams := least(v_need, v_pool.onhand_grams);
            v_cogs := round(v_qty_grams::numeric * v_pool.unit_cost_ppk / 1000.0)::bigint;
            v_seq := v_seq + 1;
            v_allocs := v_allocs || jsonb_build_object('sale_line_id', v_sale_line.id, 'product_id', v_product.id,
              'batch_id', v_pool.batch_id, 'batch_code', v_pool.batch_code, 'qty_grams', v_qty_grams,
              'unit_cost_ppk', v_pool.unit_cost_ppk, 'cogs_paisa', v_cogs, 'mode', 'fifo', 'reason', null);
            v_need := v_need - v_qty_grams;
          end if;
        end loop;
        if v_need > 0 then
          raise exception 'INVARIANT VIOLATION: insufficient eligible stock of % at % - need % kg more, nothing compatible left (FIFO pool exhausted)',
            v_product.code, (v_line ->> 'location_code'), (v_need / 1000.0)::numeric(12,1) using errcode = 'check_violation';
        end if;
      end if;
    end loop;

    if v_seq = 0 then
      raise exception 'INVARIANT VIOLATION: dispatch has no allocations' using errcode = 'check_violation';
    end if;

    select coalesce(sum((a ->> 'cogs_paisa')::bigint), 0) into v_total_cogs from jsonb_array_elements(v_allocs) a;

    insert into app.dispatches (dispatch_ref, sale_id, occurred_on, total_cogs_paisa, idempotency_key, note, created_by)
    values (app.next_dispatch_ref(), v_sale.id, p_occurred_on, v_total_cogs, p_idempotency_key, p_note, p_created_by)
    returning id, dispatch_ref into v_dispatch_id, v_dispatch_ref;

    insert into app.dispatch_allocations (dispatch_id, sale_line_id, batch_id, qty_grams, unit_cost_paisa_per_kg, cogs_paisa, allocation_mode, override_reason)
    select v_dispatch_id, (a ->> 'sale_line_id')::bigint, (a ->> 'batch_id')::integer, (a ->> 'qty_grams')::bigint,
           (a ->> 'unit_cost_ppk')::bigint, (a ->> 'cogs_paisa')::bigint, a ->> 'mode', a ->> 'reason'
    from jsonb_array_elements(v_allocs) a;

    -- COGS event: debits + per-account inventory credits, ALL in ONE statement (balance trigger)
    insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
    values (app.next_event_ref(), 'sale_cogs', p_occurred_on,
      'Dispatch ' || v_dispatch_ref || ' against invoice ' || v_sale.sale_ref || ' to ' || v_party.name ||
      ' - COGS ' || (v_total_cogs / 100.0)::numeric(14,2) || ' PKR at exact FIFO batch cost'
      || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
      'customer', v_party.id, v_party.name, 'app', p_created_by, p_idempotency_key)
    returning event_ref into v_event_ref;

    insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
    select e.id, x.seq, a.id, x.amt, 0
    from app.events e
    join (select 1 as seq, '4100' as acc, v_total_cogs as amt
          union all
          select 100 + row_number() over (order by acc), acc, cogs
          from (select app.inventory_account((a ->> 'product_id')::smallint) as acc, sum((a ->> 'cogs_paisa')::bigint) as cogs
                from jsonb_array_elements(v_allocs) a group by 1) c) x on true
    join app.accounts a on a.code = x.acc
    where e.event_ref = v_event_ref;

    -- movements: one 'out' row per allocation (negative value = book value relief), ONE statement
    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    select e.id, (a ->> 'sale_line_id')::int * 100 + row_number() over (partition by a ->> 'sale_line_id' order by a ->> 'batch_code'),
           (a ->> 'product_id')::smallint, (a ->> 'batch_id')::integer, b.location_id, 'out',
           (a ->> 'qty_grams')::bigint, -1 * (a ->> 'cogs_paisa')::bigint
    from app.events e
    join jsonb_array_elements(v_allocs) a on true
    join app.batches b on b.id = (a ->> 'batch_id')::integer
    where e.event_ref = v_event_ref;

    update app.sale_lines sl set dispatched_grams = sl.dispatched_grams + x.q
    from (select (a ->> 'sale_line_id')::bigint as slid, sum((a ->> 'qty_grams')::bigint) as q
          from jsonb_array_elements(v_allocs) a group by 1) x
    where sl.id = x.slid;

    update app.sales set status = case when not exists (
      select 1 from app.sale_lines sl where sl.sale_id = v_sale.id and sl.dispatched_grams < sl.qty_grams
    ) then 'dispatched' else 'invoiced' end where id = v_sale.id;

    -- close batches emptied by this dispatch
    update app.batches b set status = 'closed', closed_on = p_occurred_on
    where b.id in (select distinct (a ->> 'batch_id')::integer from jsonb_array_elements(v_allocs) a)
      and 0 = (select coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0)
               from app.movements m where m.batch_id = b.id);

    return jsonb_build_object('dispatch_ref', v_dispatch_ref, 'sale_ref', v_sale.sale_ref,
      'cogs_paisa', v_total_cogs, 'revenue_paisa', v_revenue,
      'gross_profit_paisa', v_revenue - v_total_cogs,
      'allocations', v_allocs);
  exception
    when serialization_failure or deadlock_detected then
      raise exception 'CONCURRENCY: another dispatch changed the same stock - nothing was saved, please retry'
        using errcode = 'serialization_failure';
  end;
end $fn$;

-- Suggested selling price from the FIFO cost basis (manual override always wins)
create or replace function public.suggest_sale_price(
  p_product_code text,
  p_location_code text,
  p_target_margin_pct numeric default 15
) returns jsonb language plpgsql stable security definer set search_path = 'app' as $fn$
declare
  v_pid smallint; v_lid smallint;
  r record;
  v_qty bigint := 0; v_val numeric := 0;
  v_cost_ppk bigint;
begin
  select id into v_pid from app.products where code = p_product_code;
  if not found then raise exception 'INVARIANT VIOLATION: unknown product %', p_product_code using errcode = 'check_violation'; end if;
  select id into v_lid from app.locations where code = p_location_code;
  if not found then raise exception 'INVARIANT VIOLATION: unknown location %', p_location_code using errcode = 'check_violation'; end if;
  for r in select * from app.fifo_pool(v_pid, v_lid) loop
    v_qty := v_qty + r.onhand_grams;
    v_val := v_val + r.onhand_grams * r.unit_cost_ppk;
  end loop;
  if v_qty <= 0 then
    return jsonb_build_object('available', false);
  end if;
  v_cost_ppk := round((v_val / v_qty))::bigint;
  return jsonb_build_object('available', true, 'fifo_cost_paisa_per_kg', v_cost_ppk,
    'suggested_price_paisa_per_kg', round(v_cost_ppk * (100 + p_target_margin_pct) / 100.0),
    'available_grams', v_qty, 'target_margin_pct', p_target_margin_pct);
end $fn$;

-- Reporting views
create or replace view app.v_batch_costs as
select b.id as batch_id, b.batch_code, p.code as product_code, p.name as product_name,
       l.code as location_code, l.name as location_name, b.status, b.opened_on, b.closed_on,
       coalesce(sum(case when c.component = 'purchase' then c.amount_paisa end), 0) as purchase_paisa,
       coalesce(sum(case when c.component = 'freight_inbound' then c.amount_paisa end), 0) as freight_inbound_paisa,
       coalesce(sum(case when c.component = 'loading' then c.amount_paisa end), 0) as loading_paisa,
       coalesce(sum(case when c.component = 'other' then c.amount_paisa end), 0) as other_paisa,
       coalesce(sum(c.amount_paisa), 0) as landed_cost_paisa,
       mv.opening_grams as acquired_grams,
       case when mv.opening_grams > 0 then round(coalesce(sum(c.amount_paisa), 0)::numeric / (mv.opening_grams / 1000.0)) else 0 end as initial_cost_ppk
from app.batches b
join app.products p on p.id = b.product_id
join app.locations l on l.id = b.location_id
left join app.batch_cost_components c on c.batch_id = b.id
left join (select batch_id, sum(qty_grams) as opening_grams from app.movements where direction = 'in' group by batch_id) mv on mv.batch_id = b.id
group by b.id, p.code, p.name, l.code, l.name, mv.opening_grams;

create or replace view app.v_dispatch_allocations as
select d.dispatch_ref, d.occurred_on, s.sale_ref, pt.name as customer_name,
       p.code as product_code, p.name as product_name,
       b.batch_code, da.qty_grams, da.unit_cost_paisa_per_kg, da.cogs_paisa,
       da.allocation_mode, da.override_reason, d.total_cogs_paisa
from app.dispatch_allocations da
join app.dispatches d on d.id = da.dispatch_id
join app.sales s on s.id = d.sale_id
join app.parties pt on pt.id = s.party_id
join app.batches b on b.id = da.batch_id
join app.products p on p.id = b.product_id;

create or replace view app.v_sales as
select s.id, s.sale_ref, s.occurred_on, pt.name as customer_name, pt.party_ref,
       s.status, s.currency, s.fx_rate, s.total_revenue_paisa, s.cash_received_paisa,
       s.advance_applied_paisa, s.ar_paisa,
       coalesce(d.total_cogs_paisa, 0) as cogs_paisa,
       s.total_revenue_paisa - coalesce(d.total_cogs_paisa, 0) as gross_profit_paisa,
       case when coalesce(d.total_cogs_paisa, 0) > 0
            then round(100.0 * (s.total_revenue_paisa - d.total_cogs_paisa) / d.total_cogs_paisa, 2) end as gross_margin_pct,
       coalesce(dq.dispatched_grams, 0) as dispatched_grams,
       sl.qty_grams as invoiced_grams
from app.sales s
join app.parties pt on pt.id = s.party_id
left join (select sale_id, sum(total_cogs_paisa) as total_cogs_paisa
           from app.dispatches group by sale_id) d on d.sale_id = s.id
left join (select d2.sale_id, sum(da.qty_grams) as dispatched_grams
           from app.dispatch_allocations da join app.dispatches d2 on d2.id = da.dispatch_id
           group by d2.sale_id) dq on dq.sale_id = s.id
left join (select sale_id, sum(qty_grams) as qty_grams from app.sale_lines group by sale_id) sl on sl.sale_id = s.id;

grant execute on function public.record_dispatch(text, jsonb, date, text, text, uuid) to anon, authenticated;
grant execute on function public.suggest_sale_price(text, text, numeric) to anon, authenticated;
grant select on app.v_batch_costs, app.v_dispatch_allocations, app.v_sales to anon, authenticated;