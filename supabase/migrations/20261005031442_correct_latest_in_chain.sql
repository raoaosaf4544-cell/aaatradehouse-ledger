-- Correct the LATEST version of an entry (owner-approved 5 Oct 2026), and the Unclassified list.
-- A chain = the original entry + every correction that points to it (source = 'correction', source_ref = original).
-- What the entry "is now" = the total of the whole chain, dated on the chain's latest entry.
--   * Only the latest entry of a chain can be corrected (the original when it has no corrections yet). An older,
--     already-replaced version is refused: "EV-x was replaced by EV-y - correct EV-y instead."
--   * Same date  -> one correction moving only the difference against what the entry is now.
--     Other date -> a reversal of what it is now (on its current date) + the correct entry on the new date.
--   * Every new correction points to the same original; older versions stay in the books as history.
-- Before: a correction could not be corrected, and an original with a correction could only be fixed by deleting
-- that correction first (EV-000403). Money entries only, as before; reason rule (app.reason_problem) unchanged.

create or replace function app.correct_entry_blocker(p_orig app.events) returns text
language plpgsql stable set search_path = '' as $$
declare
  v_root   app.events%rowtype;
  v_latest app.events%rowtype;
begin
  select * into v_root from app.events o
   where o.event_ref = case when p_orig.source = 'correction' and p_orig.source_ref is not null then p_orig.source_ref else p_orig.event_ref end;
  if not found then v_root := p_orig; end if;
  select * into v_latest from app.events e
   where e.id = v_root.id or (e.source = 'correction' and e.source_ref = v_root.event_ref) order by e.id desc limit 1;
  if v_latest.id <> p_orig.id then
    return format('%s was replaced by %s - correct %s instead.', p_orig.event_ref, v_latest.event_ref, v_latest.event_ref);
  end if;
  if v_root.event_type not in ('expense', 'asset_purchase', 'asset_disposal', 'capital_injection', 'owner_drawing', 'other')
     or exists (select 1 from app.movements m join app.events e on e.id = m.event_id
                 where e.id = v_root.id or (e.source = 'correction' and e.source_ref = v_root.event_ref))
     or exists (select 1 from app.ledger_entries le join app.accounts a on a.id = le.account_id join app.events e on e.id = le.event_id
                 where (e.id = v_root.id or (e.source = 'correction' and e.source_ref = v_root.event_ref))
                   and (a.code in ('1100', '2000', '2200') or a.code like '12%')) then
    return 'Only money entries can be corrected here. For sales, purchases, crush runs and payments: delete it and enter it again.';
  end if;
  return null;
end $$;

