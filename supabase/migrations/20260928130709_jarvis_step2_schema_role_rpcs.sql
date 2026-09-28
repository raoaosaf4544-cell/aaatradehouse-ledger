-- Phone channel, step 2: the jarvis schema (outbox, approvals mirror, inbox, state, audit), the jarvis_cloud role the
-- edge functions switch to, the six contract RPCs for the JARVIS laptop login, and what the bot may read.
-- No ledger table or policy is changed. The jarvis schema is not exposed by the API.

create schema jarvis;
revoke all on schema jarvis from public, anon, authenticated;

-- The edge functions connect as postgres and run every transaction with SET LOCAL ROLE jarvis_cloud.
-- postgres may switch to it but inherits nothing from it.
create role jarvis_cloud nologin;
grant jarvis_cloud to postgres with inherit false, set true;
grant usage on schema jarvis to jarvis_cloud;

-- Messages for the owner's phone. The notifier sends them, retries with backoff, and rings ntfy for urgent ones.
create table jarvis.outbox (
  id            bigint generated always as identity primary key,
  kind          text not null check (kind ~ '^[a-z_]{1,40}$'),
  title         text not null check (length(title) between 1 and 200),
  body          text not null default '' check (length(body) <= 3500),
  urgent        boolean not null default false,
  apr_id        text check (apr_id ~ '^APR-[0-9]{1,9}$'),
  dedupe_key    text unique check (length(dedupe_key) <= 200),
  created_at    timestamptz not null default now(),
  send_attempts int not null default 0,
  next_send_at  timestamptz not null default now(),
  sent_at       timestamptz,
  tg_message_id bigint,
  last_error    text check (length(last_error) <= 500),
  seen_at       timestamptz,
  ring_count    int not null default 0,
  last_ring_at  timestamptz,
  check (kind <> 'approval' or apr_id is not null)
);
create index outbox_unsent on jarvis.outbox (next_send_at) where sent_at is null;

-- Copy of the laptop's approval requests, so the phone can show and decide them.
create table jarvis.approvals_mirror (
  apr_id        text primary key check (apr_id ~ '^APR-[0-9]{1,9}$'),
  tool          text not null check (length(tool) between 1 and 100),
  description   text not null check (length(description) <= 1000),
  status        text not null check (status in ('pending', 'approved', 'rejected', 'running', 'done', 'failed', 'expired', 'cancelled')),
  args_hash     text not null check (length(args_hash) <= 128),
  first_seen_at timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  escalated_at  timestamptz  -- set once when "APR-n waiting 2h+" was queued
);

-- Decisions made on the phone, waiting for the laptop to pick them up (new -> taken -> done). One per approval.
create table jarvis.inbox (
  id          bigint generated always as identity primary key,
  apr_id      text not null unique references jarvis.approvals_mirror (apr_id),
  decision    text not null check (decision in ('approve', 'reject')),
  status      text not null default 'new' check (status in ('new', 'taken', 'done')),
  created_at  timestamptz not null default now(),
  taken_at    timestamptz,
  finished_at timestamptz,
  ok          boolean,
  result      text check (length(result) <= 2000)
);

-- One row: pairing, laptop heartbeat, snooze, brief bookkeeping.
create table jarvis.state (
  id               int primary key default 1 check (id = 1),
  owner_chat_id    bigint,
  paired_at        timestamptz,
  last_seen_at     timestamptz,
  running_task     text check (length(running_task) <= 200),
  clean_shutdown   boolean not null default true,  -- a laptop that never started never rings
  stall_alerted_at timestamptz,
  snooze_until     timestamptz,
  last_brief_am    date,
  last_brief_pm    date,
  webhook_ok_at    timestamptz,
  updated_at       timestamptz not null default now()
);
insert into jarvis.state default values;

-- Pairing is accepted once: the owner chat can be set but never changed.
create function jarvis.state_pair_once() returns trigger language plpgsql set search_path = '' as $$
begin
  if old.owner_chat_id is not null and new.owner_chat_id is distinct from old.owner_chat_id then
    raise exception 'Already paired' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger state_pair_once before update on jarvis.state for each row execute function jarvis.state_pair_once();

-- What the cloud side did or refused (strangers, unknown messages, send failures, its own crashes). Never secrets.
create table jarvis.audit (
  id     bigint generated always as identity primary key,
  at     timestamptz not null default now(),
  source text not null check (length(source) <= 40),
  event  text not null check (length(event) <= 60),
  detail jsonb not null default '{}' check (pg_column_size(detail) <= 8000)
);

