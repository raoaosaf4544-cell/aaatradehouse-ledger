-- CFO figures as database views, so the CFO (JARVIS laptop) and the Telegram bot give the SAME numbers.
-- Read-only, security_invoker, same grants as the other v_* views. No ledger table or policy change.
-- "Today" is the Asia/Karachi date.

-- Runway (months, 1 decimal) = cash on hand / operating spend over the last 30 days (today inclusive).
-- Operating spend = net debits (debit - credit) to accounts with type 'expense' AND kind 'general',
-- excluding 4100 (COGS) and 5250 (wastage). Stock and asset purchases are not expenses, so they stay out.
-- runway_months is null when spend <= 0 (cannot be computed).
create or replace view app.v_cfo_runway with (security_invoker = true) as
with p as (
  select (now() at time zone 'Asia/Karachi')::date as today
),
accts as (
  select a.id, a.code, a.name from app.accounts a
   where a.type = 'expense' and a.kind = 'general' and a.code not in ('4100', '5250')
),
spend as (
  select ac.code, ac.name, coalesce(sum(le.debit_paisa - le.credit_paisa), 0) as spend_paisa
    from accts ac
    left join app.ledger_entries le on le.account_id = ac.id
     and exists (select 1 from app.events e, p where e.id = le.event_id and e.occurred_on between p.today - 29 and p.today)
   group by ac.code, ac.name
),
cash as (
  select coalesce(sum(le.debit_paisa - le.credit_paisa), 0) as cash_paisa
    from app.ledger_entries le join app.accounts a on a.id = le.account_id and a.code = '1000'
)
select p.today                                   as as_of,
       p.today - 29                              as window_start,
       cash.cash_paisa,
       (select sum(spend_paisa) from spend)      as spend_30d_paisa,
       case when (select sum(spend_paisa) from spend) > 0
            then round(cash.cash_paisa::numeric / (select sum(spend_paisa) from spend), 1) end as runway_months,
       'runway (months) = cash on hand / operating spend of the last 30 days' as formula,
       (select array_agg(code order by code) from spend) as account_codes,
       (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'spend_paisa', spend_paisa) order by code) from spend) as spend_by_account
from p, cash;

-- Udhaar per customer (only balances > 0). Payments go to the oldest invoice first, so the part owed for more than
-- 7 days = outstanding - credit sales (sales.ar_paisa) of the last 7 days (today and the 6 days before), never below 0.
create or replace view app.v_udhaar_aging with (security_invoker = true) as
with p as (
  select (now() at time zone 'Asia/Karachi')::date as today
)
select d.party_id,
       d.customer_name,
       d.phone,
       d.outstanding_paisa,
       coalesce(r.recent_ar_paisa, 0)                                    as credit_sales_last_7d_paisa,
       greatest(d.outstanding_paisa - coalesce(r.recent_ar_paisa, 0), 0) as unpaid_over_7d_paisa,
       d.last_sale_on
  from app.v_debtors d
  left join (select s.party_id, sum(s.ar_paisa) as recent_ar_paisa
               from app.sales s, p
              where s.occurred_on between p.today - 6 and p.today
              group by s.party_id) r on r.party_id = d.party_id
 where d.outstanding_paisa > 0;

create or replace view public.v_cfo_runway with (security_invoker = true) as select * from app.v_cfo_runway;
create or replace view public.v_udhaar_aging with (security_invoker = true) as select * from app.v_udhaar_aging;

-- same grants as the other v_* views: read for signed-in users, nothing for anon
revoke all on app.v_cfo_runway, app.v_udhaar_aging, public.v_cfo_runway, public.v_udhaar_aging from public, anon, authenticated;
grant select on app.v_cfo_runway, app.v_udhaar_aging to authenticated;
grant select on public.v_cfo_runway, public.v_udhaar_aging to authenticated, service_role;