create or replace function app.correct_entry_impl(p_ref text, p_date date, p_lines jsonb, p_reason text, p_idempotency_key text,
                                                  p_user uuid, p_preview boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_orig    app.events%rowtype;   -- the entry tapped (must be the latest of its chain)
  v_root    app.events%rowtype;   -- the original every correction points to
  v_latest  app.events%rowtype;
  v_chain   int[];
  v_now     date;                 -- the date the entry is on now
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
  v_now_lines jsonb;
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
    if app.reason_problem(p_reason) is not null then
      raise exception 'INVARIANT VIOLATION: %', app.reason_problem(p_reason) using errcode = 'check_violation';
    end if;
  end if;

  select * into v_orig from app.events e where e.event_ref = btrim(coalesce(p_ref, ''));
  if not found then
    raise exception 'INVARIANT VIOLATION: original entry % not found', p_ref using errcode = 'check_violation';
  end if;
  select * into v_root from app.events o
   where o.event_ref = case when v_orig.source = 'correction' and v_orig.source_ref is not null then v_orig.source_ref else v_orig.event_ref end;
  if not found then v_root := v_orig; end if;
  if not p_preview then
    -- one correction of a chain at a time: a second one waits, then sees the first as the latest
    perform 1 from app.events where id = v_root.id for update;
  end if;
  v_chain := array(select e.id from app.events e where e.id = v_root.id or (e.source = 'correction' and e.source_ref = v_root.event_ref));
  select * into v_latest from app.events e where e.id = any(v_chain) order by e.id desc limit 1;
  v_now := v_latest.occurred_on;
  select jsonb_agg(jsonb_build_object('account', t.code, 'name', t.name, 'debit', greatest(t.net, 0), 'credit', greatest(-t.net, 0)) order by t.net desc, t.code)
    into v_now_lines
    from (select a.code, a.name, sum(le.debit_paisa - le.credit_paisa) net from app.ledger_entries le join app.accounts a on a.id = le.account_id
           where le.event_id = any(v_chain) group by a.code, a.name having sum(le.debit_paisa - le.credit_paisa) <> 0) t;
  v_block := app.correct_entry_blocker(v_orig);

  -- the form opens with the entry as it is now: the whole chain added up, with the original's wording
  if p_preview and p_lines is null then
    return jsonb_build_object('ref', v_orig.event_ref, 'original_ref', v_root.event_ref, 'date', v_now, 'type', v_root.event_type,
                              'description', v_root.description, 'lines', coalesce(v_now_lines, '[]'), 'blocker', v_block);
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

  v_date := coalesce(p_date, v_now);
  with o as (select a.code, sum(le.debit_paisa - le.credit_paisa) net from app.ledger_entries le join app.accounts a on a.id = le.account_id
              where le.event_id = any(v_chain) group by a.code),
       d as (select x->>'account' code, sum(coalesce((x->>'debit')::bigint, 0) - coalesce((x->>'credit')::bigint, 0)) net
               from jsonb_array_elements(p_lines) x group by 1),
       diff as (select coalesce(o.code, d.code) code, coalesce(d.net, 0) - coalesce(o.net, 0) net from o full join d on d.code = o.code)
  select case
    when v_date = v_now then
      jsonb_build_array(jsonb_build_object('kind', 'fix', 'date', v_now,
        'lines', (select jsonb_agg(jsonb_build_object('account', code, 'debit', greatest(net, 0), 'credit', greatest(-net, 0)) order by net desc, code)
                    from diff where net <> 0)))
    else
      jsonb_build_array(
        jsonb_build_object('kind', 'reverse', 'date', v_now,
          'lines', (select jsonb_agg(jsonb_build_object('account', code, 'debit', greatest(-net, 0), 'credit', greatest(net, 0)) order by net, code) from o where net <> 0)),
        jsonb_build_object('kind', 'repost', 'date', v_date,
          'lines', (select jsonb_agg(jsonb_build_object('account', code, 'debit', greatest(net, 0), 'credit', greatest(-net, 0)) order by net desc, code) from d where net <> 0)))
    end into v_plan;
  if v_plan -> 0 -> 'lines' is null or jsonb_typeof(v_plan -> 0 -> 'lines') = 'null' then
    raise exception 'INVARIANT VIOLATION: nothing changed - the correct version is the same as the entry' using errcode = 'check_violation';
  end if;

  if p_preview then
    return jsonb_build_object('ref', v_orig.event_ref, 'original_ref', v_root.event_ref, 'plan', v_plan,
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
    values (v_ref, v_root.event_type, (v_item->>'date')::date,
            'Correction of ' || v_root.event_ref
              || case when v_latest.id <> v_root.id then ' (replaces ' || v_latest.event_ref || ')' else '' end || ' - '
              || case v_item->>'kind' when 'reverse' then 'reverses the wrong entry' when 'repost' then 'the correct entry' else 'fix' end
              || ': ' || btrim(p_reason),
            v_root.party_type, v_root.party_id, v_root.party_name, 'correction', v_root.event_ref, p_user,
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

-- What is still in 5950 Personal/Unclassified, one row per chain: the original's date and register wording, the amount
-- still there, and the latest entry (the one to correct). A chain whose 5950 adds up to 0 has been moved and is gone.
create view public.v_unclassified with (security_invoker = true) as
with c as (
  select e.id, case when e.source = 'correction' and e.source_ref is not null then e.source_ref else e.event_ref end as root_ref
    from app.events e
)
select c.root_ref as original_ref,
       r.occurred_on as original_date,
       r.description as original_description,
       l.event_ref as latest_ref,
       l.occurred_on as entry_date,
       sum(le.debit_paisa - le.credit_paisa)::bigint as amount_paisa
  from c
  join app.ledger_entries le on le.event_id = c.id
  join app.accounts a on a.id = le.account_id and a.code = '5950'
  left join app.events r on r.event_ref = c.root_ref
  cross join lateral (select x.event_ref, x.occurred_on from c c2 join app.events x on x.id = c2.id
                       where c2.root_ref = c.root_ref order by x.id desc limit 1) l
 group by c.root_ref, r.occurred_on, r.description, l.event_ref, l.occurred_on
having sum(le.debit_paisa - le.credit_paisa) <> 0;

revoke all on public.v_unclassified from public, anon;
grant select on public.v_unclassified to authenticated, service_role;