-- RLS everywhere; only jarvis_cloud has policies. The JARVIS login reaches these tables only through the six RPCs.
alter table jarvis.outbox           enable row level security;
alter table jarvis.approvals_mirror enable row level security;
alter table jarvis.inbox            enable row level security;
alter table jarvis.state            enable row level security;
alter table jarvis.audit            enable row level security;
create policy jarvis_cloud_rw on jarvis.outbox           to jarvis_cloud using (true) with check (true);
create policy jarvis_cloud_rw on jarvis.approvals_mirror to jarvis_cloud using (true) with check (true);
create policy jarvis_cloud_rw on jarvis.inbox            to jarvis_cloud using (true) with check (true);
create policy jarvis_cloud_rw on jarvis.state            to jarvis_cloud using (true) with check (true);
create policy jarvis_cloud_rw on jarvis.audit            to jarvis_cloud using (true) with check (true);

-- Least privilege for the edge functions: only the columns each one has to write.
grant select, insert on jarvis.outbox to jarvis_cloud;
grant update (send_attempts, next_send_at, sent_at, tg_message_id, last_error, seen_at, ring_count, last_ring_at)
  on jarvis.outbox to jarvis_cloud;
grant select on jarvis.approvals_mirror to jarvis_cloud;
grant update (escalated_at) on jarvis.approvals_mirror to jarvis_cloud;
grant select, insert on jarvis.inbox to jarvis_cloud;
grant select on jarvis.state to jarvis_cloud;
grant update (owner_chat_id, paired_at, stall_alerted_at, snooze_until, last_brief_am, last_brief_pm, webhook_ok_at, updated_at)
  on jarvis.state to jarvis_cloud;
grant insert on jarvis.audit to jarvis_cloud;

-- The bot reads the CFO figures through three owner-run read functions. (An owner-run view does not work: the app
-- views are security_invoker, so they check the ledger tables against jarvis_cloud itself.) They read the same views
-- the CFO reads and return only what a message shows. jarvis_cloud may execute these three and nothing else.
create function jarvis.read_cash()
returns table (as_of date, cash_paisa numeric, today_in_paisa numeric, today_out_paisa numeric)
language sql stable security definer set search_path = '' as $$
  with p as (select (now() at time zone 'Asia/Karachi')::date as today)
  select p.today,
         (select t.debit_paisa - t.credit_paisa from app.v_account_totals t where t.code = '1000'),
         coalesce((select d.in_paisa  from app.v_cash_days d where d.occurred_on = p.today), 0),
         coalesce((select d.out_paisa from app.v_cash_days d where d.occurred_on = p.today), 0)
    from p
$$;

create function jarvis.read_runway()
returns table (as_of date, window_start date, cash_paisa numeric, spend_30d_paisa numeric, runway_months numeric,
               formula text, account_codes text[], spend_by_account jsonb)
language sql stable security definer set search_path = '' as $$
  select r.as_of, r.window_start, r.cash_paisa, r.spend_30d_paisa, r.runway_months, r.formula, r.account_codes, r.spend_by_account
    from app.v_cfo_runway r
$$;

create function jarvis.read_udhaar()
returns table (customer_name text, outstanding_paisa bigint, unpaid_over_7d_paisa numeric, last_sale_on date)
language sql stable security definer set search_path = '' as $$
  select u.customer_name, u.outstanding_paisa, u.unpaid_over_7d_paisa, u.last_sale_on
    from app.v_udhaar_aging u
$$;

revoke all on function jarvis.read_cash(), jarvis.read_runway(), jarvis.read_udhaar() from public, anon, authenticated;
grant execute on function jarvis.read_cash(), jarvis.read_runway(), jarvis.read_udhaar() to jarvis_cloud;

-- Waiting approvals and status read only jarvis tables, so they are plain security_invoker views.
create view jarvis.v_waiting with (security_invoker = true) as
select m.apr_id, m.tool, m.description, m.first_seen_at, i.decision as phone_decision, i.status as decision_status
  from jarvis.approvals_mirror m
  left join jarvis.inbox i on i.apr_id = m.apr_id
 where m.status = 'pending';

