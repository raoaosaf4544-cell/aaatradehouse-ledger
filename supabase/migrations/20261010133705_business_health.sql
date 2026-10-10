-- Business health / کاروبار کا حال (owner-approved 10 Oct 2026). Every figure on the page comes from here.
--   public.business_health(p_from, p_to): one period (p_from null = since the books started).
--   public.business_trend(): the last 6 months that have sales, for the trend bars.
-- Totals come from the ledger (sales = 4000, cost of salt sold = 4100, other income = other income accounts, costs =
-- expense accounts), so net profit always equals the books' profit and loss. Breakdowns by product / customer come
-- from the sale tables; whatever the ledger has that no sale line explains (corrections) is shown as "adjustments".
-- Running costs leave out entries ticked one-time (a correction counts as one-time when its original was ticked).
-- Goats (1450) are an asset outside salt profit: shown only as a note.

-- the sale lines of a period with what their salt cost (dispatch allocations)
create function app.business_sale_lines(p_from date, p_to date)
returns table (sale_ref text, occurred_on date, party_id integer, customer text, code text, product text, qty_grams bigint, revenue bigint, cogs bigint)
language sql stable security definer set search_path = '' as $$
  select s.sale_ref, s.occurred_on, s.party_id, p.name, pr.code, pr.name, x.qty_grams, x.revenue_paisa,
         (select coalesce(sum(da.cogs_paisa), 0) from app.dispatch_allocations da where da.sale_line_id = x.id)::bigint
    from app.sales s join app.sale_lines x on x.sale_id = s.id join app.products pr on pr.id = x.product_id
    left join app.parties p on p.id = s.party_id
   where s.occurred_on between p_from and p_to
$$;

