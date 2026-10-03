-- Wave 2 item 2: "Correct this entry" for money entries (owner decisions, 3 Oct 2026).
-- The owner gives the CORRECT version of the entry (date + lines); the database works out the correction:
--   * same date  -> one correction on the original date that moves only the difference, account by account;
--   * other date -> a reversal on the original date + the correct entry on the correct date (which may be later than
--                   the original, never after today - the date guards apply).
-- Both entries of a pair are saved in ONE transaction, so a correction can never be half-done. Preview and save use
-- the same function. Money entries only: expenses, asset purchases/disposals, capital, drawings, other - no salt
-- movements and no customer / supplier / advance / stock accounts. An entry that already has a correction is not
-- corrected again on top (delete that correction first). Posted entries are never changed; corrections are added.

create function app.correct_entry_blocker(p_orig app.events) returns text language sql stable set search_path = '' as $$
  select case
    when p_orig.source = 'correction' and p_orig.source_ref is not null
      then format('%s is itself a correction - correct the original entry %s instead.', p_orig.event_ref, p_orig.source_ref)
    when p_orig.event_type not in ('expense', 'asset_purchase', 'asset_disposal', 'capital_injection', 'owner_drawing', 'other')
      or exists (select 1 from app.movements m where m.event_id = p_orig.id)
      or exists (select 1 from app.ledger_entries le join app.accounts a on a.id = le.account_id
                  where le.event_id = p_orig.id and (a.code in ('1100', '2000', '2200') or a.code like '12%'))
      then 'Only money entries can be corrected here. For sales, purchases, crush runs and payments: delete it and enter it again.'
    when exists (select 1 from app.events c where c.source = 'correction' and c.source_ref = p_orig.event_ref)
      then format('%s was already corrected by %s. Delete that correction first (it shows what changes), then correct %s.',
                  p_orig.event_ref,
                  (select string_agg(c.event_ref, ', ' order by c.id) from app.events c where c.source = 'correction' and c.source_ref = p_orig.event_ref),
                  p_orig.event_ref)
  end
$$;

