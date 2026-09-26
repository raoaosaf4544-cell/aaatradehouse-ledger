-- Baseline of the live database (app + public schemas) as of 2026-09-27.
-- Generated from the Postgres catalog. Every statement is idempotent against the live DB:
-- functions/views/triggers use CREATE OR REPLACE, tables/sequences/indexes IF NOT EXISTS,
-- policies DROP IF EXISTS + CREATE, grants re-grant existing privileges. No behaviour change.

-- ============ 1. Schema, sequences ============
create schema if not exists app;

create sequence if not exists app.batch_ref_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1;
create sequence if not exists app.dispatch_ref_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1;
create sequence if not exists app.event_ref_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1;
create sequence if not exists app.party_ref_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1;
create sequence if not exists app.sale_ref_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1;


-- ============ 2. Tables (ledger app) ============
create table if not exists app.accounts (
  id smallint generated always as identity,
  code text not null,
  name text not null,
  type text not null,
  kind text default 'general'::text not null,
  is_system boolean default false not null,
  is_active boolean default true not null,
  constraint accounts_pkey PRIMARY KEY (id),
  constraint accounts_code_key UNIQUE (code),
  constraint accounts_kind_check CHECK ((kind = ANY (ARRAY['general'::text, 'inventory'::text, 'cash'::text, 'bank'::text, 'control'::text, 'personal'::text]))),
  constraint accounts_type_check CHECK ((type = ANY (ARRAY['asset'::text, 'liability'::text, 'equity'::text, 'income'::text, 'expense'::text])))
);

create table if not exists app.locations (
  id smallint generated always as identity,
  code text not null,
  name text not null,
  kind text default 'plant'::text not null,
  is_active boolean default true not null,
  constraint locations_pkey PRIMARY KEY (id),
  constraint locations_code_key UNIQUE (code),
  constraint locations_kind_check CHECK ((kind = ANY (ARRAY['plant'::text, 'warehouse'::text, 'office'::text, 'transit'::text])))
);

create table if not exists app.parties (
  id integer generated always as identity,
  party_ref text not null,
  name text not null,
  phone text,
  kind text default 'customer'::text not null,
  note text,
  is_active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  constraint parties_pkey PRIMARY KEY (id),
  constraint parties_party_ref_key UNIQUE (party_ref),
  constraint parties_kind_check CHECK ((kind = ANY (ARRAY['customer'::text, 'supplier'::text])))
);

create table if not exists app.products (
  id smallint generated always as identity,
  code text not null,
  name text not null,
  form text not null,
  base_unit text default 'kg'::text not null,
  is_active boolean default true not null,
  constraint products_pkey PRIMARY KEY (id),
  constraint products_code_key UNIQUE (code),
  constraint products_form_check CHECK ((form = ANY (ARRAY['raw'::text, 'bulk_processed'::text, 'packaged'::text, 'packaging_material'::text, 'other_material'::text])))
);

create table if not exists app.stg_excel_cash (
  txn_id text not null,
  occurred_on date not null,
  category text,
  description text,
  money_in_paisa bigint default 0 not null,
  money_out_paisa bigint default 0 not null,
  running_balance_paisa bigint,
  month_key text,
  constraint stg_excel_cash_pkey PRIMARY KEY (txn_id)
);

create table if not exists app.users (
  id uuid not null,
  name text not null,
  role text default 'owner'::text not null,
  is_active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  constraint users_pkey PRIMARY KEY (id),
  constraint users_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'operator'::text, 'auditor'::text])))
);

create table if not exists app.batches (
  id integer generated always as identity,
  batch_code text not null,
  product_id smallint not null,
  location_id smallint not null,
  status text default 'open'::text not null,
  opened_on date not null,
  closed_on date,
  note text,
  constraint batches_pkey PRIMARY KEY (id),
  constraint batches_batch_code_key UNIQUE (batch_code),
  constraint batches_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text]))),
  constraint batches_location_id_fkey FOREIGN KEY (location_id) REFERENCES app.locations(id),
  constraint batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES app.products(id)
);

create table if not exists app.events (
  id integer generated always as identity,
  event_ref text not null,
  event_type text not null,
  occurred_on date not null,
  description text not null,
  party_type text,
  party_name text,
  source text default 'app'::text not null,
  source_ref text,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  party_id integer,
  idempotency_key text,
  constraint events_pkey PRIMARY KEY (id),
  constraint events_event_ref_key UNIQUE (event_ref),
  constraint events_event_type_check CHECK ((event_type = ANY (ARRAY['capital_injection'::text, 'owner_drawing'::text, 'expense'::text, 'asset_purchase'::text, 'asset_disposal'::text, 'purchase'::text, 'purchase_payment'::text, 'supplier_return'::text, 'process_run'::text, 'packaging_run'::text, 'transfer'::text, 'stock_adjustment'::text, 'sale'::text, 'dispatch'::text, 'customer_return'::text, 'customer_payment'::text, 'customer_advance'::text, 'opening_inventory'::text, 'inventory_reval'::text, 'other'::text]))),
  constraint events_party_type_check CHECK ((party_type = ANY (ARRAY['customer'::text, 'supplier'::text, 'owner'::text, 'employee'::text, 'other'::text]))),
  constraint events_source_check CHECK ((source = ANY (ARRAY['excel_import'::text, 'app'::text, 'correction'::text, 'system'::text]))),
  constraint events_created_by_fkey FOREIGN KEY (created_by) REFERENCES app.users(id),
  constraint events_party_id_fkey FOREIGN KEY (party_id) REFERENCES app.parties(id)
);

create table if not exists app.review_queue (
  id integer generated always as identity,
  source text not null,
  severity text default 'needs_review'::text not null,
  title text not null,
  detail jsonb default '{}'::jsonb not null,
  source_ref text,
  status text default 'open'::text not null,
  resolution_note text,
  created_at timestamp with time zone default now() not null,
  resolved_at timestamp with time zone,
  resolved_by uuid,
  constraint review_queue_pkey PRIMARY KEY (id),
  constraint review_queue_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'needs_review'::text, 'critical'::text]))),
  constraint review_queue_source_check CHECK ((source = ANY (ARRAY['excel_import'::text, 'invariant'::text, 'app'::text, 'correction'::text]))),
  constraint review_queue_status_check CHECK ((status = ANY (ARRAY['open'::text, 'resolved'::text, 'dismissed'::text]))),
  constraint review_queue_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES app.users(id)
);

create table if not exists app.sales (
  id integer generated always as identity,
  sale_ref text not null,
  party_id integer not null,
  status text default 'invoiced'::text not null,
  occurred_on date not null,
  currency text default 'PKR'::text not null,
  fx_rate numeric(18,8) default 1 not null,
  total_revenue_paisa bigint not null,
  cash_received_paisa bigint default 0 not null,
  advance_applied_paisa bigint default 0 not null,
  ar_paisa bigint default 0 not null,
  idempotency_key text,
  note text,
  source text default 'app'::text not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  constraint sales_pkey PRIMARY KEY (id),
  constraint sales_sale_ref_key UNIQUE (sale_ref),
  constraint sales_advance_applied_paisa_check CHECK ((advance_applied_paisa >= 0)),
  constraint sales_ar_paisa_check CHECK ((ar_paisa >= 0)),
  constraint sales_cash_received_paisa_check CHECK ((cash_received_paisa >= 0)),
  constraint sales_status_check CHECK ((status = ANY (ARRAY['invoiced'::text, 'dispatched'::text]))),
  constraint sales_total_revenue_paisa_check CHECK ((total_revenue_paisa > 0)),
  constraint sales_party_id_fkey FOREIGN KEY (party_id) REFERENCES app.parties(id)
);

create table if not exists app.batch_cost_components (
  id bigint generated always as identity,
  batch_id integer not null,
  component text not null,
  amount_paisa bigint not null,
  event_id integer,
  note text,
  created_at timestamp with time zone default now() not null,
  constraint batch_cost_components_pkey PRIMARY KEY (id),
  constraint batch_cost_components_amount_paisa_check CHECK ((amount_paisa > 0)),
  constraint batch_cost_components_component_check CHECK ((component = ANY (ARRAY['purchase'::text, 'freight_inbound'::text, 'loading'::text, 'other'::text]))),
  constraint batch_cost_components_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES app.batches(id),
  constraint batch_cost_components_event_id_fkey FOREIGN KEY (event_id) REFERENCES app.events(id)
);

create table if not exists app.customer_advances (
  id bigint generated always as identity,
  event_id integer not null,
  party_id integer not null,
  direction text not null,
  amount_paisa bigint not null,
  occurred_on date not null,
  currency text default 'PKR'::text not null,
  fx_rate numeric(18,8) default 1 not null,
  idempotency_key text,
  note text,
  source text default 'app'::text not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  constraint customer_advances_pkey PRIMARY KEY (id),
  constraint customer_advances_amount_paisa_check CHECK ((amount_paisa > 0)),
  constraint customer_advances_direction_check CHECK ((direction = ANY (ARRAY['received'::text, 'applied'::text, 'refunded'::text]))),
  constraint customer_advances_event_id_fkey FOREIGN KEY (event_id) REFERENCES app.events(id),
  constraint customer_advances_party_id_fkey FOREIGN KEY (party_id) REFERENCES app.parties(id)
);

create table if not exists app.dispatches (
  id integer generated always as identity,
  dispatch_ref text not null,
  sale_id integer not null,
  occurred_on date not null,
  total_cogs_paisa bigint not null,
  idempotency_key text,
  note text,
  source text default 'app'::text not null,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  constraint dispatches_pkey PRIMARY KEY (id),
  constraint dispatches_dispatch_ref_key UNIQUE (dispatch_ref),
  constraint dispatches_total_cogs_paisa_check CHECK ((total_cogs_paisa >= 0)),
  constraint dispatches_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES app.sales(id)
);

create table if not exists app.ledger_entries (
  id bigint generated always as identity,
  event_id integer not null,
  entry_seq smallint not null,
  account_id smallint not null,
  debit_paisa bigint default 0 not null,
  credit_paisa bigint default 0 not null,
  constraint ledger_entries_pkey PRIMARY KEY (id),
  constraint ledger_entries_event_id_entry_seq_key UNIQUE (event_id, entry_seq),
  constraint ledger_entries_check CHECK ((NOT ((debit_paisa > 0) AND (credit_paisa > 0)))),
  constraint ledger_entries_check1 CHECK (((debit_paisa > 0) OR (credit_paisa > 0))),
  constraint ledger_entries_credit_paisa_check CHECK ((credit_paisa >= 0)),
  constraint ledger_entries_debit_paisa_check CHECK ((debit_paisa >= 0)),
  constraint ledger_entries_account_id_fkey FOREIGN KEY (account_id) REFERENCES app.accounts(id),
  constraint ledger_entries_event_id_fkey FOREIGN KEY (event_id) REFERENCES app.events(id)
);

create table if not exists app.movements (
  id bigint generated always as identity,
  event_id integer not null,
  movement_seq smallint not null,
  product_id smallint not null,
  batch_id integer not null,
  location_id smallint not null,
  direction text not null,
  qty_grams bigint not null,
  value_paisa bigint default 0 not null,
  constraint movements_pkey PRIMARY KEY (id),
  constraint movements_event_id_movement_seq_key UNIQUE (event_id, movement_seq),
  constraint movements_direction_check CHECK ((direction = ANY (ARRAY['in'::text, 'out'::text, 'wastage'::text]))),
  constraint movements_qty_grams_check CHECK ((qty_grams > 0)),
  constraint movements_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES app.batches(id),
  constraint movements_event_id_fkey FOREIGN KEY (event_id) REFERENCES app.events(id),
  constraint movements_location_id_fkey FOREIGN KEY (location_id) REFERENCES app.locations(id),
  constraint movements_product_id_fkey FOREIGN KEY (product_id) REFERENCES app.products(id)
);

create table if not exists app.sale_lines (
  id bigint generated always as identity,
  sale_id integer not null,
  line_no smallint not null,
  product_id smallint not null,
  qty_grams bigint not null,
  unit_price_paisa_per_kg bigint not null,
  price_source text default 'manual'::text not null,
  revenue_paisa bigint not null,
  dispatched_grams bigint default 0 not null,
  constraint sale_lines_pkey PRIMARY KEY (id),
  constraint sale_lines_sale_id_line_no_key UNIQUE (sale_id, line_no),
  constraint sale_lines_dispatched_grams_check CHECK ((dispatched_grams >= 0)),
  constraint sale_lines_price_source_check CHECK ((price_source = ANY (ARRAY['manual'::text, 'suggested'::text]))),
  constraint sale_lines_qty_grams_check CHECK ((qty_grams > 0)),
  constraint sale_lines_revenue_paisa_check CHECK ((revenue_paisa > 0)),
  constraint sale_lines_unit_price_paisa_per_kg_check CHECK ((unit_price_paisa_per_kg > 0)),
  constraint sale_lines_product_id_fkey FOREIGN KEY (product_id) REFERENCES app.products(id),
  constraint sale_lines_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES app.sales(id)
);