create function app.business_numbers(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_today date := (now() at time zone 'Asia/Karachi')::date;
  v_start date := (select min(occurred_on) from app.events);
  v_from  date := greatest(coalesce(p_from, v_start), v_start);
  v_to    date := least(coalesce(p_to, v_today), v_today);
  v_days  int;
  pl record; sl record; st record; bal record;
  v_gp bigint; v_running bigint; v_net bigint; v_kg_rate numeric;
begin
  v_days := greatest(v_to - v_from + 1, 0);

  -- profit and loss for the period, straight from the ledger
  with l as (
    select a.code, a.type, le.debit_paisa - le.credit_paisa as net,
           coalesce((select r.one_time from app.events r where e.source = 'correction' and r.event_ref = e.source_ref), e.one_time, false) as one_time
      from app.ledger_entries le join app.accounts a on a.id = le.account_id join app.events e on e.id = le.event_id
     where e.occurred_on between v_from and v_to and a.type in ('income', 'expense'))
  select coalesce(-sum(net) filter (where code = '4000'), 0)::bigint as sales,
         coalesce(sum(net) filter (where code = '4100'), 0)::bigint as cogs,
         coalesce(-sum(net) filter (where type = 'income' and code <> '4000'), 0)::bigint as other_income,
         coalesce(sum(net) filter (where type = 'expense' and code in ('5410', '5420', '5430', '5440', '5490') and not one_time), 0)::bigint as plant,
         coalesce(sum(net) filter (where type = 'expense' and code in ('5410', '5420', '5430', '5440') and not one_time), 0)::bigint as plant_bills,
         coalesce(-sum(net) filter (where code = '5490' and not one_time), 0)::bigint as plant_charged,
         coalesce(sum(net) filter (where type = 'expense' and code = '5000' and not one_time), 0)::bigint as labour,
         coalesce(sum(net) filter (where type = 'expense' and code in ('5200', '5300', '5600') and not one_time), 0)::bigint as transport,
         coalesce(sum(net) filter (where type = 'expense' and code = '5400' and not one_time), 0)::bigint as packing,
         coalesce(sum(net) filter (where type = 'expense' and code in ('5100', '5700', '5800', '5900') and not one_time), 0)::bigint as shop_admin,
         coalesce(sum(net) filter (where type = 'expense' and code not in ('4100', '5410', '5420', '5430', '5440', '5490', '5000', '5200', '5300', '5600', '5400', '5100', '5700', '5800', '5900') and not one_time), 0)::bigint as other_costs,
         coalesce(sum(net) filter (where type = 'expense' and code <> '4100' and one_time), 0)::bigint as one_time,
         coalesce(-sum(net), 0)::bigint as ledger_profit
    into pl from l;

  v_gp := pl.sales - pl.cogs;
  v_running := pl.plant + pl.labour + pl.transport + pl.packing + pl.shop_admin + pl.other_costs;
  v_net := v_gp + pl.other_income - v_running - pl.one_time;

  select coalesce(sum(qty_grams), 0)::bigint as grams, coalesce(sum(revenue), 0)::bigint as revenue, coalesce(sum(cogs), 0)::bigint as cogs
    into sl from app.business_sale_lines(v_from, v_to);

  -- stock now (batch records), rock vs crushed salt
  select coalesce(sum(case when pr.form = 'raw' then case m.direction when 'in' then m.qty_grams when 'out' then -m.qty_grams else 0 end end), 0)::bigint as rock_g,
         coalesce(sum(case when pr.form = 'raw' then m.value_paisa end), 0)::bigint as rock_v,
         coalesce(sum(case when pr.form = 'bulk_processed' then case m.direction when 'in' then m.qty_grams when 'out' then -m.qty_grams else 0 end end), 0)::bigint as crushed_g,
         coalesce(sum(case when pr.form = 'bulk_processed' then m.value_paisa end), 0)::bigint as crushed_v
    into st from app.movements m join app.products pr on pr.id = m.product_id;

  -- balances now (capital: at the end of the period)
  select coalesce(sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '1000'), 0)::bigint as cash,
         coalesce(sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '1050'), 0)::bigint as bank,
         coalesce(sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '1100'), 0)::bigint as udhaar,
         coalesce(-sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '2000'), 0)::bigint as suppliers,
         coalesce(-sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '2100'), 0)::bigint as wages,
         coalesce(sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '1320'), 0)::bigint as advances,
         coalesce(sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '1450'), 0)::bigint as goats,
         coalesce(-sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '3000' and e.occurred_on <= v_to), 0)::bigint as capital,
         coalesce(sum(le.debit_paisa - le.credit_paisa) filter (where a.code = '3100' and e.occurred_on between v_from and v_to), 0)::bigint as drawings
    into bal from app.ledger_entries le join app.accounts a on a.id = le.account_id join app.events e on e.id = le.event_id;

  v_kg_rate := case when v_days > 0 and sl.grams > 0 then sl.grams / 1000.0 / v_days end;

  return jsonb_build_object(
    'from', v_from, 'to', v_to, 'days', v_days,
    'sales', jsonb_build_object(
      'total_paisa', pl.sales, 'grams', sl.grams, 'bags', round(sl.grams / 50000.0, 1),
      'cash_paisa', (select coalesce(sum(s.cash_received_paisa), 0) from app.sales s where s.occurred_on between v_from and v_to),
      'udhaar_paisa', (select coalesce(sum(s.ar_paisa), 0) from app.sales s where s.occurred_on between v_from and v_to),
      'advance_paisa', (select coalesce(sum(s.advance_applied_paisa), 0) from app.sales s where s.occurred_on between v_from and v_to),
      'adjustments_paisa', pl.sales - sl.revenue,
      'by_product', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', product, 'grams', g, 'revenue_paisa', rev, 'cogs_paisa', c,
                                                                   'profit_paisa', rev - c) order by rev desc), '[]')
                       from (select code, product, sum(qty_grams) g, sum(revenue) rev, sum(cogs) c from app.business_sale_lines(v_from, v_to) group by code, product) t)),
    'gross', jsonb_build_object(
      'profit_paisa', v_gp, 'cogs_paisa', pl.cogs,
      'cogs_adjustments_paisa', pl.cogs - sl.cogs,
      'margin_pct', case when pl.sales > 0 then round(v_gp * 100.0 / pl.sales, 1) end,
      'per_kg_paisa', case when sl.grams > 0 then round(v_gp * 1000.0 / sl.grams) end,
      'per_bag_paisa', case when sl.grams > 0 then round(v_gp * 50000.0 / sl.grams) end,
      'customers', (select coalesce(jsonb_agg(jsonb_build_object('name', customer, 'revenue_paisa', rev, 'profit_paisa', rev - c, 'grams', g) order by rev - c desc), '[]')
                      from (select coalesce(customer, 'Cash customer') customer, sum(revenue) rev, sum(cogs) c, sum(qty_grams) g from app.business_sale_lines(v_from, v_to) group by 1) t),
      'below_cost', (select coalesce(jsonb_agg(jsonb_build_object('sale_ref', sale_ref, 'date', occurred_on, 'customer', coalesce(customer, 'Cash customer'), 'product', product,
                                                                   'grams', qty_grams, 'revenue_paisa', revenue, 'cogs_paisa', cogs) order by occurred_on), '[]')
                       from app.business_sale_lines(v_from, v_to) where cogs > revenue)),
    'costs', jsonb_build_object(
      'plant_paisa', pl.plant, 'plant_bills_paisa', pl.plant_bills, 'plant_charged_paisa', pl.plant_charged,
      'labour_paisa', pl.labour, 'transport_paisa', pl.transport, 'packing_paisa', pl.packing, 'shop_admin_paisa', pl.shop_admin,
      'other_paisa', pl.other_costs, 'running_paisa', v_running, 'one_time_paisa', pl.one_time),
    'other_income_paisa', pl.other_income,
    'net_profit_paisa', v_net,
    'ledger_profit_paisa', pl.ledger_profit,
    'break_even', jsonb_build_object(
      'bags_needed', case when sl.grams > 0 and v_gp > 0 then ceil(v_running / (v_gp * 50000.0 / sl.grams)) end,
      'bags_sold', round(sl.grams / 50000.0, 1),
      'why_not', case when sl.grams = 0 then 'no salt sold in this period' when v_gp <= 0 then 'no gross profit per bag in this period' end),
    'cash', jsonb_build_object(
      'cash_paisa', bal.cash, 'bank_paisa', bal.bank, 'udhaar_paisa', bal.udhaar, 'suppliers_paisa', bal.suppliers, 'wages_paisa', bal.wages,
      'advances_paisa', bal.advances, 'after_all_paisa', bal.cash + bal.bank + bal.udhaar - bal.suppliers - bal.wages,
      'debtors', (with d as (
                    select e.party_id, e.occurred_on, le.debit_paisa dr, le.credit_paisa cr
                      from app.ledger_entries le join app.accounts a on a.id = le.account_id and a.code = '1100'
                      join app.events e on e.id = le.event_id where e.party_id is not null),
                  paid as (select party_id, sum(cr) cr from d group by 1),
                  run as (select d.party_id, d.occurred_on, d.dr, sum(d.dr) over (partition by d.party_id order by d.occurred_on, d.dr rows unbounded preceding) cum from d where d.dr > 0),
                  oldest as (select r.party_id, min(r.occurred_on) since from run r join paid p on p.party_id = r.party_id where r.cum > p.cr group by 1)
                  select coalesce(jsonb_agg(jsonb_build_object('name', v.customer_name, 'owed_paisa', v.outstanding_paisa, 'unpaid_since', o.since,
                                                               'days', v_today - o.since) order by v_today - o.since desc nulls last), '[]')
                    from app.v_debtors v left join oldest o on o.party_id = v.party_id where v.outstanding_paisa > 0)),
    'ghar', jsonb_build_object('drawings_paisa', bal.drawings, 'more_than_profit', bal.drawings > v_net),
    'return', jsonb_build_object('capital_paisa', bal.capital,
      'pct', case when bal.capital > 0 then round(v_net * 100.0 / bal.capital, 1) end),
    'stock', jsonb_build_object('rock_grams', st.rock_g, 'rock_paisa', st.rock_v, 'crushed_grams', st.crushed_g, 'crushed_paisa', st.crushed_v,
      'kg_sold_per_day', round(v_kg_rate, 1),
      'days_left', case when v_kg_rate > 0 then floor((st.rock_g + st.crushed_g) / 1000.0 / v_kg_rate) end),
    'other_activities', jsonb_build_object('goats_paisa', bal.goats));