create view jarvis.v_status with (security_invoker = true) as
select s.owner_chat_id is not null as paired, s.last_seen_at, s.running_task, s.clean_shutdown, s.snooze_until, s.webhook_ok_at,
       (select count(*) from jarvis.outbox o where o.sent_at is null)                                      as unsent,
       (select count(*) from jarvis.outbox o where o.urgent and o.sent_at is not null and o.seen_at is null) as unseen_urgent,
       (select count(*) from jarvis.approvals_mirror m where m.status = 'pending')                         as pending_approvals,
       (select count(*) from jarvis.inbox i where i.status = 'new')                                        as decisions_not_picked_up
  from jarvis.state s;

revoke all on all tables in schema jarvis from public, anon, authenticated;
grant select on jarvis.v_waiting, jarvis.v_status to jarvis_cloud;

-- The six contract RPCs for the JARVIS laptop (the 'assistant' login). Nobody else may call them.
create function jarvis.require_assistant() returns void language plpgsql stable set search_path = '' as $$
begin
  if not exists (select 1 from app.users u where u.auth_user_id = auth.uid() and u.is_active and u.role = 'assistant') then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
end $$;
revoke all on function jarvis.require_assistant() from public;

create function public.jarvis_notify(p_kind text, p_title text, p_body text, p_urgent boolean,
                                     p_apr_id text default null, p_dedupe_key text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  perform jarvis.require_assistant();
  insert into jarvis.outbox (kind, title, body, urgent, apr_id, dedupe_key)
  values (p_kind, p_title, coalesce(p_body, ''), coalesce(p_urgent, false), p_apr_id, p_dedupe_key)
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  if v_id is null then  -- same dedupe_key already queued: return that message
    select o.id into v_id from jarvis.outbox o where o.dedupe_key = p_dedupe_key;
  end if;
  return v_id;
end $$;

create function public.jarvis_heartbeat(p_running_task text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform jarvis.require_assistant();
  update jarvis.state
     set last_seen_at = now(), running_task = left(nullif(btrim(p_running_task), ''), 200),
         clean_shutdown = false, stall_alerted_at = null, updated_at = now();
end $$;

create function public.jarvis_shutdown_clean()
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform jarvis.require_assistant();
  update jarvis.state set last_seen_at = now(), running_task = null, clean_shutdown = true, updated_at = now();
end $$;

create function public.jarvis_mirror_approval(p_apr_id text, p_tool text, p_description text, p_status text, p_args_hash text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform jarvis.require_assistant();
  insert into jarvis.approvals_mirror (apr_id, tool, description, status, args_hash)
  values (p_apr_id, p_tool, p_description, p_status, p_args_hash)
  on conflict (apr_id) do update
     set tool = excluded.tool, description = excluded.description, status = excluded.status,
         args_hash = excluded.args_hash, updated_at = now();
end $$;

-- Atomically hands every new decision to the laptop (new -> taken). Safe if two laptop loops call it at once.
create function public.jarvis_claim_decisions()
returns table (id bigint, apr_id text, decision text, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform jarvis.require_assistant();
  return query
  update jarvis.inbox i set status = 'taken', taken_at = now()
   where i.id in (select n.id from jarvis.inbox n where n.status = 'new' order by n.id for update skip locked)
  returning i.id, i.apr_id, i.decision, i.created_at;
end $$;

create function public.jarvis_finish_decision(p_id bigint, p_ok boolean, p_result text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform jarvis.require_assistant();
  if p_ok is null then
    raise exception 'p_ok is required' using errcode = '22004';
  end if;
  update jarvis.inbox i set status = 'done', finished_at = now(), ok = p_ok, result = left(p_result, 2000)
   where i.id = p_id and i.status = 'taken';
  if not found then
    raise exception 'Decision % is not waiting to be finished', p_id using errcode = 'P0002';
  end if;
end $$;

revoke all on function public.jarvis_notify(text, text, text, boolean, text, text), public.jarvis_heartbeat(text),
  public.jarvis_shutdown_clean(), public.jarvis_mirror_approval(text, text, text, text, text),
  public.jarvis_claim_decisions(), public.jarvis_finish_decision(bigint, boolean, text)
  from public, anon, authenticated, service_role;
grant execute on function public.jarvis_notify(text, text, text, boolean, text, text), public.jarvis_heartbeat(text),
  public.jarvis_shutdown_clean(), public.jarvis_mirror_approval(text, text, text, text, text),
  public.jarvis_claim_decisions(), public.jarvis_finish_decision(bigint, boolean, text)
  to authenticated;