create table if not exists app.dispatch_allocations (
  id bigint generated always as identity,
  dispatch_id integer not null,
  sale_line_id bigint not null,
  batch_id integer not null,
  qty_grams bigint not null,
  unit_cost_paisa_per_kg bigint not null,
  cogs_paisa bigint not null,
  allocation_mode text not null,
  override_reason text,
  created_at timestamp with time zone default now() not null,
  constraint dispatch_allocations_pkey PRIMARY KEY (id),
  constraint dispatch_allocations_allocation_mode_check CHECK ((allocation_mode = ANY (ARRAY['fifo'::text, 'manual'::text]))),
  constraint dispatch_allocations_cogs_paisa_check CHECK ((cogs_paisa > 0)),
  constraint dispatch_allocations_qty_grams_check CHECK ((qty_grams > 0)),
  constraint dispatch_allocations_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES app.batches(id),
  constraint dispatch_allocations_dispatch_id_fkey FOREIGN KEY (dispatch_id) REFERENCES app.dispatches(id),
  constraint dispatch_allocations_sale_line_id_fkey FOREIGN KEY (sale_line_id) REFERENCES app.sale_lines(id)
);


-- ============ 3. Indexes, row level security (ledger app) ============
create index if not exists ix_bcc_batch ON app.batch_cost_components USING btree (batch_id);
create index if not exists ix_adv_party ON app.customer_advances USING btree (party_id);
create UNIQUE index if not exists uq_adv_idem ON app.customer_advances USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);
create index if not exists ix_alloc_batch ON app.dispatch_allocations USING btree (batch_id);
create index if not exists ix_alloc_dispatch ON app.dispatch_allocations USING btree (dispatch_id);
create index if not exists ix_dispatch_sale ON app.dispatches USING btree (sale_id);
create UNIQUE index if not exists uq_dispatch_idem ON app.dispatches USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);
create index if not exists idx_events_date ON app.events USING btree (occurred_on);
create index if not exists idx_events_party ON app.events USING btree (party_type, party_name);
create index if not exists idx_events_type ON app.events USING btree (event_type);
create UNIQUE index if not exists uq_events_idem ON app.events USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);
create index if not exists idx_ledger_account ON app.ledger_entries USING btree (account_id);
create index if not exists idx_ledger_event ON app.ledger_entries USING btree (event_id);
create index if not exists idx_mov_batch_loc ON app.movements USING btree (batch_id, location_id);
create index if not exists idx_mov_product ON app.movements USING btree (product_id);
create index if not exists idx_review_status ON app.review_queue USING btree (status);
create index if not exists ix_sales_party ON app.sales USING btree (party_id);
create UNIQUE index if not exists uq_sales_idem ON app.sales USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL);

alter table app.accounts enable row level security;
alter table app.batch_cost_components enable row level security;
alter table app.batches enable row level security;
alter table app.customer_advances enable row level security;
alter table app.dispatch_allocations enable row level security;
alter table app.dispatches enable row level security;
alter table app.events enable row level security;
alter table app.ledger_entries enable row level security;
alter table app.locations enable row level security;
alter table app.movements enable row level security;
alter table app.parties enable row level security;
alter table app.products enable row level security;
alter table app.review_queue enable row level security;
alter table app.sale_lines enable row level security;
alter table app.sales enable row level security;
alter table app.stg_excel_cash enable row level security;
alter table app.users enable row level security;


-- ============ 4. Functions (live definitions) ============
set local check_function_bodies = off;

CREATE OR REPLACE FUNCTION app.assert_cash_nonnegative()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  bal bigint;
begin
  select coalesce(sum(le.debit_paisa - le.credit_paisa), 0) into bal
  from app.ledger_entries le
  join app.accounts a on a.id = le.account_id
  where a.code = '1000';
  if bal < 0 then
    raise exception 'INVARIANT VIOLATION: Cash on Hand would go negative (balance % paisa)', bal
      using errcode = 'check_violation';
  end if;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION app.assert_event_balanced()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  d bigint; c bigint;
begin
  select coalesce(sum(debit_paisa),0), coalesce(sum(credit_paisa),0)
    into d, c
  from app.ledger_entries where event_id = new.id;
  if d <> c then
    raise exception 'INVARIANT VIOLATION: event % unbalanced (debit %, credit % paisa)', new.event_ref, d, c
      using errcode = 'check_violation';
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION app.assert_ledger_events_balanced()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare bad record;
begin
  for bad in
    select e.event_ref, sum(le.debit_paisa) as d, sum(le.credit_paisa) as c
    from (select distinct event_id from ins_rows) t
    join app.ledger_entries le on le.event_id = t.event_id
    join app.events e on e.id = t.event_id
    group by e.event_ref
  loop
    if bad.d <> bad.c then
      raise exception 'INVARIANT VIOLATION: event % unbalanced (debit %, credit % paisa)', bad.event_ref, bad.d, bad.c
        using errcode = 'check_violation';
    end if;
  end loop;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION app.assert_stock_nonnegative()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare r record;
begin
  for r in
    select batch_id, location_id,
           sum(case when direction = 'in' then qty_grams
                    when direction = 'out' then -qty_grams
                    else 0 end) as q
    from app.movements
    where batch_id = new.batch_id and location_id = new.location_id
    group by batch_id, location_id
  loop
    if r.q < 0 then
      raise exception 'INVARIANT VIOLATION: stock negative for batch % at location % (qty % g)', r.batch_id, r.location_id, r.q
        using errcode = 'check_violation';
    end if;
  end loop;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION app.batch_unit_cost_paisa_per_kg(p_batch_id integer)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'app'
AS $function$
declare
  v_qty bigint; v_val bigint;
begin
  select coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0),
         coalesce(sum(m.value_paisa), 0)
    into v_qty, v_val
  from app.movements m where m.batch_id = p_batch_id;
  if v_qty is null or v_qty <= 0 then return 0; end if;
  return round(v_val::numeric / (v_qty / 1000.0));
end $function$;

CREATE OR REPLACE FUNCTION app.fifo_pool(p_product_id smallint, p_location_id smallint)
 RETURNS TABLE(batch_id integer, batch_code text, opened_on date, onhand_grams bigint, unit_cost_ppk bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'app'
AS $function$
  select b.id, b.batch_code, b.opened_on,
         coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0)::bigint,
         app.batch_unit_cost_paisa_per_kg(b.id)
  from app.batches b join app.movements m on m.batch_id = b.id
  where b.product_id = p_product_id and b.location_id = p_location_id
    and b.status = 'open'
  group by b.id, b.batch_code, b.opened_on
  having coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0) > 0
  order by b.opened_on, b.id
$function$;

CREATE OR REPLACE FUNCTION app.inventory_account(p_product_id smallint)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'app'
AS $function$
  select case form when 'raw' then '1200' when 'bulk_processed' then '1210'
                   when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end
  from app.products where id = p_product_id
$function$;

CREATE OR REPLACE FUNCTION app.next_dispatch_ref()
 RETURNS text
 LANGUAGE sql
 SET search_path TO 'app'
AS $function$ select 'DSP-' || lpad(nextval('app.dispatch_ref_seq')::text, 5, '0') $function$;

CREATE OR REPLACE FUNCTION app.next_event_ref()
 RETURNS text
 LANGUAGE sql
AS $function$ select 'EV-' || lpad(nextval('app.event_ref_seq')::text, 6, '0') $function$;

CREATE OR REPLACE FUNCTION app.next_party_ref()
 RETURNS text
 LANGUAGE sql
AS $function$ select 'PT-' || lpad(nextval('app.party_ref_seq')::text, 4, '0') $function$;

CREATE OR REPLACE FUNCTION app.next_sale_ref()
 RETURNS text
 LANGUAGE sql
 SET search_path TO 'app'
AS $function$ select 'INV-' || lpad(nextval('app.sale_ref_seq')::text, 5, '0') $function$;

CREATE OR REPLACE FUNCTION app.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb, p_party_type text DEFAULT NULL::text, p_party_name text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_ref text;
  v_event_id integer;
  v_line jsonb;
  v_dr bigint;
  v_cr bigint;
  v_total_dr bigint := 0;
  v_total_cr bigint := 0;
begin
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

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by)
  values (v_ref, p_event_type, p_occurred_on, p_description, p_party_type, p_party_name, 'app', p_created_by)
  returning id into v_event_id;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event_id, (row_number() over (order by t.ord))::smallint, a.id,
         coalesce((t.line->>'debit')::bigint, 0), coalesce((t.line->>'credit')::bigint, 0)
  from jsonb_array_elements(p_lines) with ordinality t(line, ord)
  join app.accounts a on a.code = t.line->>'account';

  return v_ref;
end $function$;

CREATE OR REPLACE FUNCTION app.record_advance(p_party text, p_amount_paisa bigint, p_occurred_on date DEFAULT CURRENT_DATE, p_note text DEFAULT NULL::text, p_idempotency_key text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_party app.parties%rowtype;
  v_amt bigint := coalesce(p_amount_paisa, 0);
  v_ref text;
begin
  if v_amt <= 0 then
    raise exception 'INVARIANT VIOLATION: advance amount must be positive' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is not null and exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
    return jsonb_build_object('duplicate', true);
  end if;
  select * into v_party from app.parties
  where kind = 'customer' and (party_ref = p_party or lower(name) = lower(p_party));
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown customer %', p_party using errcode = 'check_violation';
  end if;

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'customer_advance', p_occurred_on,
    'Customer advance from ' || v_party.name || ' - ' || (v_amt / 100.0)::numeric(14,2) || ' PKR held as liability (not revenue)'
    || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
    'customer', v_party.id, v_party.name, 'app', p_created_by, p_idempotency_key)
  returning event_ref into v_ref;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select e.id, x.seq, a.id, x.dr, x.cr
  from app.events e,
       (values (1, '1000', v_amt, 0::bigint), (2, '2200', 0::bigint, v_amt)) as x(seq, acc_code, dr, cr)
  join app.accounts a on a.code = x.acc_code
  where e.event_ref = v_ref;

  insert into app.customer_advances (event_id, party_id, direction, amount_paisa, occurred_on, idempotency_key, note, created_by)
  select e.id, v_party.id, 'received', v_amt, p_occurred_on, p_idempotency_key, p_note, p_created_by
  from app.events e where e.event_ref = v_ref;

  return jsonb_build_object('event_ref', v_ref, 'party_ref', v_party.party_ref, 'amount_paisa', v_amt);
end $function$;

