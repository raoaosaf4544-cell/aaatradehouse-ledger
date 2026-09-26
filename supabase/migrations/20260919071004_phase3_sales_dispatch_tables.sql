-- ============ Phase 3: sales, dispatch, advances, batch cost traceability ============

-- 1) Customer Advances liability (business decision: liability account 2200)
insert into app.accounts (code, name, type, kind, is_system, is_active)
values ('2200', 'Customer Advances', 'liability', 'control', true, true)
on conflict (code) do nothing;

-- 2) Invoices (revenue event; NEVER touches inventory)
create table if not exists app.sales (
  id integer generated always as identity primary key,
  sale_ref text not null unique,
  party_id integer not null references app.parties(id),
  status text not null default 'invoiced' check (status in ('invoiced','dispatched')),
  occurred_on date not null,
  currency text not null default 'PKR',
  fx_rate numeric(18,8) not null default 1,
  total_revenue_paisa bigint not null check (total_revenue_paisa > 0),
  cash_received_paisa bigint not null default 0 check (cash_received_paisa >= 0),
  advance_applied_paisa bigint not null default 0 check (advance_applied_paisa >= 0),
  ar_paisa bigint not null default 0 check (ar_paisa >= 0),
  idempotency_key text,
  note text,
  source text not null default 'app',
  created_by uuid,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_sales_idem on app.sales (idempotency_key) where idempotency_key is not null;
create index if not exists ix_sales_party on app.sales (party_id);

-- 3) Sale lines
create table if not exists app.sale_lines (
  id bigint generated always as identity primary key,
  sale_id integer not null references app.sales(id),
  line_no smallint not null,
  product_id smallint not null references app.products(id),
  qty_grams bigint not null check (qty_grams > 0),
  unit_price_paisa_per_kg bigint not null check (unit_price_paisa_per_kg > 0),
  price_source text not null default 'manual' check (price_source in ('manual','suggested')),
  revenue_paisa bigint not null check (revenue_paisa > 0),
  dispatched_grams bigint not null default 0 check (dispatched_grams >= 0),
  unique (sale_id, line_no)
);

-- 4) Dispatches (physical movement; the ONLY inventory deduction point)
create table if not exists app.dispatches (
  id integer generated always as identity primary key,
  dispatch_ref text not null unique,
  sale_id integer not null references app.sales(id),
  occurred_on date not null,
  total_cogs_paisa bigint not null check (total_cogs_paisa >= 0),
  idempotency_key text,
  note text,
  source text not null default 'app',
  created_by uuid,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_dispatch_idem on app.dispatches (idempotency_key) where idempotency_key is not null;
create index if not exists ix_dispatch_sale on app.dispatches (sale_id);

-- 5) Per-batch allocation records (FIFO vs manual audit)
create table if not exists app.dispatch_allocations (
  id bigint generated always as identity primary key,
  dispatch_id integer not null references app.dispatches(id),
  sale_line_id bigint not null references app.sale_lines(id),
  batch_id integer not null references app.batches(id),
  qty_grams bigint not null check (qty_grams > 0),
  unit_cost_paisa_per_kg bigint not null,
  cogs_paisa bigint not null check (cogs_paisa > 0),
  allocation_mode text not null check (allocation_mode in ('fifo','manual')),
  override_reason text,
  created_at timestamptz not null default now()
);
create index if not exists ix_alloc_dispatch on app.dispatch_allocations (dispatch_id);
create index if not exists ix_alloc_batch on app.dispatch_allocations (batch_id);

-- 6) Customer advances ledger (received / applied / refunded)
create table if not exists app.customer_advances (
  id bigint generated always as identity primary key,
  event_id integer not null references app.events(id),
  party_id integer not null references app.parties(id),
  direction text not null check (direction in ('received','applied','refunded')),
  amount_paisa bigint not null check (amount_paisa > 0),
  occurred_on date not null,
  currency text not null default 'PKR',
  fx_rate numeric(18,8) not null default 1,
  idempotency_key text,
  note text,
  source text not null default 'app',
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists ix_adv_party on app.customer_advances (party_id);
create unique index if not exists uq_adv_idem on app.customer_advances (idempotency_key) where idempotency_key is not null;

-- 7) Batch cost components (landed-cost traceability: purchase + freight + loading)
create table if not exists app.batch_cost_components (
  id bigint generated always as identity primary key,
  batch_id integer not null references app.batches(id),
  component text not null check (component in ('purchase','freight_inbound','loading','other')),
  amount_paisa bigint not null check (amount_paisa > 0),
  event_id integer references app.events(id),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists ix_bcc_batch on app.batch_cost_components (batch_id);

-- 8) Reference sequences
create sequence if not exists app.sale_ref_seq;
create sequence if not exists app.dispatch_ref_seq;

-- 9) Seed: BATCH-001 landed total (Excel import did not split components)
insert into app.batch_cost_components (batch_id, component, amount_paisa, note)
select b.id, 'purchase', mv.opening, 'Landed total from Excel import (components not split at import)'
from app.batches b
join (select batch_id, sum(value_paisa) as opening from app.movements where direction = 'in' group by batch_id) mv
  on mv.batch_id = b.id
where not exists (select 1 from app.batch_cost_components x where x.batch_id = b.id);

-- 10) Packaged products + packaging materials (units, not kg)
insert into app.products (code, name, form, base_unit, is_active) values
  ('SALT_PACK_1',  'Packaged Salt - 1 kg pouch',  'packaged', 'kg',    true),
  ('SALT_PACK_25', 'Packaged Salt - 25 kg bag',   'packaged', 'kg',    true),
  ('SALT_PACK_40', 'Packaged Salt - 40 kg bag',   'packaged', 'kg',    true),
  ('SALT_PACK_50', 'Packaged Salt - 50 kg bag',   'packaged', 'kg',    true),
  ('PKG_POUCH_1KG','Packaging: 1 kg pouch',       'packaging_material', 'units', true),
  ('PKG_BAG_25KG', 'Packaging: 25 kg bag',        'packaging_material', 'units', true),
  ('PKG_BAG_40KG', 'Packaging: 40 kg bag',        'packaging_material', 'units', true),
  ('PKG_BAG_50KG', 'Packaging: 50 kg bag',        'packaging_material', 'units', true)
on conflict (code) do nothing;
update app.products set base_unit = 'units' where form = 'packaging_material' and base_unit <> 'units';
update app.products set is_active = false where code = 'PKG_MAT' and not exists (
  select 1 from app.movements m join app.batches b on b.id = m.batch_id where b.product_id = app.products.id);