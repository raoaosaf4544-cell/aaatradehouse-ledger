-- Task 3A: lock the money functions.
-- * app.require_user(): the signed-in person's app.users.id, or "Not authorised".
-- * The write functions move to app.*_impl (bodies unchanged) and are callable only by postgres.
--   Thin public wrappers with the same names/arguments guard the call and pass the SERVER-derived
--   created_by (whatever the client sends as p_created_by is ignored).
-- * EXECUTE revoked from PUBLIC/anon on every app/public function; only the RPCs the app uses are
--   granted to authenticated.
-- * search_path pinned on the functions flagged by the advisors.

create or replace function app.require_user()
returns uuid
language plpgsql stable security definer
set search_path = app
as $$
declare v_id uuid;
begin
  select id into v_id from app.users where auth_user_id = auth.uid() and is_active;
  if v_id is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  return v_id;
end $$;

-- Move implementations out of the API schema (bodies untouched).
alter function public.create_customer(text, text, text) set schema app;
alter function app.create_customer(text, text, text) rename to create_customer_impl;
alter function public.record_customer_payment(text, bigint, date, text, uuid, text) set schema app;
alter function app.record_customer_payment(text, bigint, date, text, uuid, text) rename to record_customer_payment_impl;
alter function public.record_dispatch(text, jsonb, date, text, text, uuid) set schema app;
alter function app.record_dispatch(text, jsonb, date, text, text, uuid) rename to record_dispatch_impl;
alter function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid) set schema app;
alter function app.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid) rename to record_process_run_impl;
alter function public.record_purchase(text, text, text, bigint, bigint, boolean, date, text, uuid, text, jsonb) set schema app;
alter function app.record_purchase(text, text, text, bigint, bigint, boolean, date, text, uuid, text, jsonb) rename to record_purchase_impl;
alter function public.record_sale(text, jsonb, bigint, text, date, text, text, uuid) set schema app;
alter function app.record_sale(text, jsonb, bigint, text, date, text, text, uuid) rename to record_sale_impl;
alter function public.record_udhaar_sale(text, jsonb, bigint, text, date, text, text, uuid, text) set schema app;
alter function app.record_udhaar_sale(text, jsonb, bigint, text, date, text, text, uuid, text) rename to record_udhaar_sale_impl;
alter function public.resolve_review_item(integer, text, boolean) set schema app;
alter function app.resolve_review_item(integer, text, boolean) rename to resolve_review_item_impl;
alter function public.suggest_sale_price(text, text, numeric) set schema app;
alter function app.suggest_sale_price(text, text, numeric) rename to suggest_sale_price_impl;

-- Guarded public wrappers (same names, arguments and defaults as before).
create function public.create_customer(p_name text, p_phone text default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  perform app.require_user();
  return app.create_customer_impl(p_name, p_phone, p_note);
end $$;

create function public.record_customer_payment(p_customer text, p_amount_paisa bigint, p_occurred_on date default current_date,
  p_note text default null, p_created_by uuid default null, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.record_customer_payment_impl(p_customer, p_amount_paisa, p_occurred_on, p_note, app.require_user(), p_idempotency_key);
end $$;

create function public.record_dispatch(p_sale_ref text, p_lines jsonb, p_occurred_on date default current_date,
  p_note text default null, p_idempotency_key text default null, p_created_by uuid default null)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.record_dispatch_impl(p_sale_ref, p_lines, p_occurred_on, p_note, p_idempotency_key, app.require_user());
end $$;

create function public.record_process_run(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint,
  p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text default null, p_created_by uuid default null)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.record_process_run_impl(p_input_batch_code, p_input_qty_grams, p_outputs, p_wastage_grams,
    p_conversion_cost_paisa, p_pay_cash, p_occurred_on, p_note, app.require_user());
end $$;

create function public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint,
  p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text default null, p_created_by uuid default null,
  p_idempotency_key text default null, p_cost_components jsonb default null)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.record_purchase_impl(p_supplier, p_product_code, p_location_code, p_qty_grams, p_landed_cost_paisa,
    p_pay_cash, p_occurred_on, p_note, app.require_user(), p_idempotency_key, p_cost_components);
end $$;

create function public.record_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text,
  p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.record_sale_impl(p_party, p_items, p_cash_received_paisa, p_customer_phone, p_occurred_on, p_note,
    p_idempotency_key, app.require_user());
end $$;

create function public.record_udhaar_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint default 0,
  p_customer_phone text default null, p_occurred_on date default current_date, p_note text default null,
  p_idempotency_key text default null, p_created_by uuid default null, p_location_code text default 'KHANEWAL_PLANT')
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.record_udhaar_sale_impl(p_party, p_items, p_cash_received_paisa, p_customer_phone, p_occurred_on, p_note,
    p_idempotency_key, app.require_user(), p_location_code);
