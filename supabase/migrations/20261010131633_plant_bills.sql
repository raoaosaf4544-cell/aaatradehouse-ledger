-- Real plant bills and a monthly check of the crushing rate (owner-approved 10 Oct 2026).
--   1. Plant expense accounts 5410-5440. A crush charges the salt a standard plant cost (Cr 5490); the real bills
--      (electricity, workers, diesel, repairs) are paid here. P&L plant cost = 5410..5440 net of 5490.
--   2. post_event: a Suppliers (2000) line may name its supplier ("party") - the save links it on the line, so a plant
--      bill can be put on credit and later paid from Pay supplier. A 2000 line without a supplier is still refused.
--   3. public.v_plant_rate_check: per month, actual plant bills vs plant cost charged to salt, rock crushed and the
--      rate that would have covered the bills. Nothing changes the rate by itself; Rao decides.

insert into app.accounts (code, name, type, kind) values
  ('5410', 'Plant electricity', 'expense', 'general'),
  ('5420', 'Plant labour', 'expense', 'general'),
  ('5430', 'Plant diesel & repairs', 'expense', 'general'),
  ('5440', 'Plant other', 'expense', 'general');

create or replace function app.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb,
  p_party_type text default null, p_party_name text default null, p_created_by uuid default null, p_idempotency_key text default null)
returns text language plpgsql security definer set search_path to 'app' as $function$
declare
  v_ref text;
  v_event_id integer;
  v_line jsonb;
  v_dr bigint;
  v_cr bigint;
  v_total_dr bigint := 0;
  v_total_cr bigint := 0;
begin
  -- same key twice (double tap / retry on bad signal): return the first entry, write nothing
  if p_idempotency_key is not null then
    select event_ref into v_ref from app.events where idempotency_key = p_idempotency_key;
    if found then
      return v_ref;
    end if;
  end if;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'INVARIANT VIOLATION: at least two ledger lines are required'
      using errcode = 'check_violation';
  end if;

  for v_line in select * from jsonb_array_elements(p_lines) loop
    if (select id from app.accounts where code = v_line->>'account') is null then
      raise exception 'INVARIANT VIOLATION: unknown account code %', v_line->>'account'
        using errcode = 'check_violation';
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
    raise exception 'INVARIANT VIOLATION: posting not balanced (debit %, credit % paisa)', v_total_dr, v_total_cr
      using errcode = 'check_violation';
  end if;

  v_ref := app.next_event_ref();

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by, idempotency_key)
  values (v_ref, p_event_type, p_occurred_on, p_description, p_party_type, p_party_name, 'app', p_created_by, p_idempotency_key)
  returning id into v_event_id;

  -- a Suppliers (2000) line carries its supplier (named in "party"; a new name becomes a supplier)
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa, party_id)
  select v_event_id, (row_number() over (order by t.ord))::smallint, a.id,
         coalesce((t.line->>'debit')::bigint, 0), coalesce((t.line->>'credit')::bigint, 0),
         case when t.line->>'account' = '2000' then app.supplier_id(t.line->>'party') end
  from jsonb_array_elements(p_lines) with ordinality t(line, ord)
  join app.accounts a on a.code = t.line->>'account';

  return v_ref;
end $function$;

create view public.v_plant_rate_check with (security_invoker = true) as
with money as (
  select date_trunc('month', e.occurred_on)::date as month,
         sum(case when a.code <> '5490' then le.debit_paisa - le.credit_paisa else 0 end) as bills,
         sum(case when a.code = '5490' then le.credit_paisa - le.debit_paisa else 0 end) as charged
    from app.ledger_entries le
    join app.accounts a on a.id = le.account_id and a.code in ('5410', '5420', '5430', '5440', '5490')
    join app.events e on e.id = le.event_id
   group by 1),
rock as (
  select date_trunc('month', e.occurred_on)::date as month, sum(m.qty_grams) as grams
    from app.movements m join app.events e on e.id = m.event_id
   where e.event_type = 'process_run' and m.direction = 'out'
   group by 1)
select coalesce(money.month, rock.month) as month,
       coalesce(money.bills, 0)::bigint as actual_bills_paisa,
       coalesce(money.charged, 0)::bigint as charged_paisa,
       -- more than 0 = under-charged (bills bigger than what the salt was charged); less than 0 = over-charged
       (coalesce(money.bills, 0) - coalesce(money.charged, 0))::bigint as under_charged_paisa,
       coalesce(rock.grams, 0)::bigint as rock_crushed_grams,
       case when coalesce(rock.grams, 0) > 0 then round(coalesce(money.bills, 0) * 1000.0 / rock.grams)::bigint end as suggested_rate_paisa_per_kg
  from money full join rock on rock.month = money.month;

revoke all on public.v_plant_rate_check from public, anon;
grant select on public.v_plant_rate_check to authenticated, service_role;
