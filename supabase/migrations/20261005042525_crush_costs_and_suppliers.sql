-- Crushing costs paid line by line + who we owe (owner-approved 5 Oct 2026).
-- Real life: labour is often paid on the spot, electricity at month end, some costs a week later, sometimes part
-- now and the rest later. So each crushing-cost line says how much is paid now; the rest is owed to a named party.
--
--  1. Suppliers (2000) lines carry their party ON THE LINE (ledger_entries.party_id): one crush can owe a worker
--     and the electricity bill at once. A new 2000 line without a supplier is refused; party_id is only for 2000
--     lines. (The 2 old 2000 lines, from before this, net to 0 and stay as they are; restoring a deleted entry
--     puts lines back exactly as they were.) Purchases on credit now link their supplier too.
--  2. app.supplier_id: find or add a supplier by name (one per name). parties.extra_to_account marks a monthly
--     bill (electricity -> 5100 Utilities): paying it MORE than the estimates owed sends the extra there.
--  3. public.record_crush / public.crush_preview replace record_process_run / crush_run_preview. Each cost line:
--     kind, amount, paid now (0..amount), owed to (needed when anything is left), expected date. The full amount of
--     every line goes into the salt cost (output batch value); paid now -> Cr 1000; the rest -> Cr 2000 per party.
--     One event, one transaction. Costing is app.crush_run_values (loss absorbed, previous migration).
--  4. public.pay_supplier: Dr 2000 (that party) / Cr 1000. Never more than owed - except for a bill party, where the
--     extra goes to its account (5100) and the answer says how much. public.clear_supplier_leftover: a bill
--     estimate that was more than the real bill - Dr 2000 / Cr 5100, reason required (4-letter rule).
--  5. public.v_supplier_balances: what we owe each supplier. Delete / restore refuse to leave a supplier below 0.

-- 1 + 2 ------------------------------------------------------------------------------------------------------------
alter table app.ledger_entries add column party_id integer references app.parties(id);
create index ledger_entries_party_idx on app.ledger_entries (party_id) where party_id is not null;
alter table app.parties add column extra_to_account text references app.accounts(code);
create unique index parties_kind_name_uq on app.parties (kind, lower(btrim(name)));

create function app.assert_supplier_line_linked() returns trigger language plpgsql set search_path = '' as $$
declare v_code text;
begin
  if current_setting('app.restoring', true) = 'on' then
    return new; -- a restore puts back exactly what was deleted
  end if;
  select a.code into v_code from app.accounts a where a.id = new.account_id;
  if v_code = '2000' and new.party_id is null then
    raise exception 'INVARIANT VIOLATION: every Suppliers (2000) line needs the supplier it is owed to' using errcode = 'check_violation';
  end if;
  if new.party_id is not null and (v_code <> '2000' or not exists (select 1 from app.parties p where p.id = new.party_id and p.kind = 'supplier')) then
    raise exception 'INVARIANT VIOLATION: only a Suppliers (2000) line can carry a supplier' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger trg_supplier_line_linked before insert on app.ledger_entries for each row execute function app.assert_supplier_line_linked();

