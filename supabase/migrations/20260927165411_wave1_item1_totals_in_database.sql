-- Wave 1 item 1: totals computed in the database, so no screen downloads every row (the API returns at
-- most 1000 rows per request). Lists are paged by the app; these views give the exact totals.
-- Read-only views, security_invoker: the caller's RLS (allow-listed users only) applies.

-- Every ledger line with its entry's date/ref/description: one paged query per account.
create or replace view app.v_account_lines with (security_invoker = true) as
select a.code as account_code, le.event_id, le.entry_seq, le.debit_paisa, le.credit_paisa,
       e.occurred_on, e.event_ref, e.description
from app.ledger_entries le
join app.accounts a on a.id = le.account_id
join app.events e on e.id = le.event_id;

-- Per-account totals (lines, debits, credits) without downloading the lines.
create or replace view app.v_account_totals with (security_invoker = true) as
select a.code, count(le.id) as line_count,
       coalesce(sum(le.debit_paisa), 0) as debit_paisa, coalesce(sum(le.credit_paisa), 0) as credit_paisa
from app.accounts a
left join app.ledger_entries le on le.account_id = a.id
group by a.code;

-- Sales totals over ALL invoices. Margin uses only fully dispatched invoices (their cost is known).
create or replace view app.v_sales_totals with (security_invoker = true) as
select count(*) as invoices,
       coalesce(sum(total_revenue_paisa), 0) as revenue_paisa,
       coalesce(sum(cogs_paisa), 0) as cogs_paisa,
       coalesce(sum(total_revenue_paisa) filter (where dispatched_grams >= invoiced_grams), 0) as dispatched_revenue_paisa,
       coalesce(sum(cogs_paisa) filter (where dispatched_grams >= invoiced_grams), 0) as dispatched_cogs_paisa,
       count(*) filter (where dispatched_grams < invoiced_grams) as not_fully_dispatched
from app.v_sales;

-- Real integrity checks for the Dashboard (one row):
--  * debits = credits over the whole ledger
--  * stock value in the ledger = stock value of the batch movements (both directions, per account)
--  * cash never below zero on any day (running balance by date)
create or replace view app.v_ledger_health with (security_invoker = true) as
with inv_accounts(code) as (values ('1200'), ('1210'), ('1220'), ('1230')),
ledger_inv as (
  select a.code, coalesce(sum(le.debit_paisa - le.credit_paisa), 0) as v
  from inv_accounts i join app.accounts a on a.code = i.code
  left join app.ledger_entries le on le.account_id = a.id
  group by a.code),
movement_inv as (
  select case p.form when 'raw' then '1200' when 'bulk_processed' then '1210'
                     when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end as code,
         sum(m.value_paisa) as v
  from app.movements m join app.products p on p.id = m.product_id
  group by 1),
cash_days as (
  select sum(net) over (order by d) as bal
  from (select e.occurred_on as d, sum(le.debit_paisa - le.credit_paisa) as net
        from app.ledger_entries le
        join app.accounts a on a.id = le.account_id and a.code = '1000'
        join app.events e on e.id = le.event_id
        group by e.occurred_on) x)
select (select coalesce(sum(debit_paisa), 0) from app.ledger_entries) as total_debit_paisa,
       (select coalesce(sum(credit_paisa), 0) from app.ledger_entries) as total_credit_paisa,
       (select coalesce(sum(v), 0) from ledger_inv) as stock_ledger_paisa,
       (select coalesce(sum(v), 0) from movement_inv) as stock_movements_paisa,
       (select count(*) from (select code from ledger_inv union select code from movement_inv) c
         where coalesce((select v from ledger_inv l where l.code = c.code), 0)
            <> coalesce((select v from movement_inv m where m.code = c.code), 0)) as stock_mismatched_accounts,
       (select count(*) from cash_days where bal < 0) as negative_cash_days,
       (select min(bal) from cash_days) as lowest_cash_paisa;

create or replace view public.v_account_lines with (security_invoker = true) as select * from app.v_account_lines;
create or replace view public.v_account_totals with (security_invoker = true) as select * from app.v_account_totals;
create or replace view public.v_sales_totals with (security_invoker = true) as select * from app.v_sales_totals;
create or replace view public.v_ledger_health with (security_invoker = true) as select * from app.v_ledger_health;

-- New objects inherit broad default privileges: read-only for signed-in users, nothing for anon.
revoke all on app.v_account_lines, app.v_account_totals, app.v_sales_totals, app.v_ledger_health from public, anon, authenticated;
revoke all on public.v_account_lines, public.v_account_totals, public.v_sales_totals, public.v_ledger_health from public, anon, authenticated;
grant select on app.v_account_lines, app.v_account_totals, app.v_sales_totals, app.v_ledger_health to authenticated;
grant select on public.v_account_lines, public.v_account_totals, public.v_sales_totals, public.v_ledger_health to authenticated, service_role;