end $$;

create function public.resolve_review_item(p_id integer, p_note text, p_dismissed boolean default false)
returns void language plpgsql security definer set search_path = app as $$
begin
  perform app.require_user();
  perform app.resolve_review_item_impl(p_id, p_note, p_dismissed);
end $$;

create function public.suggest_sale_price(p_product_code text, p_location_code text, p_target_margin_pct numeric default 15)
returns jsonb language plpgsql stable security definer set search_path = app as $$
begin
  perform app.require_user();
  return app.suggest_sale_price_impl(p_product_code, p_location_code, p_target_margin_pct);
end $$;

-- Existing public wrappers: add the guard and server-side created_by.
create or replace function public.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb,
  p_party_type text default null, p_party_name text default null, p_created_by uuid default null)
returns text language plpgsql security definer set search_path = app as $$
begin
  return app.post_event(p_event_type, p_occurred_on, p_description, p_lines, p_party_type, p_party_name, app.require_user());
end $$;

create or replace function public.record_customer_advance(p_customer text, p_amount_paisa bigint, p_occurred_on date default current_date,
  p_note text default null, p_idempotency_key text default null, p_created_by uuid default null)
returns jsonb language plpgsql security definer set search_path = app as $$
begin
  return app.record_advance(p_customer, p_amount_paisa, p_occurred_on, p_note, p_idempotency_key, app.require_user());
end $$;

-- Pin search_path (advisor: function_search_path_mutable) and on the moved udhaar impl.
alter function app.assert_cash_nonnegative() set search_path = app;
alter function app.assert_event_balanced() set search_path = app;
alter function app.assert_ledger_events_balanced() set search_path = app;
alter function app.assert_stock_nonnegative() set search_path = app;
alter function app.next_event_ref() set search_path = app;
alter function app.next_party_ref() set search_path = app;
alter function app.record_udhaar_sale_impl(text, jsonb, bigint, text, date, text, text, uuid, text) set search_path = app;

-- Execute: nobody by default; the signed-in app gets exactly what it calls.
revoke all on all functions in schema app from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
-- The old 9-argument record_purchase stays inert until 3D drops it.
revoke all on function public.record_purchase(text, text, text, bigint, bigint, boolean, date, text, uuid) from service_role;

grant execute on function app.is_allowed_user() to authenticated;            -- used by RLS policies
grant execute on function public.current_app_user() to authenticated;
grant execute on function public.post_event(text, date, text, jsonb, text, text, uuid) to authenticated;
grant execute on function public.create_customer(text, text, text) to authenticated;
grant execute on function public.record_customer_payment(text, bigint, date, text, uuid, text) to authenticated;
grant execute on function public.record_dispatch(text, jsonb, date, text, text, uuid) to authenticated;
grant execute on function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid) to authenticated;
grant execute on function public.record_purchase(text, text, text, bigint, bigint, boolean, date, text, uuid, text, jsonb) to authenticated;
grant execute on function public.record_sale(text, jsonb, bigint, text, date, text, text, uuid) to authenticated;
grant execute on function public.record_udhaar_sale(text, jsonb, bigint, text, date, text, text, uuid, text) to authenticated;
grant execute on function public.resolve_review_item(integer, text, boolean) to authenticated;
