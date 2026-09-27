-- Task 3C: JARVIS tables. RLS on with no policies, so API roles (anon/authenticated) see nothing.
-- JARVIS connects directly as postgres (owner, BYPASSRLS) and is unaffected.
alter table public.contacts enable row level security;
alter table public.research_leads enable row level security;
alter table public.notifications enable row level security;
alter table public.reject_log enable row level security;
-- staging_candidates already had RLS enabled with no policies.

revoke all on public.contacts, public.research_leads, public.notifications, public.reject_log, public.staging_candidates
  from anon, authenticated;
revoke all on sequence public.notifications_id_seq, public.reject_log_id_seq from anon, authenticated;
