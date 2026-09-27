-- Task 3b: guarded correcting entries. Never edits or deletes: always posts a NEW balanced event that
-- points at the original (source = 'correction', source_ref = original ref) and is attributed to the
-- signed-in user. Each correction carries its own idempotency key, so it can never be posted twice.
create or replace function public.post_correction(
  p_original_ref    text,
  p_event_type      text,
  p_lines           jsonb,           -- [{"account":"1000","debit":450000}, {"account":"5300","credit":450000}] (paisa)
  p_idempotency_key text,
  p_note            text default null,
  p_occurred_on     date default null -- defaults to the original's date; may only be EARLIER or equal
) returns jsonb
language plpgsql security definer
set search_path = app
as $$
declare
  v_user     uuid := app.require_user();          -- "Not authorised" unless signed in and allowlisted
  v_orig     app.events%rowtype;
  v_date     date;
  v_line     jsonb;
  v_dr       bigint;
  v_cr       bigint;
  v_total_dr bigint := 0;
  v_total_cr bigint := 0;
  v_ref      text;
  v_event_id integer;
begin
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'INVARIANT VIOLATION: a correction needs its own idempotency key' using errcode = 'check_violation';
  end if;
  select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('duplicate', true, 'event_ref', v_ref);
  end if;

  select * into v_orig from app.events where event_ref = btrim(coalesce(p_original_ref, ''));
  if not found then
    raise exception 'INVARIANT VIOLATION: original entry % not found', p_original_ref using errcode = 'check_violation';
  end if;
  if v_orig.source = 'correction' then
    raise exception 'INVARIANT VIOLATION: % is itself a correction - correct the original entry instead', p_original_ref
      using errcode = 'check_violation';
  end if;

  v_date := coalesce(p_occurred_on, v_orig.occurred_on);
  if v_date > v_orig.occurred_on then
    raise exception 'INVARIANT VIOLATION: a correction may only be dated on or before the original (% is after %)',
      v_date, v_orig.occurred_on using errcode = 'check_violation';
  end if;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'INVARIANT VIOLATION: at least two ledger lines are required' using errcode = 'check_violation';
  end if;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    if not exists (select 1 from app.accounts where code = v_line->>'account') then
      raise exception 'INVARIANT VIOLATION: unknown account code %', v_line->>'account' using errcode = 'check_violation';
    end if;
    v_dr := coalesce((v_line->>'debit')::bigint, 0);
    v_cr := coalesce((v_line->>'credit')::bigint, 0);
    if v_dr < 0 or v_cr < 0 or (v_dr > 0 and v_cr > 0) or (v_dr = 0 and v_cr = 0) then
      raise exception 'INVARIANT VIOLATION: each line needs exactly one positive side (account %)', v_line->>'account'
        using errcode = 'check_violation';
    end if;
    v_total_dr := v_total_dr + v_dr;
    v_total_cr := v_total_cr + v_cr;
  end loop;
  if v_total_dr <> v_total_cr then
    raise exception 'INVARIANT VIOLATION: correction not balanced (debit %, credit % paisa)', v_total_dr, v_total_cr
      using errcode = 'check_violation';
  end if;

  v_ref := app.next_event_ref();
  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name,
                          source, source_ref, created_by, idempotency_key)
  values (v_ref, p_event_type, v_date,
          'Correction of ' || v_orig.event_ref || ' per paper register'
            || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
          v_orig.party_type, v_orig.party_id, v_orig.party_name,
          'correction', v_orig.event_ref, v_user, p_idempotency_key)
  returning id into v_event_id;

  -- one statement, so the statement-level balance trigger sees the whole event
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event_id, (row_number() over (order by t.ord))::smallint, a.id,
         coalesce((t.line->>'debit')::bigint, 0), coalesce((t.line->>'credit')::bigint, 0)
  from jsonb_array_elements(p_lines) with ordinality t(line, ord)
  join app.accounts a on a.code = t.line->>'account';

  return jsonb_build_object('event_ref', v_ref, 'occurred_on', v_date, 'source_ref', v_orig.event_ref,
                            'debit_paisa', v_total_dr, 'credit_paisa', v_total_cr);
end $$;

revoke all on function public.post_correction(text, text, jsonb, text, text, date) from public, anon;
grant execute on function public.post_correction(text, text, jsonb, text, text, date) to authenticated;
