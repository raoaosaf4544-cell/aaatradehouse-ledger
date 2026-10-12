-- jarvis_heartbeat and jarvis_shutdown_clean updated jarvis.state with no
-- WHERE clause. Through PostgREST that fails with 21000 "UPDATE requires a
-- WHERE clause" (seen 12 Oct 2026: every heartbeat from JARVIS was HTTP 400).
-- jarvis.state is a single row (id = 1, enforced by its check constraint),
-- so the fix is to say so. Same signatures: existing grants are kept.

create or replace function public.jarvis_heartbeat(p_running_task text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform jarvis.require_assistant();
  update jarvis.state
     set last_seen_at = now(), running_task = left(nullif(btrim(p_running_task), ''), 200),
         clean_shutdown = false, stall_alerted_at = null, updated_at = now()
   where id = 1;
end $$;

create or replace function public.jarvis_shutdown_clean()
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform jarvis.require_assistant();
  update jarvis.state set last_seen_at = now(), running_task = null, clean_shutdown = true, updated_at = now()
   where id = 1;
end $$;