CREATE OR REPLACE FUNCTION app.restrict_single_statement_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'app'
AS $function$
declare v_rows bigint;
begin
  select count(*) into v_rows from inserted;
  if v_rows is null or v_rows > 1 then
    raise exception 'INVARIANT VIOLATION: multi-row insert into app.% bypasses per-event balance trigger', tg_table_name
      using errcode = 'feature_not_supported';
  end if;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.create_customer(p_name text, p_phone text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_name text := btrim(p_name);
  v_id integer;
  v_ref text;
begin
  if v_name is null or v_name = '' then
    raise exception 'INVARIANT VIOLATION: customer name is required' using errcode = 'check_violation';
  end if;
  select id, party_ref into v_id, v_ref from app.parties where lower(name) = lower(v_name) and kind = 'customer';
  if found then
    return jsonb_build_object('party_id', v_id, 'party_ref', v_ref, 'created', false);
  end if;
  v_ref := app.next_party_ref();
  insert into app.parties (party_ref, name, phone, kind, note)
  values (v_ref, v_name, nullif(btrim(coalesce(p_phone, '')), ''), 'customer', nullif(btrim(coalesce(p_note, '')), ''))
  returning id into v_id;
  return jsonb_build_object('party_id', v_id, 'party_ref', v_ref, 'created', true);
end $function$;

CREATE OR REPLACE FUNCTION public.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb, p_party_type text DEFAULT NULL::text, p_party_name text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
begin
  return app.post_event(p_event_type, p_occurred_on, p_description, p_lines, p_party_type, p_party_name, p_created_by);
end $function$;

CREATE OR REPLACE FUNCTION public.record_customer_advance(p_customer text, p_amount_paisa bigint, p_occurred_on date DEFAULT CURRENT_DATE, p_note text DEFAULT NULL::text, p_idempotency_key text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
  select app.record_advance(p_customer, p_amount_paisa, p_occurred_on, p_note, p_idempotency_key, p_created_by)
$function$;

CREATE OR REPLACE FUNCTION public.record_customer_payment(p_customer text, p_amount_paisa bigint, p_occurred_on date DEFAULT CURRENT_DATE, p_note text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_customer text := btrim(coalesce(p_customer, ''));
  v_amount bigint := coalesce(p_amount_paisa, 0);
  v_party app.parties%rowtype;
  v_outstanding bigint;
  v_event_ref text;
begin
  if v_customer = '' then
    raise exception 'INVARIANT VIOLATION: customer is required' using errcode = 'check_violation';
  end if;
  if v_amount <= 0 then
    raise exception 'INVARIANT VIOLATION: payment amount must be positive' using errcode = 'check_violation';
  end if;
  if p_idempotency_key is not null and exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
    return jsonb_build_object('duplicate', true);
  end if;

  select * into v_party from app.parties
  where kind = 'customer' and (party_ref = v_customer or lower(name) = lower(v_customer));
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown customer %', v_customer using errcode = 'check_violation';
  end if;

  select coalesce(sum(le.debit_paisa - le.credit_paisa), 0)::bigint into v_outstanding
  from app.ledger_entries le
  join app.accounts a on a.id = le.account_id and a.code = '1100'
  join app.events e on e.id = le.event_id
  where e.party_id = v_party.id;

  if v_amount > v_outstanding then
    raise exception 'INVARIANT VIOLATION: payment % exceeds %s outstanding receivable of % - overpayments belong on Customer Advances, not here',
      (v_amount / 100.0)::numeric(14,2), v_party.name, (v_outstanding / 100.0)::numeric(14,2)
      using errcode = 'check_violation';
  end if;

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'customer_payment', p_occurred_on,
    'Customer payment from ' || v_party.name || ' - ' || (v_amount / 100.0)::numeric(14,2) ||
    ' PKR against receivable' || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
    'customer', v_party.id, v_party.name, 'app', p_created_by, p_idempotency_key)
  returning event_ref into v_event_ref;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select e.id, x.seq, a.id, x.dr, x.cr
  from app.events e,
       (values (1, '1000', v_amount, 0::bigint), (2, '1100', 0::bigint, v_amount)) as x(seq, acc_code, dr, cr)
  join app.accounts a on a.code = x.acc_code
  where e.event_ref = v_event_ref;

  return jsonb_build_object('event_ref', v_event_ref, 'party_ref', v_party.party_ref,
    'amount_paisa', v_amount, 'remaining_ar_paisa', v_outstanding - v_amount);
end $function$;

CREATE OR REPLACE FUNCTION public.record_dispatch(p_sale_ref text, p_lines jsonb, p_occurred_on date DEFAULT CURRENT_DATE, p_note text DEFAULT NULL::text, p_idempotency_key text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_sale app.sales%rowtype;
  v_party app.parties%rowtype;
  v_dispatch_id integer;
  v_dispatch_ref text;
  v_event_ref text;
  v_line jsonb;
  v_alloc jsonb;
  v_product app.products%rowtype;
  v_location smallint;
  v_qty_grams bigint;
  v_remaining bigint;
  v_sale_line app.sale_lines%rowtype;
  v_mode text;
  v_allocs jsonb := '[]'::jsonb;
  v_pool record;
  v_need bigint;
  v_batch app.batches%rowtype;
  v_onhand bigint;
  v_cost bigint;
  v_cogs bigint;
  v_total_cogs bigint := 0;
  v_line_no integer;
  v_seq integer := 0;
  v_revenue bigint;
  i integer;
  j integer;
  v_reason text;
  v_manual_sum bigint;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'INVARIANT VIOLATION: at least one dispatch line is required' using errcode = 'check_violation';
  end if;

  select * into v_sale from app.sales where sale_ref = btrim(coalesce(p_sale_ref, ''));
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown sale %', p_sale_ref using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    if exists (select 1 from app.dispatches where idempotency_key = p_idempotency_key) then
      select id, dispatch_ref, total_cogs_paisa into v_dispatch_id, v_dispatch_ref, v_total_cogs
      from app.dispatches where idempotency_key = p_idempotency_key;
      return jsonb_build_object('duplicate', true, 'dispatch_ref', v_dispatch_ref, 'cogs_paisa', v_total_cogs);
    end if;
    if exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
      return jsonb_build_object('duplicate', true);
    end if;
  end if;

  select * into v_party from app.parties where id = v_sale.party_id;
  v_revenue := v_sale.total_revenue_paisa;

  begin
    for i in 0 .. jsonb_array_length(p_lines) - 1 loop
      v_line := p_lines -> i;
      v_line_no := i + 1;
      select * into v_product from app.products where code = v_line ->> 'product_code';
      if not found then
        raise exception 'INVARIANT VIOLATION: unknown product code % (line %)', v_line ->> 'product_code', v_line_no using errcode = 'check_violation';
      end if;
      -- Audit fix 2026-09-19: pick the EARLIEST line of this product that still
      -- has stock to dispatch. Previously this always picked line_no = 1, so a
      -- multi-line same-product invoice stamped every allocation with the first
      -- line's id and never completed.
      select * into v_sale_line from app.sale_lines
      where sale_id = v_sale.id and product_id = v_product.id and dispatched_grams < qty_grams
      order by line_no limit 1;
      if not found then
        select * into v_sale_line from app.sale_lines
        where sale_id = v_sale.id and product_id = v_product.id
        order by line_no limit 1;
      end if;
      if not found then
        raise exception 'INVARIANT VIOLATION: product % is not on invoice % (line %)', v_product.code, v_sale.sale_ref, v_line_no using errcode = 'check_violation';
      end if;
      v_remaining := v_sale_line.qty_grams - v_sale_line.dispatched_grams;
      if v_line ? 'qty_grams' then
        v_qty_grams := round((v_line ->> 'qty_grams')::numeric)::bigint;
      else
        v_qty_grams := round((v_line ->> 'qty_kg')::numeric * 1000)::bigint;
      end if;
      if v_qty_grams is null or v_qty_grams <= 0 then
        raise exception 'INVARIANT VIOLATION: dispatch quantity must be positive (line %)', v_line_no using errcode = 'check_violation';
      end if;
      if v_qty_grams > v_remaining then
        raise exception 'INVARIANT VIOLATION: line % requests % kg but invoice % has only % kg left to dispatch for %',
          v_line_no, (v_qty_grams / 1000.0)::numeric(12,1), v_sale.sale_ref, (v_remaining / 1000.0)::numeric(12,1), v_product.code
          using errcode = 'check_violation';
      end if;
      if v_line ->> 'location_code' is null or btrim(v_line ->> 'location_code') = '' then
        raise exception 'INVARIANT VIOLATION: dispatch location is required (line %) - stock at one location is never available at another', v_line_no using errcode = 'check_violation';
      end if;
      select id into v_location from app.locations where code = v_line ->> 'location_code';
      if not found then
        raise exception 'INVARIANT VIOLATION: unknown location % (line %)', v_line ->> 'location_code', v_line_no using errcode = 'check_violation';
      end if;

      perform b.id from app.batches b
      where b.product_id = v_product.id and b.location_id = v_location and b.status = 'open'
      order by b.id
      for update;

      if v_line ? 'allocations' and jsonb_array_length(v_line -> 'allocations') > 0 then
        v_mode := 'manual';
        v_reason := btrim(coalesce(v_line ->> 'override_reason', ''));
        if v_reason = '' then
          raise exception 'INVARIANT VIOLATION: manual batch selection requires an override reason (line %)', v_line_no using errcode = 'check_violation';
        end if;
        v_manual_sum := 0;
        for j in 0 .. jsonb_array_length(v_line -> 'allocations') - 1 loop
          v_alloc := v_line -> 'allocations' -> j;
          select * into v_batch from app.batches where batch_code = v_alloc ->> 'batch_code';
          if not found then
            raise exception 'INVARIANT VIOLATION: unknown batch % (line %)', v_alloc ->> 'batch_code', v_line_no using errcode = 'check_violation';
          end if;
          if v_batch.product_id <> v_product.id then
            raise exception 'INVARIANT VIOLATION: batch % holds a different product, not % - incompatible substitution rejected (line %)',
              v_batch.batch_code, v_product.code, v_line_no using errcode = 'check_violation';
          end if;
          if v_batch.location_id <> v_location then
            raise exception 'INVARIANT VIOLATION: batch % is at another location - it cannot serve a dispatch from % (line %)',
              v_batch.batch_code, (v_line ->> 'location_code'), v_line_no using errcode = 'check_violation';
          end if;
          if v_batch.status <> 'open' then
            raise exception 'INVARIANT VIOLATION: batch % is % and cannot be dispatched (line %)', v_batch.batch_code, v_batch.status, v_line_no using errcode = 'check_violation';
          end if;
          if v_alloc ? 'qty_grams' then
            v_need := round((v_alloc ->> 'qty_grams')::numeric)::bigint;
          else
            v_need := round((v_alloc ->> 'qty_kg')::numeric * 1000)::bigint;
          end if;
          if v_need is null or v_need <= 0 then
            raise exception 'INVARIANT VIOLATION: allocation quantity must be positive (line %)', v_line_no using errcode = 'check_violation';
          end if;
          select coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0)
            into v_onhand from app.movements m where m.batch_id = v_batch.id;
          if v_need > v_onhand then
            raise exception 'INVARIANT VIOLATION: batch % has only % kg on hand, allocation requests % kg (line %)',
              v_batch.batch_code, (v_onhand / 1000.0)::numeric(12,1), (v_need / 1000.0)::numeric(12,1), v_line_no using errcode = 'check_violation';
          end if;
          v_manual_sum := v_manual_sum + v_need;
          v_cost := app.batch_unit_cost_paisa_per_kg(v_batch.id);
          v_cogs := round(v_need::numeric * v_cost / 1000.0)::bigint;
          v_seq := v_seq + 1;
          v_allocs := v_allocs || jsonb_build_object('sale_line_id', v_sale_line.id, 'product_id', v_product.id,
            'batch_id', v_batch.id, 'batch_code', v_batch.batch_code, 'qty_grams', v_need,
            'unit_cost_ppk', v_cost, 'cogs_paisa', v_cogs, 'mode', 'manual', 'reason', v_reason);
        end loop;
        if v_manual_sum <> v_qty_grams then
          raise exception 'INVARIANT VIOLATION: manual allocations (%) must exactly cover the line quantity (line %)',
            (v_manual_sum / 1000.0)::numeric(12,1), v_line_no using errcode = 'check_violation';
        end if;
      else
        v_mode := 'fifo';
        v_need := v_qty_grams;
        for v_pool in
          select batch_id, batch_code, onhand_grams, unit_cost_ppk from app.fifo_pool(v_product.id, v_location)
        loop
          exit when v_need <= 0;
          if v_pool.onhand_grams > 0 then
            v_qty_grams := least(v_need, v_pool.onhand_grams);
            v_cogs := round(v_qty_grams::numeric * v_pool.unit_cost_ppk / 1000.0)::bigint;
            v_seq := v_seq + 1;
            v_allocs := v_allocs || jsonb_build_object('sale_line_id', v_sale_line.id, 'product_id', v_product.id,
              'batch_id', v_pool.batch_id, 'batch_code', v_pool.batch_code, 'qty_grams', v_qty_grams,
              'unit_cost_ppk', v_pool.unit_cost_ppk, 'cogs_paisa', v_cogs, 'mode', 'fifo', 'reason', null);
            v_need := v_need - v_qty_grams;
          end if;
        end loop;
        if v_need > 0 then
          raise exception 'INVARIANT VIOLATION: insufficient eligible stock of % at % - need % kg more, nothing compatible left (FIFO pool exhausted)',
            v_product.code, (v_line ->> 'location_code'), (v_need / 1000.0)::numeric(12,1) using errcode = 'check_violation';
        end if;
      end if;

      -- Audit fix 2026-09-19: increment THIS line immediately so a later line of
      -- the same product selects the next under-dispatched line.
      update app.sale_lines set dispatched_grams = dispatched_grams + v_qty_grams where id = v_sale_line.id;
    end loop;

    if v_seq = 0 then
      raise exception 'INVARIANT VIOLATION: dispatch has no allocations' using errcode = 'check_violation';
    end if;

    select coalesce(sum((a ->> 'cogs_paisa')::bigint), 0) into v_total_cogs from jsonb_array_elements(v_allocs) a;

    insert into app.dispatches (dispatch_ref, sale_id, occurred_on, total_cogs_paisa, idempotency_key, note, created_by)
    values (app.next_dispatch_ref(), v_sale.id, p_occurred_on, v_total_cogs, p_idempotency_key, p_note, p_created_by)
    returning id, dispatch_ref into v_dispatch_id, v_dispatch_ref;

    insert into app.dispatch_allocations (dispatch_id, sale_line_id, batch_id, qty_grams, unit_cost_paisa_per_kg, cogs_paisa, allocation_mode, override_reason)
    select v_dispatch_id, (a ->> 'sale_line_id')::bigint, (a ->> 'batch_id')::integer, (a ->> 'qty_grams')::bigint,
           (a ->> 'unit_cost_ppk')::bigint, (a ->> 'cogs_paisa')::bigint, a ->> 'mode', a ->> 'reason'
    from jsonb_array_elements(v_allocs) a;

    insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
    values (app.next_event_ref(), 'dispatch', p_occurred_on,
      'Dispatch ' || v_dispatch_ref || ' against invoice ' || v_sale.sale_ref || ' to ' || v_party.name ||
      ' - COGS ' || (v_total_cogs / 100.0)::numeric(14,2) || ' PKR at exact FIFO batch cost'
      || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
      'customer', v_party.id, v_party.name, 'app', p_created_by, p_idempotency_key)
    returning event_ref into v_event_ref;

    insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
    select e.id, x.seq, a.id, x.dr, x.cr
    from app.events e
    join (select 1 as seq, '4100' as acc, v_total_cogs as dr, 0::bigint as cr
          union all
          select 100 + row_number() over (order by c.acc), c.acc, 0::bigint, c.cogs
          from (select app.inventory_account((a ->> 'product_id')::smallint) as acc, sum((a ->> 'cogs_paisa')::bigint) as cogs
                from jsonb_array_elements(v_allocs) a group by 1) c
         ) x on true
    join app.accounts a on a.code = x.acc
    where e.event_ref = v_event_ref;

    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    select e.id, (a ->> 'sale_line_id')::int * 100 + row_number() over (partition by a ->> 'sale_line_id' order by a ->> 'batch_code'),
           (a ->> 'product_id')::smallint, (a ->> 'batch_id')::integer, b.location_id, 'out',
           (a ->> 'qty_grams')::bigint, -1 * (a ->> 'cogs_paisa')::bigint
    from app.events e
    join jsonb_array_elements(v_allocs) a on true
    join app.batches b on b.id = (a ->> 'batch_id')::integer
    where e.event_ref = v_event_ref;

    update app.sales set status = case when not exists (
      select 1 from app.sale_lines sl where sl.sale_id = v_sale.id and sl.dispatched_grams < sl.qty_grams
    ) then 'dispatched' else 'invoiced' end where id = v_sale.id;

    update app.batches b set status = 'closed', closed_on = p_occurred_on
    where b.id in (select distinct (a ->> 'batch_id')::integer from jsonb_array_elements(v_allocs) a)
      and 0 = (select coalesce(sum(case when m.direction = 'in' then m.qty_grams when m.direction = 'out' then -m.qty_grams else 0 end), 0)
               from app.movements m where m.batch_id = b.id);

    return jsonb_build_object('dispatch_ref', v_dispatch_ref, 'sale_ref', v_sale.sale_ref,
      'cogs_paisa', v_total_cogs, 'revenue_paisa', v_revenue,
      'gross_profit_paisa', v_revenue - v_total_cogs,
      'allocations', v_allocs);
  exception
    when serialization_failure or deadlock_detected then
      raise exception 'CONCURRENCY: another dispatch changed the same stock - nothing was saved, please retry'
        using errcode = 'serialization_failure';
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_process_run(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_input_batch   app.batches%rowtype;
  v_input_product app.products%rowtype;
  v_input_loc     app.locations%rowtype;
  v_onhand        bigint;
  v_input_value   bigint;
  v_out_qty       bigint := 0;
  v_out_total     bigint := 0;
  v_leftover      bigint;
  v_wast_value    bigint := 0;
  v_wast_expense  bigint;
  v_event_ref     text;
  v_event_id      integer;
  v_line          jsonb;
  v_prod          app.products%rowtype;
  v_batch_code    text;
  v_batch_id      integer;
  v_lines         jsonb := '[]'::jsonb;
  v_result        jsonb := '[]'::jsonb;
  v_grade         int := 0;
  v_seq           smallint := 0;
  v_inv_account   text;
begin
  if p_input_qty_grams is null or p_input_qty_grams <= 0 then
    raise exception 'INVARIANT VIOLATION: input quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_wastage_grams is null or p_wastage_grams < 0 then
    raise exception 'INVARIANT VIOLATION: wastage cannot be negative' using errcode = 'check_violation';
  end if;
  if p_outputs is null or jsonb_typeof(p_outputs) <> 'array' or jsonb_array_length(p_outputs) = 0 then
    raise exception 'INVARIANT VIOLATION: at least one output grade is required' using errcode = 'check_violation';
  end if;
  if p_conversion_cost_paisa is null or p_conversion_cost_paisa < 0 then
    raise exception 'INVARIANT VIOLATION: conversion cost cannot be negative' using errcode = 'check_violation';
  end if;

  select * into v_input_batch from app.batches where batch_code = p_input_batch_code;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown input batch %', p_input_batch_code using errcode = 'check_violation';
  end if;
  select * into v_input_product from app.products where id = v_input_batch.product_id;
  select * into v_input_loc from app.locations where id = v_input_batch.location_id;

  -- on-hand: ONLY 'out' decrements ('wastage' rows are value-attribution records)
  select coalesce(sum(case when direction = 'in' then qty_grams
                           when direction = 'out' then -qty_grams
                           else 0 end), 0)
    into v_onhand
    from app.movements where batch_id = v_input_batch.id;

  if p_input_qty_grams > v_onhand then
    raise exception 'INVARIANT VIOLATION: cannot consume % g from batch % — only % g on hand',
      p_input_qty_grams, p_input_batch_code, v_onhand using errcode = 'check_violation';
  end if;

  -- batch weighted-average cost of consumed quantity (numeric math: no truncation before rounding)
  select coalesce(sum(value_paisa), 0) into v_input_value
    from app.movements
   where batch_id = v_input_batch.id and direction in ('in','out');
  v_input_value := round(v_input_value::numeric * p_input_qty_grams / v_onhand);

  for v_line in select * from jsonb_array_elements(p_outputs) loop
    if coalesce((v_line->>'qty_grams')::bigint, 0) <= 0 then
      raise exception 'INVARIANT VIOLATION: output quantities must be positive' using errcode = 'check_violation';
    end if;
    v_out_qty := v_out_qty + (v_line->>'qty_grams')::bigint;
  end loop;
  if v_out_qty + p_wastage_grams <> p_input_qty_grams then
    raise exception 'INVARIANT VIOLATION: mass conservation failed — output % g + wastage % g must equal input % g',
      v_out_qty, p_wastage_grams, p_input_qty_grams using errcode = 'check_violation';
  end if;

  for v_line in select * from jsonb_array_elements(p_outputs) loop
    select * into v_prod from app.products where code = v_line->>'product_code';
    if not found then
      raise exception 'INVARIANT VIOLATION: unknown output product code %', v_line->>'product_code' using errcode = 'check_violation';
    end if;
    if coalesce((v_line->>'value_paisa')::bigint, 0) < 0 then
      raise exception 'INVARIANT VIOLATION: output values cannot be negative' using errcode = 'check_violation';
    end if;
    v_out_total := v_out_total + coalesce((v_line->>'value_paisa')::bigint, 0);
  end loop;
  if v_out_total > v_input_value + p_conversion_cost_paisa then
    raise exception 'INVARIANT VIOLATION: cost conservation failed — output value % paisa exceeds input value % + conversion cost %',
      v_out_total, v_input_value, p_conversion_cost_paisa using errcode = 'check_violation';
  end if;

  v_leftover := v_input_value + p_conversion_cost_paisa - v_out_total;
  if p_wastage_grams > 0 and v_leftover > 0 then
    v_wast_value := least(v_leftover, round(v_leftover::numeric * p_wastage_grams / (p_wastage_grams + v_out_qty)));
  end if;
  v_wast_expense := v_leftover - v_wast_value;

  insert into app.events (event_ref, event_type, occurred_on, description, source, created_by)
  values (app.next_event_ref(), 'process_run', p_occurred_on,
          'Crush run: consumed ' || (p_input_qty_grams / 1000.0)::numeric(12,1) || ' kg of ' || p_input_batch_code ||
          ' → ' || (v_out_qty / 1000.0)::numeric(12,1) || ' kg graded output, ' || (p_wastage_grams / 1000.0)::numeric(12,1) || ' kg wastage' ||
          coalesce(' — ' || nullif(btrim(p_note), ''), ''),
          'app', p_created_by)
  returning event_ref, id into v_event_ref, v_event_id;

  -- 1) input consumption (out)
  v_seq := v_seq + 1;
  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  values (v_event_id, v_seq, v_input_product.id, v_input_batch.id, v_input_loc.id, 'out',
          p_input_qty_grams, -(v_input_value - v_wast_value));

  -- 2) graded outputs (in): new child batches
  for v_line in select * from jsonb_array_elements(p_outputs) loop
    select * into v_prod from app.products where code = v_line->>'product_code';
    v_grade := v_grade + 1;
    v_batch_code := p_input_batch_code || '-G' || v_grade::text;
    while exists (select 1 from app.batches where batch_code = v_batch_code) loop
      v_grade := v_grade + 1;
      v_batch_code := p_input_batch_code || '-G' || v_grade::text;
    end loop;
    insert into app.batches (batch_code, product_id, location_id, opened_on, note)
    values (v_batch_code, v_prod.id, v_input_batch.location_id, p_occurred_on,
            'Crush output from ' || p_input_batch_code || coalesce(' — ' || nullif(btrim(p_note), ''), ''))
    returning id into v_batch_id;

    v_seq := v_seq + 1;
    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    values (v_event_id, v_seq, v_prod.id, v_batch_id, v_input_batch.location_id, 'in',
            (v_line->>'qty_grams')::bigint, (v_line->>'value_paisa')::bigint);

    v_result := v_result || jsonb_build_object(
      'batch_code', v_batch_code, 'product_code', v_prod.code, 'product_name', v_prod.name,
      'qty_grams', (v_line->>'qty_grams')::bigint, 'value_paisa', (v_line->>'value_paisa')::bigint);
  end loop;

  -- 3) wastage — REPORTING row: quantity + value attribution, NOT a second quantity decrement
  if p_wastage_grams > 0 then
    v_seq := v_seq + 1;
    insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
    values (v_event_id, v_seq, v_input_product.id, v_input_batch.id, v_input_loc.id, 'wastage',
            p_wastage_grams, -v_wast_value);
  end if;

  v_lines := v_lines || jsonb_build_object('account',
    case v_input_product.form when 'raw' then '1200' when 'bulk_processed' then '1210' when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end,
    'credit', v_input_value);

  for v_line in select * from jsonb_array_elements(p_outputs) loop
    select * into v_prod from app.products where code = v_line->>'product_code';
    v_inv_account := case v_prod.form when 'raw' then '1200' when 'bulk_processed' then '1210' when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end;
    v_lines := v_lines || jsonb_build_object('account', v_inv_account, 'debit', (v_line->>'value_paisa')::bigint);
  end loop;

  if v_leftover > 0 then
    v_lines := v_lines || jsonb_build_object('account', '5250', 'debit', v_leftover);
  end if;
  if p_conversion_cost_paisa > 0 then
    v_lines := v_lines || jsonb_build_object('account', case when p_pay_cash then '1000' else '2000' end, 'credit', p_conversion_cost_paisa);
  end if;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event_id, (row_number() over (order by t.ord))::smallint, a.id,
         coalesce((t.o->>'debit')::bigint, 0), coalesce((t.o->>'credit')::bigint, 0)
  from jsonb_array_elements(v_lines) with ordinality t(o, ord)
  join app.accounts a on a.code = t.o->>'account';

  return jsonb_build_object('event_ref', v_event_ref, 'input_batch', p_input_batch_code,
    'input_value_paisa', v_input_value, 'wastage_grams', p_wastage_grams,
    'wastage_value_paisa', v_wast_value, 'wastage_expense_paisa', v_wast_expense,
    'outputs', v_result);
