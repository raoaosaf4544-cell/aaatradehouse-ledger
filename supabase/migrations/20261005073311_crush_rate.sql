-- One crushing rate per kg of rock (owner-approved 5 Oct 2026). We crush in our own plant: nobody is paid per kg;
-- the plant's real bills (electricity, workers, diesel, repairs) are paid separately, on their own dates. So a crush
-- charges a standard plant cost = rate x rock kg in, credited to a contra-expense account:
--   Dr output stock (1210)  rock value used + plant cost   (split by weight; loss absorbed, as before)
--   Cr rock stock (1200)    rock value used
--   Cr 5490 Plant cost charged to salt   plant cost
-- No cash, no supplier on a crush. The monthly "plant rate check" compares 5490 with the real plant bills.
-- Replaces this morning's cost-line version (record_crush / crush_preview with p_costs); there are no crush runs in
-- the books. Suppliers / pay_supplier / v_supplier_balances stay (bills on credit use them).

insert into app.accounts (code, name, type, kind) values ('5490', 'Plant cost charged to salt', 'expense', 'general');

drop function public.record_crush(text, bigint, jsonb, bigint, jsonb, date, text, text);
drop function public.crush_preview(text, bigint, jsonb, bigint, jsonb);
drop function app.record_crush_impl(text, bigint, jsonb, bigint, jsonb, date, text, uuid, text);
drop function app.crush_values_with_costs(text, bigint, jsonb, bigint, jsonb);
drop function app.crush_cost_lines(jsonb);

-- The crush figures with the plant cost credited to 5490 instead of cash.
create function app.crush_values_with_rate(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb,
                                           p_wastage_grams bigint, p_rate_paisa_per_kg bigint) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_plant bigint;
  v jsonb;
begin
  if p_rate_paisa_per_kg is null or p_rate_paisa_per_kg < 0 then
    raise exception 'INVARIANT VIOLATION: the crushing rate must be 0 or more' using errcode = 'check_violation';
  end if;
  v_plant := round(p_rate_paisa_per_kg::numeric * coalesce(p_input_qty_grams, 0) / 1000);
  v := app.crush_run_values(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, v_plant, true);
  v := jsonb_set(v, '{lines}',
         (select coalesce(jsonb_agg(l order by ord), '[]') from jsonb_array_elements(v->'lines') with ordinality x(l, ord) where l->>'account' <> '1000')
         || case when v_plant > 0 then jsonb_build_array(jsonb_build_object('account', '5490', 'debit', 0, 'credit', v_plant)) else '[]' end);
  return v || jsonb_build_object('rate_paisa_per_kg', p_rate_paisa_per_kg, 'plant_cost_paisa', v_plant);
end $$;

create function app.record_crush_impl(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint,
  p_rate_paisa_per_kg bigint, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text)
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

  v := app.crush_values_with_rate(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, p_rate_paisa_per_kg);

  insert into app.events (event_ref, event_type, occurred_on, description, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'process_run', p_occurred_on,
          'Crush run: ' || (p_input_qty_grams / 1000.0)::numeric(12,1) || ' kg of ' || p_input_batch_code ||
          ' -> ' || ((v->>'output_grams')::bigint / 1000.0)::numeric(12,1) || ' kg good salt, ' ||
          (p_wastage_grams / 1000.0)::numeric(12,1) || ' kg loss (in the cost). Plant cost Rs ' ||
          ((v->>'plant_cost_paisa')::bigint / 100.0)::numeric(14,2) || ' at Rs ' || (p_rate_paisa_per_kg / 100.0)::numeric(10,2) || '/kg of rock' ||
          coalesce(' - ' || nullif(btrim(p_note), ''), ''),
          'app', p_created_by, p_idempotency_key)
  returning event_ref, id into v_ref, v_event;

  -- 1) the rock taken out, at its full value (loss absorbed)
  v_seq := v_seq + 1;
  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  values (v_event, v_seq, (v->>'input_product_id')::smallint, (v->>'input_batch_id')::integer, (v->>'location_id')::integer, 'out',
          p_input_qty_grams, -(v->>'input_value_paisa')::bigint);

  -- 2) one new batch per output, at its share of rock value + plant cost
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

  -- one statement, so the balance check sees the whole entry
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event, (row_number() over (order by t.ord))::smallint, a.id, (t.o->>'debit')::bigint, (t.o->>'credit')::bigint
    from jsonb_array_elements(v->'lines') with ordinality t(o, ord)
    join app.accounts a on a.code = t.o->>'account';

  return jsonb_build_object('event_ref', v_ref, 'input_batch', p_input_batch_code, 'input_value_paisa', (v->>'input_value_paisa')::bigint,
    'plant_cost_paisa', (v->>'plant_cost_paisa')::bigint, 'pool_paisa', (v->>'pool_paisa')::bigint, 'output_grams', (v->>'output_grams')::bigint,
    'wastage_grams', p_wastage_grams, 'outputs', v_result);
end $$;

create function public.record_crush(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint,
  p_rate_paisa_per_kg bigint, p_occurred_on date, p_note text default null, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  return app.record_crush_impl(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, p_rate_paisa_per_kg, p_occurred_on,
                               p_note, app.require_user(), p_idempotency_key);
end $$;

-- The screen's answer before Save: the same figures, nothing written.
create function public.crush_preview(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint,
  p_rate_paisa_per_kg bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform app.require_user();
  return app.crush_values_with_rate(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams, p_rate_paisa_per_kg)
         - 'input_product_id' - 'input_batch_id' - 'location_id';
end $$;

-- The rate used on the last crush (the screen starts from it): plant cost charged / rock kg in.
create view public.v_last_crush_rate with (security_invoker = true) as
select e.event_ref, e.occurred_on,
       round(coalesce((select sum(le.credit_paisa - le.debit_paisa) from app.ledger_entries le join app.accounts a on a.id = le.account_id
                        where le.event_id = e.id and a.code = '5490'), 0)::numeric * 1000
             / nullif((select sum(m.qty_grams) from app.movements m where m.event_id = e.id and m.direction = 'out'), 0))::bigint as rate_paisa_per_kg
  from app.events e
 where e.event_type = 'process_run'
 order by e.occurred_on desc, e.id desc
 limit 1;

revoke all on function app.crush_values_with_rate(text, bigint, jsonb, bigint, bigint),
  app.record_crush_impl(text, bigint, jsonb, bigint, bigint, date, text, uuid, text) from public, anon, authenticated;
revoke all on function public.record_crush(text, bigint, jsonb, bigint, bigint, date, text, text),
  public.crush_preview(text, bigint, jsonb, bigint, bigint) from public, anon, authenticated, service_role;
grant execute on function public.record_crush(text, bigint, jsonb, bigint, bigint, date, text, text),
  public.crush_preview(text, bigint, jsonb, bigint, bigint) to authenticated;
revoke all on public.v_last_crush_rate from public, anon;
grant select on public.v_last_crush_rate to authenticated, service_role;