end $$;

create function public.business_health(p_from date default null, p_to date default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.is_allowed_user() then
    raise exception 'Not allowed' using errcode = 'insufficient_privilege';
  end if;
  return app.business_numbers(p_from, p_to);
end $$;

create function public.business_trend() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb := '[]'; m date; n jsonb;
begin
  if not app.is_allowed_user() then
    raise exception 'Not allowed' using errcode = 'insufficient_privilege';
  end if;
  for m in select distinct date_trunc('month', e.occurred_on)::date from app.events e
             join app.ledger_entries le on le.event_id = e.id join app.accounts a on a.id = le.account_id and a.code = '4000'
            order by 1 desc limit 6 loop
    n := app.business_numbers(m, (m + interval '1 month' - interval '1 day')::date);
    v := jsonb_build_object('month', m, 'sales_paisa', n->'sales'->'total_paisa', 'gross_profit_paisa', n->'gross'->'profit_paisa',
                            'net_profit_paisa', n->'net_profit_paisa') || v;
  end loop;
  return (select coalesce(jsonb_agg(x order by x->>'month'), '[]') from jsonb_array_elements(v) x);
end $$;

revoke all on function app.business_numbers(date, date), app.business_sale_lines(date, date) from public, anon, authenticated;
revoke all on function public.business_health(date, date), public.business_trend() from public, anon;
grant execute on function public.business_health(date, date), public.business_trend() to authenticated, service_role;