end
$function$;

CREATE OR REPLACE FUNCTION public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_product app.products%rowtype;
  v_location app.locations%rowtype;
  v_batch_code text;
  v_batch_id integer;
  v_event_ref text;
  v_credit_account text;
begin
  -- validation
  if p_supplier is null or btrim(p_supplier) = '' then
    raise exception 'INVARIANT VIOLATION: supplier name is required' using errcode = 'check_violation';
  end if;
  if p_qty_grams is null or p_qty_grams <= 0 then
    raise exception 'INVARIANT VIOLATION: quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_landed_cost_paisa is null or p_landed_cost_paisa <= 0 then
    raise exception 'INVARIANT VIOLATION: landed cost must be positive' using errcode = 'check_violation';
  end if;

  select * into v_product from app.products where code = p_product_code;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown product code %', p_product_code using errcode = 'check_violation';
  end if;
  select * into v_location from app.locations where code = p_location_code;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown location code %', p_location_code using errcode = 'check_violation';
  end if;

  -- new batch code (sequence skips any existing codes, e.g. BATCH-001)
  v_batch_code := 'BATCH-' || lpad(nextval('app.batch_ref_seq')::text, 3, '0');
  while exists (select 1 from app.batches where batch_code = v_batch_code) loop
    v_batch_code := 'BATCH-' || lpad(nextval('app.batch_ref_seq')::text, 3, '0');
  end loop;

  insert into app.batches (batch_code, product_id, location_id, opened_on, note)
  values (v_batch_code, v_product.id, v_location.id, p_occurred_on,
          'Purchased from ' || btrim(p_supplier) || coalesce(' — ' || nullif(btrim(p_note), ''), ''))
  returning id into v_batch_id;

  v_credit_account := case when p_pay_cash then '1000' else '2000' end;

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by)
  values (app.next_event_ref(), 'purchase', p_occurred_on,
          'Salt purchase from ' || btrim(p_supplier) || ' — ' || (p_qty_grams / 1000.0)::numeric(12,1) || ' kg, landed cost ' || (p_landed_cost_paisa / 100.0)::numeric(14,2) || ' PKR, batch ' || v_batch_code,
          'supplier', btrim(p_supplier), 'app', p_created_by)
  returning event_ref into v_event_ref;

  -- balanced ledger (single statement for the statement-level balance trigger)
  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select e.id, x.seq, a.id, x.dr, x.cr
  from app.events e,
       (values (1, (select code from app.accounts where kind = 'inventory' and code = case v_product.form when 'raw' then '1200' when 'bulk_processed' then '1210' when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end), p_landed_cost_paisa, 0::bigint),
               (2, v_credit_account, 0::bigint, p_landed_cost_paisa)) as x(seq, acc_code, dr, cr)
  join app.accounts a on a.code = x.acc_code
  where e.event_ref = v_event_ref;

  -- movement (value positive on receipt)
  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  select e.id, 1, v_product.id, v_batch_id, v_location.id, 'in', p_qty_grams, p_landed_cost_paisa
  from app.events e where e.event_ref = v_event_ref;

  return jsonb_build_object('event_ref', v_event_ref, 'batch_code', v_batch_code);
