-- Task 2: login allowlist. Links Supabase Auth users to app.users; adds read access for
-- signed-in allowlisted users alongside the existing anon policies (anon is removed in Task 3).
-- No financial rows are touched. created_by on existing entries is never changed.

-- A1: link column
alter table app.users add column if not exists auth_user_id uuid unique;

-- A2: correct display names/roles (ids unchanged)
update app.users set name = 'Rao Aosaf (Operator)', role = 'operator'
 where id = '11111111-1111-1111-1111-111111111111';
update app.users set name = 'M. Shafiq Shaheen (Owner)'
 where id = '22222222-2222-2222-2222-222222222222';

-- A3: single allowlist check used by every policy
create or replace function app.is_allowed_user()
returns boolean
language sql stable security definer
set search_path = app
as $$
  select exists (select 1 from app.users where auth_user_id = auth.uid() and is_active)
$$;
revoke execute on function app.is_allowed_user() from public, anon;
grant execute on function app.is_allowed_user() to authenticated;

-- A4: the signed-in person's own app.users row (nothing else)
create or replace function public.current_app_user()
returns jsonb
language sql stable security definer
set search_path = app
as $$
  select jsonb_build_object('id', id, 'name', name, 'role', role)
  from app.users where auth_user_id = auth.uid() and is_active
$$;
revoke execute on function public.current_app_user() from public, anon;
grant execute on function public.current_app_user() to authenticated;

-- A5: read access for signed-in allowlisted users on the tables that were anon-only
do $$
declare t text;
begin
  foreach t in array array['accounts','batches','events','ledger_entries','locations','movements',
                           'products','review_queue','stg_excel_cash','users'] loop
    execute format('drop policy if exists auth_read on app.%I', t);
    execute format('create policy auth_read on app.%I for select to authenticated using (app.is_allowed_user())', t);
  end loop;
end $$;

-- A6: record_udhaar_sale no longer credits a missing created_by to 1111... (default -> NULL; body unchanged)
CREATE OR REPLACE FUNCTION public.record_udhaar_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint DEFAULT 0, p_customer_phone text DEFAULT NULL::text, p_occurred_on date DEFAULT CURRENT_DATE, p_note text DEFAULT NULL::text, p_idempotency_key text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid, p_location_code text DEFAULT 'KHANEWAL_PLANT'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sale jsonb;
  v_sale_ref text;
  v_items jsonb := '[]'::jsonb;
  v_item jsonb;
  v_dispatch jsonb;
  i int;
begin
  -- Sale gets the RAW items: record_sale now understands qty_kg/qty_grams AND
  -- line_total_paisa (exact revenue, no per-kg rounding loss).
  v_sale := public.record_sale(p_party, p_items, p_cash_received_paisa, p_customer_phone,
                               p_occurred_on, p_note, p_idempotency_key, p_created_by);
  v_sale_ref := v_sale ->> 'sale_ref';
  if coalesce((v_sale ->> 'duplicate')::boolean, false) then
    return jsonb_build_object('duplicate', true, 'sale_ref', v_sale_ref, 'sale', v_sale);
  end if;

  -- Dispatch items: normalize qty to qty_kg, derive per-kg price from line_total,
  -- inject default location (dispatch needs an explicit location).
  for i in 0 .. jsonb_array_length(p_items) - 1 loop
    v_item := p_items -> i;
    if not (v_item ? 'qty_kg') then
      v_item := jsonb_set(v_item, '{qty_kg}', to_jsonb((v_item ->> 'qty_grams')::numeric / 1000.0));
    end if;
    if v_item ? 'line_total_paisa' then
      v_item := jsonb_set(v_item, '{unit_price_paisa_per_kg}',
        to_jsonb(round((v_item ->> 'line_total_paisa')::numeric * 1000 / ((v_item ->> 'qty_kg')::numeric * 1000))::bigint));
    end if;
    if not (v_item ? 'location_code') then
      v_item := jsonb_set(v_item, '{location_code}', to_jsonb(p_location_code));
    end if;
    v_items := v_items || jsonb_build_array(jsonb_strip_nulls(v_item - 'line_total_paisa'));
  end loop;

  v_dispatch := public.record_dispatch(v_sale_ref, v_items, p_occurred_on, p_note,
    case when p_idempotency_key is null then null else p_idempotency_key || '-dispatch' end, p_created_by);

  return jsonb_build_object('sale_ref', v_sale_ref, 'dispatch_ref', v_dispatch ->> 'dispatch_ref',
    'revenue_paisa', v_sale ->> 'revenue_paisa', 'cash_paisa', v_sale ->> 'cash_paisa',
    'ar_paisa', v_sale ->> 'ar_paisa', 'cogs_paisa', v_dispatch ->> 'cogs_paisa',
    'party_created', v_sale ->> 'party_created', 'duplicate', false);
end
$function$;
