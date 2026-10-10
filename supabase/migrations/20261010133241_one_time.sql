-- "One-time setup cost / ایک بار کا خرچ" tick (owner-approved 10 Oct 2026). Saved on the entry; no account changes.
-- The business page shows running costs and one-time costs apart, so break-even is not distorted.
-- Nullable on purpose: restoring an entry deleted before today rebuilds its row from a snapshot without this key.
-- A correction counts as one-time when the entry it corrects was ticked.

alter table app.events add column one_time boolean;
comment on column app.events.one_time is 'Ticked on Money Out: a one-time setup cost (machine part, first signboard). null/false = running cost.';

drop function public.post_event(text, date, text, jsonb, text, text, uuid, text);
create function public.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb,
  p_party_type text default null, p_party_name text default null, p_created_by uuid default null,
  p_idempotency_key text default null, p_one_time boolean default false)
returns text language plpgsql security definer set search_path to 'app' as $function$
declare v_ref text;
begin
  v_ref := app.post_event(p_event_type, p_occurred_on, p_description, p_lines, p_party_type, p_party_name,
    app.require_user(), p_idempotency_key);
  if coalesce(p_one_time, false) then
    update app.events set one_time = true where event_ref = v_ref;
  end if;
  return v_ref;
end $function$;
revoke all on function public.post_event(text, date, text, jsonb, text, text, uuid, text, boolean) from public, anon;
grant execute on function public.post_event(text, date, text, jsonb, text, text, uuid, text, boolean) to authenticated, service_role;