end $function$;

CREATE OR REPLACE FUNCTION public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text DEFAULT NULL::text, p_created_by uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text, p_cost_components jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_product app.products%rowtype;
  v_location app.locations%rowtype;
  v_batch_code text;
  v_batch_id integer;
  v_event_ref text;
  v_event_id integer;
  v_credit_account text;
  v_comp jsonb;
  v_comp_sum bigint := 0;
  v_comp_count integer := 0;
begin
  if p_idempotency_key is not null and exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
    return jsonb_build_object('duplicate', true);
  end if;
  if p_supplier is null or btrim(p_supplier) = '' then
    raise exception 'INVARIANT VIOLATION: supplier name is required' using errcode = 'check_violation';
  end if;
  if p_qty_grams is null or p_qty_grams <= 0 then
    raise exception 'INVARIANT VIOLATION: quantity must be positive' using errcode = 'check_violation';
  end if;
  if p_landed_cost_paisa is null or p_landed_cost_paisa <= 0 then
    raise exception 'INVARIANT VIOLATION: landed cost must be positive' using errcode = 'check_violation';
  end if;

  select * into v_product from app.products where code = p_product_code;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown product code %', p_product_code using errcode = 'check_violation';
  end if;
  select * into v_location from app.locations where code = p_location_code;
  if not found then
    raise exception 'INVARIANT VIOLATION: unknown location code %', p_location_code using errcode = 'check_violation';
  end if;

  if p_cost_components is not null then
    if jsonb_typeof(p_cost_components) <> 'array' then
      raise exception 'INVARIANT VIOLATION: cost_components must be an array' using errcode = 'check_violation';
    end if;
    for v_comp in select * from jsonb_array_elements(p_cost_components) loop
      v_comp_count := v_comp_count + 1;
      if v_comp ->> 'component' not in ('purchase','freight_inbound','loading','other') then
        raise exception 'INVARIANT VIOLATION: unknown cost component %', v_comp ->> 'component' using errcode = 'check_violation';
      end if;
      if coalesce((v_comp ->> 'amount_paisa')::bigint, 0) <= 0 then
        raise exception 'INVARIANT VIOLATION: cost component % amount must be positive', v_comp ->> 'component' using errcode = 'check_violation';
      end if;
      v_comp_sum := v_comp_sum + (v_comp ->> 'amount_paisa')::bigint;
    end loop;
    if v_comp_sum <> p_landed_cost_paisa then
      raise exception 'INVARIANT VIOLATION: cost components sum to % but landed cost is % - they must match exactly (no double counting)',
        (v_comp_sum / 100.0)::numeric(14,2), (p_landed_cost_paisa / 100.0)::numeric(14,2) using errcode = 'check_violation';
    end if;
  end if;

  v_batch_code := 'BATCH-' || lpad(nextval('app.batch_ref_seq')::text, 3, '0');
  while exists (select 1 from app.batches where batch_code = v_batch_code) loop
    v_batch_code := 'BATCH-' || lpad(nextval('app.batch_ref_seq')::text, 3, '0');
  end loop;

  insert into app.batches (batch_code, product_id, location_id, opened_on, note)
  values (v_batch_code, v_product.id, v_location.id, p_occurred_on,
          'Purchased from ' || btrim(p_supplier) || coalesce(' - ' || nullif(btrim(p_note), ''), ''))
  returning id into v_batch_id;

  v_credit_account := case when p_pay_cash then '1000' else '2000' end;

  with ins as (
    insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, created_by, idempotency_key)
    values (app.next_event_ref(), 'purchase', p_occurred_on,
            'Salt purchase from ' || btrim(p_supplier) || ' - ' || (p_qty_grams / 1000.0)::numeric(12,1) ||
            ' kg, landed cost ' || (p_landed_cost_paisa / 100.0)::numeric(14,2) || ' PKR, batch ' || v_batch_code,
            'supplier', btrim(p_supplier), 'app', p_created_by, p_idempotency_key)
    returning id, event_ref
  )
  select event_ref, id into v_event_ref, v_event_id from ins;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select v_event_id, x.seq, a.id, x.dr, x.cr
  from (values (1, case v_product.form when 'raw' then '1200' when 'bulk_processed' then '1210' when 'packaged' then '1220' when 'packaging_material' then '1230' else '1500' end, p_landed_cost_paisa, 0::bigint),
               (2, v_credit_account, 0::bigint, p_landed_cost_paisa)) as x(seq, acc_code, dr, cr)
  join app.accounts a on a.code = x.acc_code;

  insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
  values (v_event_id, 1, v_product.id, v_batch_id, v_location.id, 'in', p_qty_grams, p_landed_cost_paisa);

  if v_comp_count > 0 then
    insert into app.batch_cost_components (batch_id, component, amount_paisa, event_id, note)
    select v_batch_id, ce.comp_obj ->> 'component', (ce.comp_obj ->> 'amount_paisa')::bigint, v_event_id, ce.comp_obj ->> 'note'
    from jsonb_array_elements(p_cost_components) as ce(comp_obj);
  end if;

  return jsonb_build_object('event_ref', v_event_ref, 'batch_code', v_batch_code);
end $function$;

CREATE OR REPLACE FUNCTION public.record_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_party_name text := btrim(coalesce(p_party, ''));
  v_cash bigint := coalesce(p_cash_received_paisa, 0);
  v_party app.parties%rowtype;
  v_party_created boolean := false;
  v_sale_id integer;
  v_sale_ref text;
  v_event_ref text;
  v_lines jsonb := '[]'::jsonb;
  v_item jsonb;
  v_qty_grams bigint;
  v_price bigint;
  v_line_rev bigint;
  v_revenue bigint := 0;
  v_product app.products%rowtype;
  v_adv_balance bigint := 0;
  v_apply bigint := 0;
  v_ar bigint;
  i integer;