create function app.correct_entry_impl(p_ref text, p_date date, p_lines jsonb, p_reason text, p_idempotency_key text,
                                       p_user uuid, p_preview boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_orig    app.events%rowtype;
  v_block   text;
  v_date    date;
  v_line    jsonb;
  v_dr      bigint;
  v_cr      bigint;
  v_tdr     bigint := 0;
  v_tcr     bigint := 0;
  v_plan    jsonb;
  v_item    jsonb;
  v_n       int := 0;
  v_ref     text;
  v_id      integer;
  v_refs    jsonb := '[]';
  v_orig_lines jsonb;
begin
  if not p_preview then
    if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
      raise exception 'INVARIANT VIOLATION: a correction needs its own idempotency key' using errcode = 'check_violation';
    end if;
    -- same key again (double tap / retry on bad signal): answer with what was saved, write nothing
    select jsonb_agg(e.event_ref order by e.id) into v_refs from app.events e
     where e.idempotency_key in (p_idempotency_key, p_idempotency_key || ':2');
    if v_refs is not null then
      return jsonb_build_object('duplicate', true, 'event_refs', v_refs);
    end if;
    v_refs := '[]';
    if btrim(coalesce(p_reason, '')) = '' then
      raise exception 'INVARIANT VIOLATION: write why this entry is being corrected' using errcode = 'check_violation';
    end if;
  end if;

  select * into v_orig from app.events e where e.event_ref = btrim(coalesce(p_ref, ''));
  if not found then
    raise exception 'INVARIANT VIOLATION: original entry % not found', p_ref using errcode = 'check_violation';
  end if;
  select jsonb_agg(jsonb_build_object('account', a.code, 'name', a.name, 'debit', le.debit_paisa, 'credit', le.credit_paisa) order by le.entry_seq)
    into v_orig_lines from app.ledger_entries le join app.accounts a on a.id = le.account_id where le.event_id = v_orig.id;
  v_block := app.correct_entry_blocker(v_orig);

  -- the form opens with the entry as it is now (or why it cannot be corrected here)
  if p_preview and p_lines is null then
    return jsonb_build_object('ref', v_orig.event_ref, 'date', v_orig.occurred_on, 'type', v_orig.event_type,
                              'description', v_orig.description, 'lines', v_orig_lines, 'blocker', v_block);
  end if;
  if v_block is not null then
    raise exception 'INVARIANT VIOLATION: %', v_block using errcode = 'check_violation';
  end if;

  -- the correct version: balanced, known accounts, one positive side per line, no customer/supplier/stock accounts
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'INVARIANT VIOLATION: at least two ledger lines are required' using errcode = 'check_violation';
  end if;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    if not exists (select 1 from app.accounts a where a.code = v_line->>'account') then
      raise exception 'INVARIANT VIOLATION: unknown account code %', v_line->>'account' using errcode = 'check_violation';
    end if;
    if v_line->>'account' in ('1100', '2000', '2200') or v_line->>'account' like '12%' then
      raise exception 'INVARIANT VIOLATION: account % cannot be used in a money-entry correction', v_line->>'account' using errcode = 'check_violation';
    end if;
    v_dr := coalesce((v_line->>'debit')::bigint, 0);
    v_cr := coalesce((v_line->>'credit')::bigint, 0);
    if v_dr < 0 or v_cr < 0 or (v_dr > 0 and v_cr > 0) or (v_dr = 0 and v_cr = 0) then
      raise exception 'INVARIANT VIOLATION: each line needs exactly one positive side (account %)', v_line->>'account' using errcode = 'check_violation';
    end if;
    v_tdr := v_tdr + v_dr;
    v_tcr := v_tcr + v_cr;
  end loop;
  if v_tdr <> v_tcr then
    raise exception 'INVARIANT VIOLATION: correction not balanced (debit %, credit % paisa)', v_tdr, v_tcr using errcode = 'check_violation';
  end if;

  v_date := coalesce(p_date, v_orig.occurred_on);
  with o as (select a.code, sum(le.debit_paisa - le.credit_paisa) net from app.ledger_entries le join app.accounts a on a.id = le.account_id
              where le.event_id = v_orig.id group by a.code),
       d as (select x->>'account' code, sum(coalesce((x->>'debit')::bigint, 0) - coalesce((x->>'credit')::bigint, 0)) net
               from jsonb_array_elements(p_lines) x group by 1),
       diff as (select coalesce(o.code, d.code) code, coalesce(d.net, 0) - coalesce(o.net, 0) net from o full join d on d.code = o.code)
  select case
    when v_date = v_orig.occurred_on then
      jsonb_build_array(jsonb_build_object('kind', 'fix', 'date', v_orig.occurred_on,
        'lines', (select jsonb_agg(jsonb_build_object('account', code, 'debit', greatest(net, 0), 'credit', greatest(-net, 0)) order by net desc, code)
                    from diff where net <> 0)))
    else
      jsonb_build_array(
        jsonb_build_object('kind', 'reverse', 'date', v_orig.occurred_on,
          'lines', (select jsonb_agg(jsonb_build_object('account', code, 'debit', greatest(-net, 0), 'credit', greatest(net, 0)) order by net, code) from o where net <> 0)),
        jsonb_build_object('kind', 'repost', 'date', v_date,
          'lines', (select jsonb_agg(jsonb_build_object('account', code, 'debit', greatest(net, 0), 'credit', greatest(-net, 0)) order by net desc, code) from d where net <> 0)))
    end into v_plan;
  if v_plan -> 0 -> 'lines' is null or jsonb_typeof(v_plan -> 0 -> 'lines') = 'null' then
    raise exception 'INVARIANT VIOLATION: nothing changed - the correct version is the same as the entry' using errcode = 'check_violation';
  end if;

  if p_preview then
    return jsonb_build_object('ref', v_orig.event_ref, 'plan', v_plan,
      'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', a.code, 'name', a.name,
                     'before_paisa', s * (select coalesce(sum(l.debit_paisa - l.credit_paisa), 0) from app.ledger_entries l where l.account_id = a.id),
                     'after_paisa', s * ((select coalesce(sum(l.debit_paisa - l.credit_paisa), 0) from app.ledger_entries l where l.account_id = a.id) + t.net))
                     order by a.code), '[]')
                   from (select x->>'account' code, sum((x->>'debit')::bigint - (x->>'credit')::bigint) net
                           from jsonb_array_elements(v_plan) p, jsonb_array_elements(p->'lines') x group by 1) t
                   join app.accounts a on a.code = t.code
                   cross join lateral (select case when a.type in ('asset', 'expense') then 1 else -1 end s) z
                  where t.net <> 0));
  end if;

  for v_item in select * from jsonb_array_elements(v_plan) loop
    v_n := v_n + 1;
    v_ref := app.next_event_ref();
    insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name,
                            source, source_ref, created_by, idempotency_key)
    values (v_ref, v_orig.event_type, (v_item->>'date')::date,
            'Correction of ' || v_orig.event_ref || ' - '
              || case v_item->>'kind' when 'reverse' then 'reverses the wrong entry' when 'repost' then 'the correct entry' else 'fix' end
              || ': ' || btrim(p_reason),
            v_orig.party_type, v_orig.party_id, v_orig.party_name, 'correction', v_orig.event_ref, p_user,
            case when v_n = 1 then p_idempotency_key else p_idempotency_key || ':2' end)
    returning id into v_id;
    -- one statement per entry, so the balance check sees the whole entry
    insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
    select v_id, (row_number() over (order by t.ord))::smallint, a.id, (t.line->>'debit')::bigint, (t.line->>'credit')::bigint
      from jsonb_array_elements(v_item->'lines') with ordinality t(line, ord)
      join app.accounts a on a.code = t.line->>'account';
    v_refs := v_refs || to_jsonb(v_ref);
  end loop;
  return jsonb_build_object('event_refs', v_refs, 'plan', v_plan);
end $$;
revoke all on function app.correct_entry_blocker(app.events), app.correct_entry_impl(text, date, jsonb, text, text, uuid, boolean)
  from public, anon, authenticated;

create function public.correct_entry_preview(p_ref text, p_date date default null, p_lines jsonb default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  return app.correct_entry_impl(p_ref, p_date, p_lines, null, null, app.require_user(), true);
end $$;

create function public.correct_entry(p_ref text, p_date date, p_lines jsonb, p_reason text, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return app.correct_entry_impl(p_ref, p_date, p_lines, p_reason, p_idempotency_key, app.require_user(), false);
end $$;

revoke all on function public.correct_entry_preview(text, date, jsonb), public.correct_entry(text, date, jsonb, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.correct_entry_preview(text, date, jsonb), public.correct_entry(text, date, jsonb, text, text)
  to authenticated;
