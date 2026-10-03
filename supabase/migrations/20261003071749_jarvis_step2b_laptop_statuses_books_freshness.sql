-- Phone channel, step 2 fixes.
-- 1. Approval statuses are exactly the laptop's six (the laptop is the source of truth; expiry is stored as 'rejected').
-- 2. The stale-books rule, in one place for the CFO and the bot: newest entry date, newest sale date and two flags.
--    Sales are stale when the newest sale is more than 5 days old; the books when the newest entry of any kind is
--    more than 3 days old. Dates are entry dates (occurred_on); "today" is the Asia/Karachi date.

alter table jarvis.approvals_mirror drop constraint approvals_mirror_status_check;
alter table jarvis.approvals_mirror add constraint approvals_mirror_status_check
  check (status in ('pending', 'approved', 'rejected', 'executing', 'done', 'failed'));

create view app.v_books_freshness with (security_invoker = true) as
with p as (select (now() at time zone 'Asia/Karachi')::date as today),
f as (select (select max(e.occurred_on) from app.events e) as newest_entry_on,
             (select max(s.occurred_on) from app.sales s)  as newest_sale_on)
select p.today as as_of,
       f.newest_entry_on,
       f.newest_sale_on,
       coalesce(p.today - f.newest_sale_on > 5, true)  as sales_stale,
       coalesce(p.today - f.newest_entry_on > 3, true) as books_stale
  from p, f;
create view public.v_books_freshness with (security_invoker = true) as select * from app.v_books_freshness;
revoke all on app.v_books_freshness, public.v_books_freshness from public, anon, authenticated;
grant select on app.v_books_freshness to authenticated;
grant select on public.v_books_freshness to authenticated, service_role;

-- The bot reads it through v_status, via a fourth owner-run read function (same reason as the other three).
create function jarvis.read_freshness()
returns table (newest_entry_on date, newest_sale_on date, sales_stale boolean, books_stale boolean)
language sql stable security definer set search_path = '' as $$
  select f.newest_entry_on, f.newest_sale_on, f.sales_stale, f.books_stale from app.v_books_freshness f
$$;
revoke all on function jarvis.read_freshness() from public, anon, authenticated;
grant execute on function jarvis.read_freshness() to jarvis_cloud;

create or replace view jarvis.v_status with (security_invoker = true) as
select s.owner_chat_id is not null as paired, s.last_seen_at, s.running_task, s.clean_shutdown, s.snooze_until, s.webhook_ok_at,
       (select count(*) from jarvis.outbox o where o.sent_at is null)                                      as unsent,
       (select count(*) from jarvis.outbox o where o.urgent and o.sent_at is not null and o.seen_at is null) as unseen_urgent,
       (select count(*) from jarvis.approvals_mirror m where m.status = 'pending')                         as pending_approvals,
       (select count(*) from jarvis.inbox i where i.status = 'new')                                        as decisions_not_picked_up,
       f.newest_entry_on, f.newest_sale_on, f.sales_stale, f.books_stale
  from jarvis.state s
 cross join jarvis.read_freshness() f;