begin
  if v_party_name = '' then
    raise exception 'INVARIANT VIOLATION: customer is required' using errcode = 'check_violation';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'INVARIANT VIOLATION: at least one sale line is required' using errcode = 'check_violation';
  end if;
  if v_cash < 0 then
    raise exception 'INVARIANT VIOLATION: cash received cannot be negative' using errcode = 'check_violation';
  end if;

  if p_idempotency_key is not null then
    if exists (select 1 from app.sales where idempotency_key = p_idempotency_key) then
      select id, sale_ref, total_revenue_paisa, cash_received_paisa, advance_applied_paisa, ar_paisa
        into v_sale_id, v_sale_ref, v_revenue, v_cash, v_apply, v_ar
      from app.sales where idempotency_key = p_idempotency_key;
      return jsonb_build_object('duplicate', true, 'sale_ref', v_sale_ref, 'revenue_paisa', v_revenue,
        'cash_paisa', v_cash, 'advance_applied_paisa', v_apply, 'ar_paisa', v_ar);
    end if;
    if exists (select 1 from app.events where idempotency_key = p_idempotency_key) then
      return jsonb_build_object('duplicate', true);
    end if;
  end if;

  select * into v_party from app.parties where kind = 'customer' and lower(name) = lower(v_party_name);
  if not found then
    v_party_created := true;
    insert into app.parties (party_ref, name, phone, kind)
    values (app.next_party_ref(), v_party_name, nullif(btrim(coalesce(p_customer_phone, '')), ''), 'customer')
    returning * into v_party;
  end if;

  for i in 0 .. jsonb_array_length(p_items) - 1 loop
    v_item := p_items -> i;
    if v_item ? 'qty_grams' then
      v_qty_grams := round((v_item ->> 'qty_grams')::numeric)::bigint;
    else
      v_qty_grams := round((v_item ->> 'qty_kg')::numeric * 1000)::bigint;
    end if;
    v_price := coalesce((v_item ->> 'unit_price_paisa_per_kg')::bigint, (v_item ->> 'unit_price_paisa')::bigint, 0);
    if v_qty_grams is null or v_qty_grams <= 0 then
      raise exception 'INVARIANT VIOLATION: quantity must be positive (line %)', i + 1 using errcode = 'check_violation';
    end if;
    if v_item ? 'line_total_paisa' then
      v_line_rev := round((v_item ->> 'line_total_paisa')::numeric)::bigint;
      if v_line_rev is null or v_line_rev <= 0 then
        raise exception 'INVARIANT VIOLATION: line total must be positive (line %)', i + 1 using errcode = 'check_violation';
      end if;
      v_price := round(v_line_rev::numeric * 1000 / v_qty_grams);
    else
      if v_price <= 0 then
        raise exception 'INVARIANT VIOLATION: unit price must be positive (line %)', i + 1 using errcode = 'check_violation';
      end if;
      v_line_rev := round(v_qty_grams::numeric * v_price / 1000.0)::bigint;
    end if;
    select * into v_product from app.products where code = v_item ->> 'product_code';
    if not found then
      raise exception 'INVARIANT VIOLATION: unknown product code %', v_item ->> 'product_code' using errcode = 'check_violation';
    end if;
    v_revenue := v_revenue + v_line_rev;
    v_lines := v_lines || jsonb_build_object('line_no', i + 1, 'product_id', v_product.id,
      'product_code', v_product.code, 'qty_grams', v_qty_grams,
      'unit_price_paisa_per_kg', v_price, 'revenue_paisa', v_line_rev);
  end loop;

  with agg as (
    select sum(case when direction = 'received' then 1 else 0 end) as n_recv,
           sum(case when direction = 'applied' then 1 else 0 end) as n_appl,
           coalesce(sum(case when direction = 'received' then amount_paisa else -amount_paisa end), 0) as bal
    from app.customer_advances where party_id = v_party.id
  )
  select case when n_recv >= n_appl then bal else 0 end into v_adv_balance from agg;

  v_apply := least(greatest(v_adv_balance, 0), v_revenue);
  if v_apply > v_adv_balance then
    raise exception 'INVARIANT VIOLATION: advance application (%) exceeds available advance balance (%)',
      (v_apply / 100.0)::numeric(14,2), (v_adv_balance / 100.0)::numeric(14,2)
      using errcode = 'check_violation';
  end if;
  if v_cash + v_apply > v_revenue then
    raise exception 'INVARIANT VIOLATION: cash (%) plus advance application (%) exceeds invoice total (%)',
      (v_cash / 100.0)::numeric(14,2), (v_apply / 100.0)::numeric(14,2), (v_revenue / 100.0)::numeric(14,2)
      using errcode = 'check_violation';
  end if;
  v_ar := v_revenue - v_cash - v_apply;

  v_sale_ref := app.next_sale_ref();

  insert into app.sales (sale_ref, party_id, status, occurred_on, total_revenue_paisa,
                         cash_received_paisa, advance_applied_paisa, ar_paisa, idempotency_key, note, created_by)
  values (v_sale_ref, v_party.id, 'invoiced', p_occurred_on, v_revenue, v_cash, v_apply, v_ar, p_idempotency_key, p_note, p_created_by)
  returning id into v_sale_id;

  insert into app.sale_lines (sale_id, line_no, product_id, qty_grams, unit_price_paisa_per_kg, revenue_paisa)
  select v_sale_id, (l ->> 'line_no')::int, (l ->> 'product_id')::smallint, (l ->> 'qty_grams')::bigint,
         (l ->> 'unit_price_paisa_per_kg')::bigint, (l ->> 'revenue_paisa')::bigint
  from jsonb_array_elements(v_lines) l;

  insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_id, party_name, source, created_by, idempotency_key)
  values (app.next_event_ref(), 'sale', p_occurred_on,
    'Invoice ' || v_sale_ref || ' to ' || v_party.name || ' - ' || (v_revenue / 100.0)::numeric(14,2) || ' PKR'
    || case when v_cash > 0 then ' (cash ' || (v_cash / 100.0)::numeric(14,2) || ')' else '' end
    || case when v_apply > 0 then ' (advance applied ' || (v_apply / 100.0)::numeric(14,2) || ')' else '' end
    || case when v_ar > 0 then ' (receivable ' || (v_ar / 100.0)::numeric(14,2) || ')' else '' end
    || coalesce(' - ' || nullif(btrim(coalesce(p_note, '')), ''), ''),
    'customer', v_party.id, v_party.name, 'app', p_created_by, p_idempotency_key)
  returning event_ref into v_event_ref;

  insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
  select e.id, x.seq, a.id, x.dr, x.cr
  from app.events e
  join (values
    (1, '1000', v_cash, 0::bigint),
    (2, '2200', v_apply, 0::bigint),
    (3, '1100', v_ar, 0::bigint),
    (4, '4000', 0::bigint, v_revenue)
  ) as x(seq, acc_code, dr, cr) on true
  join app.accounts a on a.code = x.acc_code
  where e.event_ref = v_event_ref and x.dr > 0 or (e.event_ref = v_event_ref and x.acc_code = '4000');

  if v_apply > 0 then
    insert into app.customer_advances (event_id, party_id, direction, amount_paisa, occurred_on, note, created_by)
    select e.id, v_party.id, 'applied', v_apply, p_occurred_on, 'Applied to invoice ' || v_sale_ref, p_created_by
    from app.events e where e.event_ref = v_event_ref;
  end if;

  return jsonb_build_object('sale_ref', v_sale_ref, 'event_ref', v_event_ref,
    'party_ref', v_party.party_ref, 'party_created', v_party_created,
    'revenue_paisa', v_revenue, 'cash_paisa', v_cash,
    'advance_applied_paisa', v_apply, 'ar_paisa', v_ar,
    'lines', v_lines);
end
$function$;

CREATE OR REPLACE FUNCTION public.record_udhaar_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint DEFAULT 0, p_customer_phone text DEFAULT NULL::text, p_occurred_on date DEFAULT CURRENT_DATE, p_note text DEFAULT NULL::text, p_idempotency_key text DEFAULT NULL::text, p_created_by uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid, p_location_code text DEFAULT 'KHANEWAL_PLANT'::text)
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

