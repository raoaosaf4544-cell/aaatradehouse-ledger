-- Reason rule (owner-approved 5 Oct 2026): every delete and correction (and later every edit) needs a real reason -
-- at least 4 letters, not only digits or symbols. Closes the old "one-letter reason" finding.
-- One rule in one place (app.reason_problem); delete_entry_impl and correct_entry_impl only swap their old
-- "reason is not blank" check for it. Each body is patched with an exact text replace of that check, and the
-- migration stops if the check text is not found, so nothing else in either function changes.

create function app.reason_problem(p_reason text) returns text
language sql immutable set search_path = '' as $$
  select case when length(regexp_replace(coalesce(p_reason, ''), '[^[:alpha:]]', '', 'g')) < 4
    then 'Write a short reason, at least 4 letters (not only numbers).' end
$$;
revoke all on function app.reason_problem(text) from public, anon, authenticated;

do $m$
declare
  v_def text;
  v_old text;
begin
  v_def := pg_get_functiondef('app.delete_entry_impl(text,text,uuid,text)'::regprocedure);
  v_old := $o$  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'Cannot delete: a reason is required.' using errcode = 'check_violation';
  end if;$o$;
  if position(v_old in v_def) = 0 then
    raise exception 'reason rule: delete_entry_impl reason check not found - function changed, migration stopped';
  end if;
  execute replace(v_def, v_old, $n$  if app.reason_problem(p_reason) is not null then
    raise exception 'Cannot delete: %', app.reason_problem(p_reason) using errcode = 'check_violation';
  end if;$n$);

  v_def := pg_get_functiondef('app.correct_entry_impl(text,date,jsonb,text,text,uuid,boolean)'::regprocedure);
  v_old := $o$    if btrim(coalesce(p_reason, '')) = '' then
      raise exception 'INVARIANT VIOLATION: write why this entry is being corrected' using errcode = 'check_violation';
    end if;$o$;
  if position(v_old in v_def) = 0 then
    raise exception 'reason rule: correct_entry_impl reason check not found - function changed, migration stopped';
  end if;
  execute replace(v_def, v_old, $n$    if app.reason_problem(p_reason) is not null then
      raise exception 'INVARIANT VIOLATION: %', app.reason_problem(p_reason) using errcode = 'check_violation';
    end if;$n$);
end $m$;
