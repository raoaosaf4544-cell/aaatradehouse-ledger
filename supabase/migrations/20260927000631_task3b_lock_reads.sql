-- Task 3B: lock reads. Anon reads nothing; signed-in allowlisted users read everything the app needs.
-- RLS now applies all the way down: every app/public view runs as the caller (security_invoker).

-- B1: replace every anon/public read policy with the allowlisted auth_read policy.
do $$
declare t text;
begin
  foreach t in array array['accounts','batches','events','ledger_entries','locations','movements',
                           'products','review_queue','stg_excel_cash','users'] loop
    execute format('drop policy if exists anon_read on app.%I', t);
  end loop;
  foreach t in array array['sales','sale_lines','dispatches','dispatch_allocations','customer_advances','batch_cost_components'] loop
    execute format('drop policy if exists read_only on app.%I', t);
  end loop;
  drop policy if exists "parties read" on app.parties;
  foreach t in array array['sales','sale_lines','dispatches','dispatch_allocations','customer_advances',
                           'batch_cost_components','parties'] loop
    execute format('drop policy if exists auth_read on app.%I', t);
    execute format('create policy auth_read on app.%I for select to authenticated using (app.is_allowed_user())', t);
  end loop;
end $$;

-- B2: anon gets nothing in the ledger schemas; authenticated keeps SELECT only on the public views.
revoke all on all tables in schema app from anon;
revoke all on all sequences in schema app from anon;
revoke usage on schema app from anon;
revoke all on public.v_account_balances, public.v_accounts, public.v_advances, public.v_batch_costs, public.v_batches,
  public.v_customers, public.v_debtors, public.v_dispatch_allocations, public.v_events_with_party, public.v_ledger_lines,
  public.v_locations, public.v_parties, public.v_products, public.v_review_queue, public.v_sales, public.v_stock_onhand
  from anon;
revoke insert, update, delete, truncate, references, trigger, maintain on public.v_account_balances, public.v_accounts,
  public.v_advances, public.v_batch_costs, public.v_batches, public.v_customers, public.v_debtors,
  public.v_dispatch_allocations, public.v_events_with_party, public.v_ledger_lines, public.v_locations, public.v_parties,
  public.v_products, public.v_review_queue, public.v_sales, public.v_stock_onhand
  from authenticated, service_role;

-- Future objects created by postgres are not granted to anon (or executable by PUBLIC).
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;
alter default privileges for role postgres in schema app revoke all on tables from anon;
alter default privileges for role postgres revoke execute on functions from public;

-- B3: views run as the caller so RLS applies to the underlying tables.
alter view public.v_debtors set (security_invoker = true);
alter view public.v_parties set (security_invoker = true);
alter view app.v_account_balances set (security_invoker = true);
alter view app.v_batch_costs set (security_invoker = true);
alter view app.v_batches set (security_invoker = true);
alter view app.v_cash_summary set (security_invoker = true);
alter view app.v_debtors set (security_invoker = true);
alter view app.v_dispatch_allocations set (security_invoker = true);
alter view app.v_events_with_party set (security_invoker = true);
alter view app.v_sales set (security_invoker = true);
alter view app.v_stock_onhand set (security_invoker = true);
