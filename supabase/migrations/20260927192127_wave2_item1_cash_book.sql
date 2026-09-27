-- Wave 2 item 1: cash book (read-only). Every line on 1000 Cash on Hand with its running balance, and one row per
-- day with opening / money in / money out / closing, so the day can be ticked against the paper roznamcha.
-- The running balance is computed over ALL cash lines before any filter (no PARTITION BY, so a date filter from
-- the app cannot change it). security_invoker: the caller's RLS applies.

create or replace view app.v_cash_book with (security_invoker = true) as
select e.occurred_on,
       e.id as event_id,
       e.event_ref,
       e.description,
       e.source,
       le.entry_seq,
       le.debit_paisa as in_paisa,
       le.credit_paisa as out_paisa,
       sum(le.debit_paisa - le.credit_paisa) over (order by e.occurred_on, e.id, le.entry_seq) as balance_paisa
from app.ledger_entries le
join app.accounts a on a.id = le.account_id and a.code = '1000'
join app.events e on e.id = le.event_id;

create or replace view app.v_cash_days with (security_invoker = true) as
select d.occurred_on,
       d.lines,
       d.in_paisa,
       d.out_paisa,
       sum(d.in_paisa - d.out_paisa) over (order by d.occurred_on) - (d.in_paisa - d.out_paisa) as opening_paisa,
       sum(d.in_paisa - d.out_paisa) over (order by d.occurred_on) as closing_paisa
from (select e.occurred_on, count(*) as lines,
             sum(le.debit_paisa) as in_paisa, sum(le.credit_paisa) as out_paisa
      from app.ledger_entries le
      join app.accounts a on a.id = le.account_id and a.code = '1000'
      join app.events e on e.id = le.event_id
      group by e.occurred_on) d;

create or replace view public.v_cash_book with (security_invoker = true) as select * from app.v_cash_book;
create or replace view public.v_cash_days with (security_invoker = true) as select * from app.v_cash_days;

-- read-only for signed-in users, nothing for anon (new objects inherit broad default privileges)
revoke all on app.v_cash_book, app.v_cash_days, public.v_cash_book, public.v_cash_days from public, anon, authenticated;
grant select on app.v_cash_book, app.v_cash_days to authenticated;
grant select on public.v_cash_book, public.v_cash_days to authenticated, service_role;