CREATE OR REPLACE FUNCTION public.resolve_review_item(p_id integer, p_note text, p_dismissed boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
begin
  if p_note is null or btrim(p_note) = '' then
    raise exception 'INVARIANT VIOLATION: a resolution note is required — corrections must never be silent'
      using errcode = 'check_violation';
  end if;
  update app.review_queue
     set status = case when p_dismissed then 'dismissed' else 'resolved' end,
         resolution_note = p_note, resolved_at = now()
   where id = p_id and status = 'open';
  if not found then
    raise exception 'INVARIANT VIOLATION: review item % is not open (already resolved?)', p_id
      using errcode = 'check_violation';
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.suggest_sale_price(p_product_code text, p_location_code text, p_target_margin_pct numeric DEFAULT 15)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'app'
AS $function$
declare
  v_pid smallint; v_lid smallint;
  r record;
  v_qty bigint := 0; v_val numeric := 0;
  v_cost_ppk bigint;
begin
  select id into v_pid from app.products where code = p_product_code;
  if not found then raise exception 'INVARIANT VIOLATION: unknown product %', p_product_code using errcode = 'check_violation'; end if;
  select id into v_lid from app.locations where code = p_location_code;
  if not found then raise exception 'INVARIANT VIOLATION: unknown location %', p_location_code using errcode = 'check_violation'; end if;
  for r in select * from app.fifo_pool(v_pid, v_lid) loop
    v_qty := v_qty + r.onhand_grams;
    v_val := v_val + r.onhand_grams * r.unit_cost_ppk;
  end loop;
  if v_qty <= 0 then
    return jsonb_build_object('available', false);
  end if;
  v_cost_ppk := round((v_val / v_qty))::bigint;
  return jsonb_build_object('available', true, 'fifo_cost_paisa_per_kg', v_cost_ppk,
    'suggested_price_paisa_per_kg', round(v_cost_ppk * (100 + p_target_margin_pct) / 100.0),
    'available_grams', v_qty, 'target_margin_pct', p_target_margin_pct);
end $function$;


-- ============ 5. Views (live definitions, creation order) ============
create or replace view app.v_cash_summary as
 SELECT a.code AS account_code,
    COALESCE(sum(le.debit_paisa - le.credit_paisa), 0::numeric) AS balance_paisa
   FROM app.accounts a
     LEFT JOIN app.ledger_entries le ON le.account_id = a.id
  WHERE a.code = '1000'::text
  GROUP BY a.code;

create or replace view app.v_account_balances as
 SELECT a.code,
    a.name,
    a.type,
    a.kind,
    COALESCE(sum(le.debit_paisa - le.credit_paisa), 0::numeric) AS balance_paisa
   FROM app.accounts a
     LEFT JOIN app.ledger_entries le ON le.account_id = a.id
  GROUP BY a.code, a.name, a.type, a.kind
  ORDER BY a.code;

create or replace view app.v_stock_onhand as
 SELECT b.batch_code,
    p.code AS product_code,
    p.name AS product_name,
    l.code AS location_code,
    l.name AS location_name,
    sum(
        CASE
            WHEN m.direction = 'in'::text THEN m.qty_grams
            WHEN m.direction = 'out'::text THEN - m.qty_grams
            ELSE 0::bigint
        END) AS qty_grams,
    sum(m.value_paisa) AS value_paisa,
    sum(
        CASE
            WHEN m.direction = 'wastage'::text THEN m.qty_grams
            ELSE 0::bigint
        END) AS wastage_qty_grams,
    sum(
        CASE
            WHEN m.direction = 'wastage'::text THEN - m.value_paisa
            ELSE 0::bigint
        END) AS wastage_value_paisa
   FROM app.movements m
     JOIN app.batches b ON b.id = m.batch_id
     JOIN app.products p ON p.id = m.product_id
     JOIN app.locations l ON l.id = m.location_id
  GROUP BY b.batch_code, p.code, p.name, l.code, l.name;

create or replace view app.v_events_with_party as
 SELECT e.id,
    e.event_ref,
    e.event_type,
    e.occurred_on,
    e.description,
    e.party_type,
    e.party_name,
    e.source,
    e.source_ref,
    e.created_at,
    u.name AS created_by_name,
    ( SELECT COALESCE(sum(le.debit_paisa), 0::numeric) AS "coalesce"
           FROM app.ledger_entries le
          WHERE le.event_id = e.id) AS total_paisa
   FROM app.events e
     LEFT JOIN app.users u ON u.id = e.created_by;

create or replace view public.v_events_with_party with (security_invoker=true) as
 SELECT id,
    event_ref,
    event_type,
    occurred_on,
    description,
    party_type,
    party_name,
    source,
    source_ref,
    created_at,
    created_by_name,
    total_paisa
   FROM app.v_events_with_party;

create or replace view public.v_account_balances with (security_invoker=true) as
 SELECT code,
    name,
    type,
    kind,
    balance_paisa
   FROM app.v_account_balances;

create or replace view public.v_stock_onhand with (security_invoker=true) as
 SELECT batch_code,
    product_code,
    product_name,
    location_code,
    location_name,
    qty_grams,
    value_paisa,
    wastage_qty_grams,
    wastage_value_paisa
   FROM app.v_stock_onhand;

create or replace view public.v_accounts with (security_invoker=true) as
 SELECT id,
    code,
    name,
    type,
    kind
   FROM app.accounts;

create or replace view public.v_review_queue with (security_invoker=true) as
 SELECT id,
    source,
    severity,
    title,
    detail,
    source_ref,
    status,
    resolution_note,
    created_at,
    resolved_at,
    resolved_by
   FROM app.review_queue;

create or replace view public.v_ledger_lines with (security_invoker=true) as
 SELECT le.id,
    le.event_id,
    le.entry_seq,
    le.debit_paisa,
    le.credit_paisa,
    a.code AS account_code,
    a.name AS account_name
   FROM app.ledger_entries le
     JOIN app.accounts a ON a.id = le.account_id;

create or replace view public.v_products with (security_invoker=true) as
 SELECT id,
    code,
    name,
    form,
    base_unit,
    is_active
   FROM app.products
  ORDER BY name;

create or replace view public.v_locations with (security_invoker=true) as
 SELECT id,
    code,
    name,
    kind,
    is_active
   FROM app.locations
  ORDER BY name;

create or replace view public.v_batches with (security_invoker=true) as
 SELECT id,
    batch_code,
    product_id,
    product_code,
    product_name,
    location_id,
    location_code,
    location_name,
    status,
    opened_on,
    note,
    onhand_grams,
    value_paisa,
    wastage_grams,
    wastage_value_paisa
   FROM app.v_batches;

create or replace view app.v_batches as
 SELECT b.id,
    b.batch_code,
    b.product_id,
    p.code AS product_code,
    p.name AS product_name,
    b.location_id,
    l.code AS location_code,
    l.name AS location_name,
    b.status,
    b.opened_on,
    b.note,
    COALESCE(sum(
        CASE
            WHEN m.direction = 'in'::text THEN m.qty_grams
            WHEN m.direction = 'out'::text THEN - m.qty_grams
            ELSE 0::bigint
        END), 0::numeric) AS onhand_grams,
    COALESCE(sum(m.value_paisa), 0::numeric) AS value_paisa,
    COALESCE(sum(
        CASE
            WHEN m.direction = 'wastage'::text THEN m.qty_grams
            ELSE 0::bigint
        END), 0::numeric) AS wastage_grams,
    COALESCE(sum(
        CASE
            WHEN m.direction = 'wastage'::text THEN - m.value_paisa
            ELSE 0::bigint
        END), 0::numeric) AS wastage_value_paisa
   FROM app.batches b
     JOIN app.products p ON p.id = b.product_id
     JOIN app.locations l ON l.id = b.location_id
     LEFT JOIN app.movements m ON m.batch_id = b.id
  GROUP BY b.id, b.batch_code, b.product_id, p.code, p.name, b.location_id, l.code, l.name, b.status, b.opened_on, b.note;

create or replace view app.v_debtors as
 SELECT pt.id AS party_id,
    pt.party_ref,
    pt.name AS customer_name,
    pt.phone,
    COALESCE(sum(le.debit_paisa - le.credit_paisa), 0::numeric)::bigint AS outstanding_paisa,
    COALESCE(sum(le.debit_paisa), 0::numeric)::bigint AS total_invoiced_paisa,
    COALESCE(sum(le.credit_paisa), 0::numeric)::bigint AS total_paid_paisa,
    ( SELECT max(e2.occurred_on) AS max
           FROM app.events e2
          WHERE e2.party_id = pt.id AND e2.event_type = 'sale'::text) AS last_sale_on,
    ( SELECT max(e2.occurred_on) AS max
           FROM app.events e2
          WHERE e2.party_id = pt.id AND e2.event_type = 'customer_payment'::text) AS last_payment_on
   FROM app.parties pt
     JOIN app.events e ON e.party_id = pt.id
     JOIN app.ledger_entries le ON le.event_id = e.id
     JOIN app.accounts a ON a.id = le.account_id AND a.code = '1100'::text
  WHERE pt.kind = 'customer'::text
  GROUP BY pt.id, pt.party_ref, pt.name, pt.phone;

create or replace view public.v_debtors as
 SELECT party_id,
    party_ref,
    customer_name,
    phone,
    outstanding_paisa,
    total_invoiced_paisa,
    total_paid_paisa,
    last_sale_on,
    last_payment_on
   FROM app.v_debtors;

create or replace view public.v_parties as
 SELECT id,
    party_ref,
    name,
    phone,
    kind,
    is_active
   FROM app.parties;

create or replace view app.v_batch_costs as
 SELECT b.id AS batch_id,
    b.batch_code,
    p.code AS product_code,
    p.name AS product_name,
    l.code AS location_code,
    l.name AS location_name,
    b.status,
    b.opened_on,
    b.closed_on,
    COALESCE(sum(
        CASE
            WHEN c.component = 'purchase'::text THEN c.amount_paisa
            ELSE NULL::bigint
        END), 0::numeric) AS purchase_paisa,
    COALESCE(sum(
        CASE
            WHEN c.component = 'freight_inbound'::text THEN c.amount_paisa
            ELSE NULL::bigint
        END), 0::numeric) AS freight_inbound_paisa,
    COALESCE(sum(
        CASE
            WHEN c.component = 'loading'::text THEN c.amount_paisa
            ELSE NULL::bigint
        END), 0::numeric) AS loading_paisa,
    COALESCE(sum(
        CASE
            WHEN c.component = 'other'::text THEN c.amount_paisa
            ELSE NULL::bigint
        END), 0::numeric) AS other_paisa,
        CASE
            WHEN COALESCE(sum(c.amount_paisa), 0::numeric) > 0::numeric THEN COALESCE(sum(c.amount_paisa), 0::numeric)
            ELSE COALESCE(mv.opening_value, 0::numeric)
        END AS landed_cost_paisa,
    mv.opening_grams AS acquired_grams,
        CASE
            WHEN mv.opening_grams > 0::numeric THEN round(
            CASE
                WHEN COALESCE(sum(c.amount_paisa), 0::numeric) > 0::numeric THEN COALESCE(sum(c.amount_paisa), 0::numeric)
                ELSE COALESCE(mv.opening_value, 0::numeric)
            END / (mv.opening_grams / 1000.0))
            ELSE 0::numeric
        END AS initial_cost_ppk
   FROM app.batches b
     JOIN app.products p ON p.id = b.product_id
     JOIN app.locations l ON l.id = b.location_id
     LEFT JOIN app.batch_cost_components c ON c.batch_id = b.id
     LEFT JOIN ( SELECT movements.batch_id,
            sum(movements.qty_grams) AS opening_grams,
            sum(movements.value_paisa) AS opening_value
           FROM app.movements
          WHERE movements.direction = 'in'::text
          GROUP BY movements.batch_id) mv ON mv.batch_id = b.id
  GROUP BY b.id, p.code, p.name, l.code, l.name, mv.opening_grams, mv.opening_value;

create or replace view app.v_dispatch_allocations as
 SELECT d.dispatch_ref,
    d.occurred_on,
    s.sale_ref,
    pt.name AS customer_name,
    p.code AS product_code,
    p.name AS product_name,
    b.batch_code,
    da.qty_grams,
    da.unit_cost_paisa_per_kg,
    da.cogs_paisa,
    da.allocation_mode,
    da.override_reason,
    d.total_cogs_paisa
   FROM app.dispatch_allocations da
     JOIN app.dispatches d ON d.id = da.dispatch_id
     JOIN app.sales s ON s.id = d.sale_id
     JOIN app.parties pt ON pt.id = s.party_id
     JOIN app.batches b ON b.id = da.batch_id
     JOIN app.products p ON p.id = b.product_id;

create or replace view app.v_sales as
 SELECT s.id,
    s.sale_ref,
    s.occurred_on,
    pt.name AS customer_name,
    pt.party_ref,
    s.status,
    s.currency,
    s.fx_rate,
    s.total_revenue_paisa,
    s.cash_received_paisa,
    s.advance_applied_paisa,
    s.ar_paisa,
    COALESCE(d.total_cogs_paisa, 0::numeric) AS cogs_paisa,
    s.total_revenue_paisa::numeric - COALESCE(d.total_cogs_paisa, 0::numeric) AS gross_profit_paisa,
        CASE
            WHEN COALESCE(d.total_cogs_paisa, 0::numeric) > 0::numeric THEN round(100.0 * (s.total_revenue_paisa::numeric - d.total_cogs_paisa) / d.total_cogs_paisa, 2)
            ELSE NULL::numeric
        END AS gross_margin_pct,
    COALESCE(dq.dispatched_grams, 0::numeric) AS dispatched_grams,
    sl.qty_grams AS invoiced_grams
   FROM app.sales s
     JOIN app.parties pt ON pt.id = s.party_id
     LEFT JOIN ( SELECT dispatches.sale_id,
            sum(dispatches.total_cogs_paisa) AS total_cogs_paisa
           FROM app.dispatches
          GROUP BY dispatches.sale_id) d ON d.sale_id = s.id
     LEFT JOIN ( SELECT d2.sale_id,
            sum(da.qty_grams) AS dispatched_grams
           FROM app.dispatch_allocations da
             JOIN app.dispatches d2 ON d2.id = da.dispatch_id
          GROUP BY d2.sale_id) dq ON dq.sale_id = s.id
     LEFT JOIN ( SELECT sale_lines.sale_id,
            sum(sale_lines.qty_grams) AS qty_grams
           FROM app.sale_lines
          GROUP BY sale_lines.sale_id) sl ON sl.sale_id = s.id;

create or replace view public.v_sales with (security_invoker=true) as
 SELECT id,
    sale_ref,
    occurred_on,
    customer_name,
    party_ref,
    status,
    currency,
    fx_rate,
    total_revenue_paisa,
    cash_received_paisa,
    advance_applied_paisa,
    ar_paisa,
    cogs_paisa,
    gross_profit_paisa,
    gross_margin_pct,
    dispatched_grams,
    invoiced_grams
   FROM app.v_sales;

create or replace view public.v_batch_costs with (security_invoker=true) as
 SELECT batch_id,
    batch_code,
    product_code,
    product_name,
    location_code,
    location_name,
    status,
    opened_on,
    closed_on,
    purchase_paisa,
    freight_inbound_paisa,
    loading_paisa,
    other_paisa,
    landed_cost_paisa,
    acquired_grams,
    initial_cost_ppk
   FROM app.v_batch_costs;

create or replace view public.v_dispatch_allocations with (security_invoker=true) as
 SELECT dispatch_ref,
    occurred_on,
    sale_ref,
    customer_name,
    product_code,
    product_name,
    batch_code,
    qty_grams,
    unit_cost_paisa_per_kg,
    cogs_paisa,
    allocation_mode,
    override_reason,
    total_cogs_paisa
   FROM app.v_dispatch_allocations;

create or replace view public.v_advances with (security_invoker=true) as
 SELECT pt.id AS party_id,
    pt.party_ref,
    pt.name AS customer_name,
    pt.phone,
    COALESCE(sum(
        CASE
            WHEN a.direction = 'received'::text THEN a.amount_paisa
            ELSE - a.amount_paisa
        END), 0::numeric)::bigint AS advance_balance_paisa
   FROM app.parties pt
     LEFT JOIN app.customer_advances a ON a.party_id = pt.id
  WHERE pt.kind = 'customer'::text
  GROUP BY pt.id, pt.party_ref, pt.name, pt.phone;

create or replace view public.v_customers with (security_invoker=true) as
 SELECT id AS party_id,
    party_ref,
    name,
    phone,
    is_active,
    created_at
   FROM app.parties pt
  WHERE kind = 'customer'::text;


-- ============ 6. Triggers, policies (ledger app) ============
create or replace trigger trg_events_balanced AFTER INSERT OR UPDATE OF event_type ON app.events FOR EACH ROW EXECUTE FUNCTION app.assert_event_balanced();
create or replace trigger trg_events_single_row AFTER INSERT ON app.events REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE FUNCTION app.restrict_single_statement_insert();
create or replace trigger trg_cash_nonneg AFTER INSERT OR DELETE ON app.ledger_entries FOR EACH STATEMENT EXECUTE FUNCTION app.assert_cash_nonnegative();
create or replace trigger trg_ledger_balanced AFTER INSERT ON app.ledger_entries REFERENCING NEW TABLE AS ins_rows FOR EACH STATEMENT EXECUTE FUNCTION app.assert_ledger_events_balanced();
create or replace trigger trg_stock_nonneg AFTER INSERT ON app.movements FOR EACH ROW EXECUTE FUNCTION app.assert_stock_nonnegative();

drop policy if exists anon_read on app.accounts;
create policy anon_read on app.accounts as permissive for select to anon using (true);
drop policy if exists read_only on app.batch_cost_components;
create policy read_only on app.batch_cost_components as permissive for select to anon, authenticated using (true);
drop policy if exists anon_read on app.batches;
create policy anon_read on app.batches as permissive for select to anon using (true);
drop policy if exists read_only on app.customer_advances;
create policy read_only on app.customer_advances as permissive for select to anon, authenticated using (true);
drop policy if exists read_only on app.dispatch_allocations;
create policy read_only on app.dispatch_allocations as permissive for select to anon, authenticated using (true);
drop policy if exists read_only on app.dispatches;
create policy read_only on app.dispatches as permissive for select to anon, authenticated using (true);
drop policy if exists anon_read on app.events;
create policy anon_read on app.events as permissive for select to anon using (true);
drop policy if exists anon_read on app.ledger_entries;
create policy anon_read on app.ledger_entries as permissive for select to anon using (true);
drop policy if exists anon_read on app.locations;
create policy anon_read on app.locations as permissive for select to anon using (true);
drop policy if exists anon_read on app.movements;
create policy anon_read on app.movements as permissive for select to anon using (true);
drop policy if exists "parties read" on app.parties;
create policy "parties read" on app.parties as permissive for select to public using (true);
drop policy if exists anon_read on app.products;
create policy anon_read on app.products as permissive for select to anon using (true);
drop policy if exists anon_read on app.review_queue;
create policy anon_read on app.review_queue as permissive for select to anon using (true);
drop policy if exists read_only on app.sale_lines;
create policy read_only on app.sale_lines as permissive for select to anon, authenticated using (true);
drop policy if exists read_only on app.sales;
create policy read_only on app.sales as permissive for select to anon, authenticated using (true);
drop policy if exists anon_read on app.stg_excel_cash;
create policy anon_read on app.stg_excel_cash as permissive for select to anon using (true);
drop policy if exists anon_read on app.users;
create policy anon_read on app.users as permissive for select to anon using (true);


-- ============ 7. Grants (exactly as live on 2026-09-27; Task 3 changes them in a later migration) ============
grant usage on schema app to anon;
grant usage on schema app to authenticated;
grant select on table app.accounts to anon;
grant select on table app.accounts to authenticated;
grant select on table app.batch_cost_components to anon;
grant select on table app.batch_cost_components to authenticated;
grant select on sequence app.batch_ref_seq to anon;
grant select on sequence app.batch_ref_seq to authenticated;
grant select on table app.batches to anon;
grant select on table app.batches to authenticated;
grant select on table app.customer_advances to anon;
grant select on table app.customer_advances to authenticated;
grant select on table app.dispatch_allocations to anon;
grant select on table app.dispatch_allocations to authenticated;
grant select on table app.dispatches to anon;
grant select on table app.dispatches to authenticated;
grant select on sequence app.event_ref_seq to anon;
grant select on sequence app.event_ref_seq to authenticated;
grant select on table app.events to anon;
grant select on table app.events to authenticated;
grant select on table app.ledger_entries to anon;
grant select on table app.ledger_entries to authenticated;
grant select on table app.locations to anon;
grant select on table app.locations to authenticated;
grant select on table app.movements to anon;
grant select on table app.movements to authenticated;
grant select on table app.parties to anon;
grant select on table app.parties to authenticated;
grant select on table app.products to anon;
grant select on table app.products to authenticated;
grant select on table app.review_queue to anon;
grant select on table app.review_queue to authenticated;
grant select on table app.sale_lines to anon;
grant select on table app.sale_lines to authenticated;
grant select on table app.sales to anon;
grant select on table app.sales to authenticated;
grant select on table app.stg_excel_cash to anon;
grant select on table app.stg_excel_cash to authenticated;
grant select on table app.users to anon;
grant select on table app.users to authenticated;
grant select on table app.v_account_balances to anon;
grant select on table app.v_account_balances to authenticated;
grant select on table app.v_batch_costs to anon;
grant select on table app.v_batch_costs to authenticated;
grant select on table app.v_batches to anon;
grant select on table app.v_batches to authenticated;
grant select on table app.v_cash_summary to anon;
grant select on table app.v_cash_summary to authenticated;
grant select on table app.v_debtors to anon;
grant select on table app.v_debtors to authenticated;
grant select on table app.v_dispatch_allocations to anon;
grant select on table app.v_dispatch_allocations to authenticated;
grant select on table app.v_events_with_party to anon;
grant select on table app.v_events_with_party to authenticated;
grant select on table app.v_sales to anon;
grant select on table app.v_sales to authenticated;
grant select on table app.v_stock_onhand to anon;
grant select on table app.v_stock_onhand to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_account_balances to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_account_balances to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_account_balances to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_accounts to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_accounts to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_accounts to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_advances to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_advances to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_advances to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_batch_costs to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_batch_costs to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_batch_costs to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_batches to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_batches to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_batches to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_customers to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_customers to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_customers to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_debtors to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_debtors to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_debtors to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_dispatch_allocations to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_dispatch_allocations to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_dispatch_allocations to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_events_with_party to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_events_with_party to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_events_with_party to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_ledger_lines to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_ledger_lines to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_ledger_lines to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_locations to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_locations to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_locations to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_parties to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_parties to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_parties to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_products to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_products to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_products to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_review_queue to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_review_queue to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_review_queue to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_sales to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_sales to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_sales to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_stock_onhand to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_stock_onhand to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.v_stock_onhand to service_role;
grant execute on function app.batch_unit_cost_paisa_per_kg(p_batch_id integer) to anon;
grant execute on function app.batch_unit_cost_paisa_per_kg(p_batch_id integer) to authenticated;
grant execute on function app.batch_unit_cost_paisa_per_kg(p_batch_id integer) to public;
grant execute on function app.fifo_pool(p_product_id smallint, p_location_id smallint) to anon;
grant execute on function app.fifo_pool(p_product_id smallint, p_location_id smallint) to authenticated;
grant execute on function app.fifo_pool(p_product_id smallint, p_location_id smallint) to public;
grant execute on function app.record_advance(p_party text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to anon;
grant execute on function app.record_advance(p_party text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to authenticated;
grant execute on function app.record_advance(p_party text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to public;
grant execute on function public.create_customer(p_name text, p_phone text, p_note text) to anon;
grant execute on function public.create_customer(p_name text, p_phone text, p_note text) to authenticated;
grant execute on function public.create_customer(p_name text, p_phone text, p_note text) to public;
grant execute on function public.create_customer(p_name text, p_phone text, p_note text) to service_role;
grant execute on function public.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb, p_party_type text, p_party_name text, p_created_by uuid) to anon;
grant execute on function public.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb, p_party_type text, p_party_name text, p_created_by uuid) to authenticated;
grant execute on function public.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb, p_party_type text, p_party_name text, p_created_by uuid) to public;
grant execute on function public.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb, p_party_type text, p_party_name text, p_created_by uuid) to service_role;
grant execute on function public.record_customer_advance(p_customer text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to anon;
grant execute on function public.record_customer_advance(p_customer text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to authenticated;
grant execute on function public.record_customer_advance(p_customer text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to public;
grant execute on function public.record_customer_advance(p_customer text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to service_role;
grant execute on function public.record_customer_payment(p_customer text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text) to anon;
grant execute on function public.record_customer_payment(p_customer text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text) to authenticated;
grant execute on function public.record_customer_payment(p_customer text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text) to public;
grant execute on function public.record_customer_payment(p_customer text, p_amount_paisa bigint, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text) to service_role;
grant execute on function public.record_dispatch(p_sale_ref text, p_lines jsonb, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to anon;
grant execute on function public.record_dispatch(p_sale_ref text, p_lines jsonb, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to authenticated;
grant execute on function public.record_dispatch(p_sale_ref text, p_lines jsonb, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to public;
grant execute on function public.record_dispatch(p_sale_ref text, p_lines jsonb, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to service_role;
grant execute on function public.record_process_run(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid) to anon;
grant execute on function public.record_process_run(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid) to authenticated;
grant execute on function public.record_process_run(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid) to public;
grant execute on function public.record_process_run(p_input_batch_code text, p_input_qty_grams bigint, p_outputs jsonb, p_wastage_grams bigint, p_conversion_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid) to service_role;
grant execute on function public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid) to anon;
grant execute on function public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid) to authenticated;
grant execute on function public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid) to public;
grant execute on function public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid) to service_role;
grant execute on function public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text, p_cost_components jsonb) to anon;
grant execute on function public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text, p_cost_components jsonb) to authenticated;
grant execute on function public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text, p_cost_components jsonb) to public;
grant execute on function public.record_purchase(p_supplier text, p_product_code text, p_location_code text, p_qty_grams bigint, p_landed_cost_paisa bigint, p_pay_cash boolean, p_occurred_on date, p_note text, p_created_by uuid, p_idempotency_key text, p_cost_components jsonb) to service_role;
grant execute on function public.record_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to anon;
grant execute on function public.record_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to authenticated;
grant execute on function public.record_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to public;
grant execute on function public.record_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid) to service_role;
grant execute on function public.record_udhaar_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid, p_location_code text) to anon;
grant execute on function public.record_udhaar_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid, p_location_code text) to authenticated;
grant execute on function public.record_udhaar_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid, p_location_code text) to public;
grant execute on function public.record_udhaar_sale(p_party text, p_items jsonb, p_cash_received_paisa bigint, p_customer_phone text, p_occurred_on date, p_note text, p_idempotency_key text, p_created_by uuid, p_location_code text) to service_role;
grant execute on function public.resolve_review_item(p_id integer, p_note text, p_dismissed boolean) to anon;
grant execute on function public.resolve_review_item(p_id integer, p_note text, p_dismissed boolean) to authenticated;
grant execute on function public.resolve_review_item(p_id integer, p_note text, p_dismissed boolean) to public;
grant execute on function public.resolve_review_item(p_id integer, p_note text, p_dismissed boolean) to service_role;
grant execute on function public.suggest_sale_price(p_product_code text, p_location_code text, p_target_margin_pct numeric) to anon;
grant execute on function public.suggest_sale_price(p_product_code text, p_location_code text, p_target_margin_pct numeric) to authenticated;
grant execute on function public.suggest_sale_price(p_product_code text, p_location_code text, p_target_margin_pct numeric) to public;
grant execute on function public.suggest_sale_price(p_product_code text, p_location_code text, p_target_margin_pct numeric) to service_role;


