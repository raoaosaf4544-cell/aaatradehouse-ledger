-- Task 5B: after a save (or a "duplicate" reply on retry) the app confirms the entry from the
-- database: ref, type, date and posted amount of the event saved under that idempotency key.
-- Read-only; only signed-in allowlisted users (app.require_user raises "Not authorised").
create or replace function public.entry_by_key(p_idempotency_key text)
returns jsonb
language plpgsql stable security definer
set search_path = app
as $$
declare
  v jsonb;
begin
  perform app.require_user();
  select jsonb_build_object(
           'event_ref', e.event_ref,
           'event_type', e.event_type,
           'occurred_on', e.occurred_on,
           'total_paisa', (select coalesce(sum(le.debit_paisa), 0) from app.ledger_entries le where le.event_id = e.id))
    into v
  from app.events e
  where e.idempotency_key = p_idempotency_key;
  return v;  -- null when nothing was saved under this key
end $$;

revoke all on function public.entry_by_key(text) from public, anon;
grant execute on function public.entry_by_key(text) to authenticated;
