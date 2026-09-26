-- Task 2: link Rao's Supabase login to the Rao Aosaf (Operator) row. Looked up by email; fails loudly if absent.
do $$
declare v_auth uuid;
begin
  select id into strict v_auth from auth.users where lower(email) = lower('AAA_Trading.pk@outlook.com');
  update app.users set auth_user_id = v_auth where id = '11111111-1111-1111-1111-111111111111';
end $$;