-- ============ 8. Migration history: phase0-2 were applied before history tracking ============
insert into supabase_migrations.schema_migrations (version, name) values
  ('20260918000000', 'phase0_init'),
  ('20260918010000', 'phase1_import'),
  ('20260918020000', 'phase2_inventory_ops')
on conflict (version) do nothing;


-- ============ 9. JARVIS tables (owned by the JARVIS assistant, not the ledger app; accessed via direct postgres connection) ============
create table if not exists public.contacts (
  email character varying(255) not null,
  contact_id character varying(50),
  deal_id character varying(50),
  company character varying(255),
  country character varying(50),
  source character varying(100),
  score integer,
  label character varying(20),
  cached_at timestamp with time zone default now(),
  constraint contacts_pkey PRIMARY KEY (email)
);

create table if not exists public.notifications (
  id integer default nextval('notifications_id_seq'::regclass) not null,
  event character varying(50),
  run_id character varying(50),
  received integer,
  processed integer,
  dropped integer,
  saved_hot integer,
  vault_warm integer,
  rejected integer,
  partial_failures integer,
  severity character varying(20),
  read_at timestamp with time zone,
  created_at timestamp with time zone default now(),
  constraint notifications_pkey PRIMARY KEY (id)
);

create table if not exists public.reject_log (
  id integer default nextval('reject_log_id_seq'::regclass) not null,
  lead_id character varying(100),
  email character varying(255),
  company character varying(255),
  country character varying(50),
  reject_reason character varying(100),
  reject_detail text,
  created_at timestamp with time zone default now(),
  constraint reject_log_pkey PRIMARY KEY (id)
);

create table if not exists public.research_leads (
  lead_id character varying(100) not null,
  email character varying(255) not null,
  company character varying(255),
  country character varying(50),
  name character varying(255),
  buyer_type character varying(100),
  source character varying(100),
  moq_fit boolean,
  score integer,
  label character varying(20),
  scoring_reasons text,
  enrichment_data jsonb,
  times_seen integer default 1,
  synced_at timestamp with time zone,
  sync_attempts integer default 0,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  constraint research_leads_pkey PRIMARY KEY (lead_id),
  constraint research_leads_email_key UNIQUE (email)
);

create table if not exists public.staging_candidates (
  id uuid default gen_random_uuid() not null,
  company_name text not null,
  website text,
  email text,
  country text not null,
  buyer_type text not null,
  product text not null,
  discovery_source text default 'unknown'::text not null,
  processed boolean default false not null,
  score integer,
  score_label text,
  routing text,
  created_at timestamp with time zone default now() not null,
  processed_at timestamp with time zone,
  constraint staging_candidates_pkey PRIMARY KEY (id),
  constraint valid_discovery_source CHECK ((discovery_source = ANY (ARRAY['trade data'::text, 'rfq'::text, 'referral'::text, 'linkedin'::text, 'cold list'::text, 'unknown'::text]))),
  constraint valid_label CHECK (((score_label IS NULL) OR (score_label = ANY (ARRAY['Hot'::text, 'Warm'::text, 'Cold'::text, 'ERROR'::text])))),
  constraint valid_score CHECK (((score IS NULL) OR ((score >= 0) AND (score <= 100))))
);

create index if not exists idx_contacts_contact_id ON public.contacts USING btree (contact_id);
create index if not exists idx_contacts_deal_id ON public.contacts USING btree (deal_id);
create index if not exists idx_notifications_created_at ON public.notifications USING btree (created_at DESC);
create index if not exists idx_notifications_read_at ON public.notifications USING btree (read_at) WHERE (read_at IS NULL);
create index if not exists idx_notifications_run_id ON public.notifications USING btree (run_id);
create index if not exists idx_notifications_severity ON public.notifications USING btree (severity);
create index if not exists idx_reject_log_created_at ON public.reject_log USING btree (created_at DESC);
create index if not exists idx_reject_log_email ON public.reject_log USING btree (email);
create index if not exists idx_reject_log_lead_id ON public.reject_log USING btree (lead_id);
create index if not exists idx_reject_log_reason ON public.reject_log USING btree (reject_reason);
create index if not exists idx_research_leads_created_at ON public.research_leads USING btree (created_at DESC);
create index if not exists idx_research_leads_email ON public.research_leads USING btree (email);
create index if not exists idx_research_leads_synced_at ON public.research_leads USING btree (synced_at) WHERE (synced_at IS NULL);
create index if not exists idx_staging_email ON public.staging_candidates USING btree (email) WHERE (email IS NOT NULL);
create index if not exists idx_staging_processed ON public.staging_candidates USING btree (processed, created_at);
create index if not exists idx_staging_routing ON public.staging_candidates USING btree (routing, created_at) WHERE (processed = true);

alter table public.staging_candidates enable row level security;

grant delete, insert, maintain, references, select, trigger, truncate, update on table public.contacts to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.contacts to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.contacts to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.notifications to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.notifications to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.notifications to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.reject_log to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.reject_log to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.reject_log to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.research_leads to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.research_leads to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.research_leads to service_role;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.staging_candidates to anon;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.staging_candidates to authenticated;
grant delete, insert, maintain, references, select, trigger, truncate, update on table public.staging_candidates to service_role;
