-- Wave 2 item 0: JARVIS gets its own login (role 'assistant') to READ the ledger through the same RLS as the
-- app, instead of relying on the postgres role. Owner-approved design.
-- The assistant role is READ-ONLY: require_user() (the gate of every save function) refuses it, so linking this
-- login cannot change the books. Writes stay closed until post_event is restricted (Wave 2 item 8) and the owner
-- approves JARVIS writing.

alter table app.users drop constraint users_role_check;
alter table app.users add constraint users_role_check
  check (role = any (array['owner'::text, 'operator'::text, 'auditor'::text, 'assistant'::text]));

do $$
declare v_auth uuid;
begin
  select id into strict v_auth from auth.users where lower(email) = lower('aaa_trading.pk+jarvis@outlook.com');
  if not exists (select 1 from app.users where auth_user_id = v_auth) then
    insert into app.users (id, name, role, is_active, auth_user_id)
    values (gen_random_uuid(), 'JARVIS (Rao''s assistant)', 'assistant', true, v_auth);
  end if;
end $$;

create or replace function app.require_user()
returns uuid
language plpgsql
stable
security definer
set search_path = app
as $$
declare v_id uuid;
begin
  -- an active, linked user who may record; the assistant role only reads
  select id into v_id from app.users where auth_user_id = auth.uid() and is_active and role <> 'assistant';
  if v_id is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  return v_id;
end $$;
