-- ============ RLS hardening + public read surface ============
-- Match the established pattern: tables are SELECT-only under RLS; writes go through security-definer RPCs.
do $$
declare t text;
begin
  foreach t in array array['sales','sale_lines','dispatches','dispatch_allocations','customer_advances','batch_cost_components'] loop
    execute format('alter table app.%I enable row level security', t);
    execute format('drop policy if exists read_only on app.%I', t);
    execute format('create policy read_only on app.%I for select to anon, authenticated using (true)', t);
  end loop;
end $$;

-- Public read surface (invoker-securing like the existing v_* views)
create or replace view public.v_sales with (security_invoker = true) as
  select * from app.v_sales;
create or replace view public.v_batch_costs with (security_invoker = true) as
  select * from app.v_batch_costs;
create or replace view public.v_dispatch_allocations with (security_invoker = true) as
  select * from app.v_dispatch_allocations;

create or replace view public.v_advances with (security_invoker = true) as
select pt.id as party_id, pt.party_ref, pt.name as customer_name, pt.phone,
       coalesce(sum(case when a.direction = 'received' then a.amount_paisa else -a.amount_paisa end), 0)::bigint as advance_balance_paisa
from app.parties pt
left join app.customer_advances a on a.party_id = pt.id
where pt.kind = 'customer'
group by pt.id, pt.party_ref, pt.name, pt.phone;

create or replace view public.v_customers with (security_invoker = true) as
select pt.id as party_id, pt.party_ref, pt.name, pt.phone, pt.is_active, pt.created_at
from app.parties pt
where pt.kind = 'customer';

grant select on public.v_sales, public.v_batch_costs, public.v_dispatch_allocations,
                public.v_advances, public.v_customers to anon, authenticated;

-- public wrapper for the advance RPC (app schema is not reachable by PostgREST)
create or replace function public.record_customer_advance(
  p_customer text,
  p_amount_paisa bigint,
  p_occurred_on date default current_date,
  p_note text default null,
  p_idempotency_key text default null,
  p_created_by uuid default null
) returns jsonb language sql security definer set search_path = 'app' as $fn$
  select app.record_advance(p_customer, p_amount_paisa, p_occurred_on, p_note, p_idempotency_key, p_created_by)
$fn$;
grant execute on function public.record_customer_advance(text, bigint, date, text, text, uuid) to anon, authenticated;