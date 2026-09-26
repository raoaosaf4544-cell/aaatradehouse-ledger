-- FIX: tg_n_rows is not populated for statement triggers here; count the transition table instead.
create or replace function app.restrict_single_statement_insert()
returns trigger language plpgsql set search_path = 'app' as $fn$
declare v_rows bigint;
begin
  select count(*) into v_rows from inserted;
  if v_rows is null or v_rows > 1 then
    raise exception 'INVARIANT VIOLATION: multi-row insert into app.% bypasses per-event balance trigger', tg_table_name
      using errcode = 'feature_not_supported';
  end if;
  return null;
end $fn$;