create function app.supplier_id(p_name text, p_extra_to_account text default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_id integer;
begin
  if v_name = '' then
    raise exception 'INVARIANT VIOLATION: supplier name is required' using errcode = 'check_violation';
  end if;
  select p.id into v_id from app.parties p where p.kind = 'supplier' and lower(btrim(p.name)) = lower(v_name);
  if v_id is null then
    insert into app.parties (party_ref, name, kind) values (app.next_party_ref(), v_name, 'supplier') returning id into v_id;
  end if;
  if p_extra_to_account is not null then
    update app.parties set extra_to_account = p_extra_to_account where id = v_id and extra_to_account is null;
  end if;
  return v_id;
end $$;

-- purchases on credit: link the supplier on the 2000 line (exact text replace; stops if the insert is not found)
do $m$
declare
  v_def text := pg_get_functiondef('app.record_purchase_impl(text,text,text,bigint,bigint,boolean,date,text,uuid,text,jsonb)'::regprocedure);
  v_old constant text := $o$  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event_id, x.seq, a.id, x.dr, x.cr
  from (values$o$;
begin
  if position(v_old in v_def) = 0 then
    raise exception 'crush costs: record_purchase_impl ledger insert not found - function changed, migration stopped';
  end if;
  execute replace(v_def, v_old, $n$  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa, party_id)
  select v_event_id, x.seq, a.id, x.dr, x.cr, case when x.acc_code = '2000' then app.supplier_id(p_supplier) end
  from (values$n$);
end $m$;

-- 3 ----------------------------------------------------------------------------------------------------------------
-- The crushing-cost lines checked and added up: total (all into the salt cost), paid now, owed per party, words.
create function app.crush_cost_lines(p_costs jsonb) returns jsonb language plpgsql stable set search_path = '' as $$
declare
  c        jsonb;
  v_amt    bigint;
  v_paid   bigint;
  v_name   text;
  v_key    text;
  v_total  bigint := 0;
  v_paid_t bigint := 0;
  v_owed   jsonb := '{}';
  v_words  text[] := '{}';
  c_kinds  constant jsonb := '{"labour": "Labour", "electricity": "Electricity", "diesel": "Diesel", "bags": "Empty bags", "other": "Other"}';
begin
  if p_costs is null then
    p_costs := '[]';
  end if;
  if jsonb_typeof(p_costs) <> 'array' then
    raise exception 'INVARIANT VIOLATION: crushing costs must be a list' using errcode = 'check_violation';
  end if;
  for c in select * from jsonb_array_elements(p_costs) loop
    if not c_kinds ? coalesce(c->>'kind', '') then
      raise exception 'INVARIANT VIOLATION: unknown crushing cost kind %', c->>'kind' using errcode = 'check_violation';
    end if;
    v_amt := (c->>'amount_paisa')::bigint;
    v_paid := coalesce((c->>'paid_now_paisa')::bigint, 0);
    if v_amt is null or v_amt <= 0 then
      raise exception 'INVARIANT VIOLATION: each crushing cost needs an amount more than 0' using errcode = 'check_violation';
    end if;
    if v_paid < 0 or v_paid > v_amt then
      raise exception 'INVARIANT VIOLATION: paid now (Rs %) must be between 0 and the amount (Rs %)', v_paid / 100.0, v_amt / 100.0 using errcode = 'check_violation';
    end if;
    v_total := v_total + v_amt;
    v_paid_t := v_paid_t + v_paid;
    v_words := v_words || (c_kinds->>(c->>'kind') || ' Rs ' || (v_amt / 100.0)::numeric(14,2)
      || case when v_paid = v_amt then ' paid now'
              else coalesce(case when v_paid > 0 then ' (Rs ' || (v_paid / 100.0)::numeric(14,2) || ' now)' end, '')
                   || ', Rs ' || ((v_amt - v_paid) / 100.0)::numeric(14,2) || ' owed to ' || btrim(coalesce(c->>'owed_to', ''))
                   || coalesce(' by ' || nullif(c->>'expected_on', ''), '') end);
    if v_amt > v_paid then
      v_name := btrim(coalesce(c->>'owed_to', ''));
      if v_name = '' then
        raise exception 'INVARIANT VIOLATION: Rs % of % is to pay later - say who it is owed to', (v_amt - v_paid) / 100.0, lower(c_kinds->>(c->>'kind'))
          using errcode = 'check_violation';
      end if;
      v_key := lower(v_name);
      v_owed := jsonb_set(v_owed, array[v_key], jsonb_build_object(
        'name', coalesce(v_owed->v_key->>'name', v_name),
        'amount_paisa', coalesce((v_owed->v_key->>'amount_paisa')::bigint, 0) + v_amt - v_paid,
        'bill', coalesce((v_owed->v_key->>'bill')::boolean, false) or c->>'kind' = 'electricity'));
    end if;
  end loop;
  return jsonb_build_object('total_paisa', v_total, 'paid_now_paisa', v_paid_t, 'later_paisa', v_total - v_paid_t,
                            'owed', (select coalesce(jsonb_agg(value order by key), '[]') from jsonb_each(v_owed)),
                            'words', array_to_string(v_words, '; '));
end $$;

-- The crush figures (app.crush_run_values) with the crushing cost credited line by line: Cr 1000 paid now,
-- Cr 2000 per party owed (the line names its party; the save turns names into suppliers).
create function app.crush_values_with_costs(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb,
                                            p_wastage_grams bigint, p_costs jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  k jsonb := app.crush_cost_lines(p_costs);
  v jsonb;
begin
  v := app.crush_run_values(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, (k->>'total_paisa')::bigint, true);
  -- the one "paid in cash" line crush_run_values adds for the cost is replaced by the real split
  v := jsonb_set(v, '{lines}',
         (select coalesce(jsonb_agg(l order by ord), '[]') from jsonb_array_elements(v->'lines') with ordinality x(l, ord) where l->>'account' <> '1000')
         || case when (k->>'paid_now_paisa')::bigint > 0
                 then jsonb_build_array(jsonb_build_object('account', '1000', 'debit', 0, 'credit', (k->>'paid_now_paisa')::bigint)) else '[]' end
         || (select coalesce(jsonb_agg(jsonb_build_object('account', '2000', 'debit', 0, 'credit', (o->>'amount_paisa')::bigint,
                                                          'party', o->>'name', 'bill', (o->>'bill')::boolean)), '[]')
               from jsonb_array_elements(k->'owed') o));
  return v || jsonb_build_object('costs', k);
end $$;

create function app.record_crush_impl(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint,
  p_costs jsonb, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v         jsonb;
  v_ref     text;
  v_event   integer;
  v_seq     smallint := 0;
  v_out     jsonb;
  v_grade   int := 0;
  v_code    text;
  v_batch   integer;
  v_result  jsonb := '[]';
begin
  -- same key twice (double tap / retry on bad signal): return the first run, write nothing
  if p_idempotency_key is not null then
    select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('duplicate', true, 'event_ref', v_ref);
    end if;
  end if;

  v := app.crush_values_with_costs(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, p_costs);

  insert into app.events (event_ref, event_type, occurred_on, description, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'process_run', p_occurred_on,
          'Crush run: ' || (p_input_qty_grams / 1000.0)::numeric(12,1) || ' kg of ' || p_input_batch_code ||
          ' -> ' || ((v->>'output_grams')::bigint / 1000.0)::numeric(12,1) || ' kg good salt, ' ||
          (p_wastage_grams / 1000.0)::numeric(12,1) || ' kg loss (in the cost)' ||
          coalesce('. Crushing cost: ' || nullif(v->'costs'->>'words', ''), '') ||
          coalesce(' - ' || nullif(btrim(p_note), ''), ''),
          'app', p_created_by, p_idempotency_key)
  returning event_ref, id into v_ref, v_event;

  -- 1) the rock taken out, at its full value (loss absorbed)
  v_seq := v_seq + 1;
  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  values (v_event, v_seq, (v->>'input_product_id')::smallint, (v->>'input_batch_id')::integer, (v->>'location_id')::integer, 'out',
          p_input_qty_grams, -(v->>'input_value_paisa')::bigint);

  -- 2) one new batch per output, at its share of rock value + crushing cost
  for v_out in select * from jsonb_array_elements(v->'outputs') loop
    v_grade := v_grade + 1;
    v_code := p_input_batch_code || '-G' || v_grade;
    while exists (select 1 from app.batches where batch_code = v_code) loop
      v_grade := v_grade + 1;
      v_code := p_input_batch_code || '-G' || v_grade;
    end loop;
    insert into app.batches (batch_code, product_id, location_id, opened_on, note)
    values (v_code, (select id from app.products where code = v_out->>'product_code'), (v->>'location_id')::integer, p_occurred_on,
            'Crush output from ' || p_input_batch_code || coalesce(' - ' || nullif(btrim(p_note), ''), ''))
    returning id into v_batch;
    v_seq := v_seq + 1;
    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    values (v_event, v_seq, (select id from app.products where code = v_out->>'product_code'), v_batch, (v->>'location_id')::integer, 'in',
            (v_out->>'qty_grams')::bigint, (v_out->>'value_paisa')::bigint);
    v_result := v_result || jsonb_build_array((v_out - 'form') || jsonb_build_object('batch_code', v_code));
  end loop;

  -- 3) the loss: kg for reports, no value (it is inside the good salt's cost)
  if p_wastage_grams > 0 then
    v_seq := v_seq + 1;
    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    values (v_event, v_seq, (v->>'input_product_id')::smallint, (v->>'input_batch_id')::integer, (v->>'location_id')::integer, 'wastage',
            p_wastage_grams, 0);
  end if;

  -- one statement, so the balance check sees the whole entry; each 2000 line carries its supplier
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa, party_id)
  select v_event, (row_number() over (order by t.ord))::smallint, a.id, (t.o->>'debit')::bigint, (t.o->>'credit')::bigint,
         case when t.o->>'account' = '2000' then app.supplier_id(t.o->>'party', case when (t.o->>'bill')::boolean then '5100' end) end
    from jsonb_array_elements(v->'lines') with ordinality t(o, ord)
    join app.accounts a on a.code = t.o->>'account';

  return jsonb_build_object('event_ref', v_ref, 'input_batch', p_input_batch_code, 'input_value_paisa', (v->>'input_value_paisa')::bigint,
    'cost_paisa', (v->'costs'->>'total_paisa')::bigint, 'pool_paisa', (v->>'pool_paisa')::bigint, 'output_grams', (v->>'output_grams')::bigint,
    'wastage_grams', p_wastage_grams, 'outputs', v_result);
end $$;

create function public.record_crush(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint,
  p_costs jsonb, p_occurred_on date, p_note text default null, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return app.record_crush_impl(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, p_costs, p_occurred_on, p_note,
                               app.require_user(), p_idempotency_key);
end $$;

-- The screen's answer before Save: the same figures, nothing written.
create function public.crush_preview(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint, p_costs jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.require_user();
  return app.crush_values_with_costs(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, p_costs)
         - 'input_product_id' - 'input_batch_id' - 'location_id';
end $$;

-- one way to save a crush: the old single "paid now / credit" functions go
drop function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text, text);
drop function app.record_process_run_impl(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid, text, text);
drop function public.crush_run_preview(text, bigint, jsonb, bigint, bigint, boolean);

-- 4 ----------------------------------------------------------------------------------------------------------------
create function app.supplier_owed(p_party_id integer) returns bigint language sql stable set search_path = '' as $$
  select coalesce(sum(l.credit_paisa - l.debit_paisa), 0)::bigint from app.ledger_entries l where l.party_id = p_party_id
$$;

create function app.pay_supplier_impl(p_party_id integer, p_amount_paisa bigint, p_occurred_on date, p_note text,
                                      p_user uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_party app.parties%rowtype;
  v_ref   text;
  v_id    integer;
  v_owed  bigint;
  v_debt  bigint;
  v_extra bigint;
begin
  if p_idempotency_key is not null then
    select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('duplicate', true, 'event_ref', v_ref);
    end if;
  end if;
  select * into v_party from app.parties p where p.id = p_party_id and p.kind = 'supplier' for update;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown supplier' using errcode = 'check_violation';
  end if;
  if p_amount_paisa is null or p_amount_paisa <= 0 then
    raise exception 'INVARIANT VIOLATION: payment amount must be positive' using errcode = 'check_violation';
  end if;
  v_owed := greatest(app.supplier_owed(v_party.id), 0);
  v_debt := least(v_owed, p_amount_paisa);
  v_extra := p_amount_paisa - v_debt;
  if v_extra > 0 and v_party.extra_to_account is null then
    raise exception 'INVARIANT VIOLATION: Rs % is more than we owe % (Rs %) - pay at most Rs %',
      (p_amount_paisa / 100.0)::numeric(14,2), v_party.name, (v_owed / 100.0)::numeric(14,2), (v_owed / 100.0)::numeric(14,2)
      using errcode = 'check_violation';
  end if;

  v_ref := app.next_event_ref();
  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
  values (v_ref, 'purchase_payment', p_occurred_on,
          'Paid ' || v_party.name || ' Rs ' || (p_amount_paisa / 100.0)::numeric(14,2)
            || case when v_extra > 0 then ' (Rs ' || (v_debt / 100.0)::numeric(14,2) || ' cleared what we owed, Rs '
                                          || (v_extra / 100.0)::numeric(14,2) || ' extra to ' || (select a.name from app.accounts a where a.code = v_party.extra_to_account) || ')'
                    else '' end
            || coalesce(' - ' || nullif(btrim(p_note), ''), ''),
          'supplier', v_party.id, v_party.name, 'app', p_user, p_idempotency_key)
  returning id into v_id;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa, party_id)
  select v_id, (row_number() over (order by x.seq))::smallint, a.id, x.dr, x.cr, x.party
    from (values (1, '2000', v_debt, 0::bigint, v_party.id),
                 (2, v_party.extra_to_account, v_extra, 0::bigint, null::integer),
                 (3, '1000', 0::bigint, p_amount_paisa, null::integer)) x(seq, code, dr, cr, party)
    join app.accounts a on a.code = x.code
   where x.dr > 0 or x.cr > 0;

  return jsonb_build_object('event_ref', v_ref, 'supplier', v_party.name, 'paid_paisa', p_amount_paisa, 'cleared_paisa', v_debt,
                            'extra_paisa', v_extra, 'extra_account', case when v_extra > 0 then v_party.extra_to_account end,
                            'owed_after_paisa', v_owed - v_debt);
end $$;

create function public.pay_supplier(p_party_id integer, p_amount_paisa bigint, p_occurred_on date, p_note text default null,
                                    p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return app.pay_supplier_impl(p_party_id, p_amount_paisa, p_occurred_on, p_note, app.require_user(), p_idempotency_key);
end $$;

-- A bill estimate that was more than the real bill: remove what is left from 2000 and lower the bill's expense.
create function app.clear_supplier_leftover_impl(p_party_id integer, p_occurred_on date, p_reason text, p_user uuid, p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_party app.parties%rowtype;
  v_ref   text;
  v_id    integer;
  v_owed  bigint;
begin
  if p_idempotency_key is not null then
    select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('duplicate', true, 'event_ref', v_ref);
    end if;
  end if;
  if app.reason_problem(p_reason) is not null then
    raise exception 'INVARIANT VIOLATION: %', app.reason_problem(p_reason) using errcode = 'check_violation';
  end if;
  select * into v_party from app.parties p where p.id = p_party_id and p.kind = 'supplier' for update;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown supplier' using errcode = 'check_violation';
  end if;
  if v_party.extra_to_account is null then
    raise exception 'INVARIANT VIOLATION: only a bill estimate (like electricity) can be cleared - pay % instead', v_party.name using errcode = 'check_violation';
  end if;
  v_owed := app.supplier_owed(v_party.id);
  if v_owed <= 0 then
    raise exception 'INVARIANT VIOLATION: nothing is left owed to %', v_party.name using errcode = 'check_violation';
  end if;

  v_ref := app.next_event_ref();
  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
  values (v_ref, 'other', p_occurred_on,
          'Leftover estimate cleared: ' || v_party.name || ' Rs ' || (v_owed / 100.0)::numeric(14,2) || ' - ' || btrim(p_reason),
          'supplier', v_party.id, v_party.name, 'app', p_user, p_idempotency_key)
  returning id into v_id;
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa, party_id)
  select v_id, x.seq, a.id, x.dr, x.cr, x.party
    from (values (1::smallint, '2000', v_owed, 0::bigint, v_party.id),
                 (2::smallint, v_party.extra_to_account, 0::bigint, v_owed, null::integer)) x(seq, code, dr, cr, party)
    join app.accounts a on a.code = x.code;
  return jsonb_build_object('event_ref', v_ref, 'supplier', v_party.name, 'cleared_paisa', v_owed, 'account', v_party.extra_to_account);
end $$;

create function public.clear_supplier_leftover(p_party_id integer, p_occurred_on date, p_reason text, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return app.clear_supplier_leftover_impl(p_party_id, p_occurred_on, p_reason, app.require_user(), p_idempotency_key);
end $$;

-- 5 ----------------------------------------------------------------------------------------------------------------
create view public.v_supplier_balances with (security_invoker = true) as
select p.id as party_id, p.party_ref, p.name, p.extra_to_account,
       coalesce(sum(l.credit_paisa - l.debit_paisa), 0)::bigint as owed_paisa,
       max(e.occurred_on) filter (where l.credit_paisa > 0) as last_owed_on,
       max(e.occurred_on) filter (where l.debit_paisa > 0) as last_paid_on
  from app.parties p
  join app.ledger_entries l on l.party_id = p.id
  join app.events e on e.id = l.event_id
 where p.kind = 'supplier'
 group by p.id, p.party_ref, p.name, p.extra_to_account;

-- delete / restore: never leave a supplier owed below 0 (paid more than owed)
do $m$
declare
  v_def text := pg_get_functiondef('app.check_books_after_change(text)'::regprocedure);
  v_old constant text := $o$  select string_agg(p.name, ', ') into v_bad from app.parties p
   where (select coalesce(sum(case when c.direction = 'received' then c.amount_paisa else -c.amount_paisa end), 0)$o$;
begin
  if position(v_old in v_def) = 0 then
    raise exception 'crush costs: check_books_after_change advance check not found - function changed, migration stopped';
  end if;
  execute replace(v_def, v_old, $n$  select string_agg(p.name, ', ') into v_bad from app.parties p
   where p.kind = 'supplier' and app.supplier_owed(p.id) < 0;
  if v_bad is not null then
    raise exception 'Cannot %: we would have paid % more than we owe. Nothing was changed.', p_what, v_bad using errcode = 'check_violation';
  end if;
$n$ || v_old);
end $m$;

revoke all on function app.assert_supplier_line_linked(), app.supplier_id(text, text), app.crush_cost_lines(jsonb),
  app.crush_values_with_costs(text, bigint, jsonb, bigint, jsonb),
  app.record_crush_impl(text, bigint, jsonb, bigint, jsonb, date, text, uuid, text), app.supplier_owed(integer),
  app.pay_supplier_impl(integer, bigint, date, text, uuid, text), app.clear_supplier_leftover_impl(integer, date, text, uuid, text)
  from public, anon, authenticated;
revoke all on function public.record_crush(text, bigint, jsonb, bigint, jsonb, date, text, text),
  public.crush_preview(text, bigint, jsonb, bigint, jsonb), public.pay_supplier(integer, bigint, date, text, text),
  public.clear_supplier_leftover(integer, date, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_crush(text, bigint, jsonb, bigint, jsonb, date, text, text),
  public.crush_preview(text, bigint, jsonb, bigint, jsonb), public.pay_supplier(integer, bigint, date, text, text),
  public.clear_supplier_leftover(integer, date, text, text)
  to authenticated;
revoke all on public.v_supplier_balances from public, anon;
grant select on public.v_supplier_balances to authenticated, service_role;
