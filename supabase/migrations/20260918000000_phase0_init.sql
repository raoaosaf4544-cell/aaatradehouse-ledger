-- ============================================================
-- AAA Trade House Ledger — Phase 0: Foundations
-- Postgres 17 (Supabase). Idempotent, deterministic, no crypto randomness.
-- Money in paisa integers (BIGINT). Quantities in grams integers (BIGINT).
-- ============================================================

-- ---------- 0.1 Schema ----------
create schema if not exists app;

-- ---------- 0.2 Reference tables ----------

create table if not exists app.users (
  id           uuid primary key,
  name         text not null,
  role         text not null default 'owner' check (role in ('owner','operator','auditor')),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

create table if not exists app.locations (
  id          smallint primary key generated always as identity,
  code        text not null unique,
  name        text not null,
  kind        text not null default 'plant' check (kind in ('plant','warehouse','office','transit')),
  is_active   boolean not null default true
);

create table if not exists app.products (
  id          smallint primary key generated always as identity,
  code        text not null unique,
  name        text not null,
  form        text not null check (form in ('raw','bulk_processed','packaged','packaging_material','other_material')),
  base_unit   text not null default 'kg',
  is_active   boolean not null default true
);

-- Batch = accounting identity for inventory (purchase, crush run, packaging run).
-- Each batch belongs to ONE product (form) at ONE location.
create table if not exists app.batches (
  id              integer primary key generated always as identity,
  batch_code      text not null unique,
  product_id      smallint not null references app.products(id),
  location_id     smallint not null references app.locations(id),
  status          text not null default 'open' check (status in ('open','closed')),
  opened_on       date not null,
  closed_on       date,
  note            text
);

-- Chart of accounts: code is the stable business key; ids are surrogate.
create table if not exists app.accounts (
  id          smallint primary key generated always as identity,
  code        text not null unique,
  name        text not null,
  type        text not null check (type in ('asset','liability','equity','income','expense')),
  kind        text not null default 'general' check (kind in ('general','inventory','cash','bank','control','personal')),
  is_system   boolean not null default false,
  is_active   boolean not null default true
);

-- ---------- 0.3 Core append-only tables ----------

-- Events: what happened (the fact). One event per real-world occurrence.
create table if not exists app.events (
  id              integer primary key generated always as identity,
  event_ref       text not null unique,            -- e.g. CL-20260823-001 (imported) / EV-000001 (new)
  event_type      text not null check (event_type in (
                    'capital_injection','owner_drawing','expense','asset_purchase','asset_disposal',
                    'purchase','purchase_payment','supplier_return',
                    'process_run','packaging_run','transfer','stock_adjustment',
                    'sale','dispatch','customer_return','customer_payment','customer_advance',
                    'opening_inventory','inventory_reval','other')),
  occurred_on     date not null,
  description     text not null,
  party_type      text check (party_type in ('customer','supplier','owner','employee','other')),
  party_name      text,
  source          text not null default 'app' check (source in ('excel_import','app','correction','system')),
  source_ref      text,                             -- excel transaction id, etc.
  created_by      uuid references app.users(id),
  created_at      timestamptz not null default now()
);

create index if not exists idx_events_date on app.events (occurred_on);
create index if not exists idx_events_type on app.events (event_type);
create index if not exists idx_events_party on app.events (party_type, party_name);

-- Ledger entries: double-entry money lines, append-only, balanced per event.
create table if not exists app.ledger_entries (
  id            bigint primary key generated always as identity,
  event_id      integer not null references app.events(id),
  entry_seq     smallint not null,                 -- ordering within event
  account_id    smallint not null references app.accounts(id),
  debit_paisa   bigint not null default 0 check (debit_paisa  >= 0),
  credit_paisa  bigint not null default 0 check (credit_paisa >= 0),
  check (not (debit_paisa > 0 and credit_paisa > 0)),
  check (debit_paisa > 0 or credit_paisa > 0),
  unique (event_id, entry_seq)
);

create index if not exists idx_ledger_event on app.ledger_entries (event_id);
create index if not exists idx_ledger_account on app.ledger_entries (account_id);

-- Movements: append-only stock lines. On-hand qty/weight = SUM per (batch,location).
create table if not exists app.movements (
  id            bigint primary key generated always as identity,
  event_id      integer not null references app.events(id),
  movement_seq  smallint not null,
  product_id    smallint not null references app.products(id),
  batch_id      integer not null references app.batches(id),
  location_id   smallint not null references app.locations(id),
  direction     text not null check (direction in ('in','out','wastage')),
  qty_grams     bigint not null,                   -- positive number; direction carries the sign
  value_paisa   bigint not null default 0,         -- inventory value of this movement (signed: in +, out -)
  check (qty_grams > 0),
  unique (event_id, movement_seq)
);

create index if not exists idx_mov_batch_loc on app.movements (batch_id, location_id);
create index if not exists idx_mov_product on app.movements (product_id);

-- Queue for anything we refuse to auto-classify (imported 'UNCLEAR' lines, review flags).
create table if not exists app.review_queue (
  id            integer primary key generated always as identity,
  source        text not null check (source in ('excel_import','invariant','app','correction')),
  severity      text not null default 'needs_review' check (severity in ('info','needs_review','critical')),
  title         text not null,
  detail        jsonb not null default '{}'::jsonb,
  source_ref    text,                                -- e.g. excel transaction id
  status        text not null default 'open' check (status in ('open','resolved','dismissed')),
  resolution_note text,
  created_at    timestamptz not null default now(),
  resolved_at   timestamptz,
  resolved_by   uuid references app.users(id)
);

create index if not exists idx_review_status on app.review_queue (status);

-- ---------- 0.4 Sequences for human refs ----------
create sequence if not exists app.event_ref_seq start 1;
create sequence if not exists app.batch_ref_seq start 1;

create or replace function app.next_event_ref()
returns text language sql as
$$ select 'EV-' || lpad(nextval('app.event_ref_seq')::text, 6, '0') $$;

-- ---------- 0.5 Seed: users ----------
insert into app.users (id, name, role) values
  ('11111111-1111-1111-1111-111111111111', 'Ahsan (Owner)', 'owner'),
  ('22222222-2222-2222-2222-222222222222', 'Father (Owner)', 'owner'),
  ('33333333-3333-3333-3333-333333333333', 'System (Import)', 'operator')
on conflict (id) do nothing;

-- ---------- 0.6 Seed: locations, products, chart of accounts ----------
insert into app.locations (code, name, kind) values
  ('KHANEWAL_PLANT', 'Khanewal Plant', 'plant'),
  ('LAHORE_OFFICE',  'Lahore Office',  'office'),
  ('TRANSIT',        'In Transit',     'transit')
on conflict (code) do nothing;

insert into app.products (code, name, form) values
  ('SALT_RAW',   'Raw Rock Salt (uncrushed)', 'raw'),
  ('SALT_BULK',  'Bulk Crushed Salt (any grade, unpackaged)', 'bulk_processed'),
  ('PKG_MAT',    'Packaging Material (bags etc.)', 'packaging_material')
on conflict (code) do nothing;

insert into app.accounts (code, name, type, kind) values
  -- Assets
  ('1000', 'Cash on Hand',                        'asset',   'cash'),
  ('1050', 'Cash — Bank (future use)',            'asset',   'bank'),
  ('1100', 'Accounts Receivable — Trade',         'asset',   'control'),
  ('1200', 'Inventory — Raw Salt',                'asset',   'inventory'),
  ('1210', 'Inventory — Bulk Processed Salt',     'asset',   'inventory'),
  ('1220', 'Inventory — Packaged Goods',          'asset',   'inventory'),
  ('1230', 'Inventory — Packaging Material',      'asset',   'inventory'),
  ('1240', 'WIP — Consumption Pool (contra)',     'asset',   'inventory'),
  ('1300', 'Inventory — Work in Progress',        'asset',   'inventory'),
  ('1310', 'WIP — Processing Costs Pool',         'asset',   'inventory'),
  ('1400', 'Vehicle (Motorcycle)',                'asset',   'general'),
  ('1450', 'Livestock — Side Activity (Goats)',   'asset',   'general'),
  ('1500', 'Other Fixed Assets',                  'asset',   'general'),
  ('1900', 'Suspense / Unclassified',             'asset',   'control'),
  -- Liabilities
  ('2000', 'Accounts Payable — Trade',            'liability','control'),
  ('2050', 'Customer Advances',                   'liability','control'),
  ('2100', 'Accrued Expenses',                    'liability','control'),
  -- Equity
  ('3000', 'Owner Capital',                       'equity',  'general'),
  ('3100', 'Owner Drawings',                      'equity',  'personal'),
  ('3200', 'Retained Earnings',                   'equity',  'general'),
  -- Income
  ('4000', 'Salt Sales Revenue',                  'income',  'general'),
  ('4900', 'Other Income',                        'income',  'general'),
  -- Expenses
  ('5000', 'Labour',                              'expense', 'general'),
  ('5100', 'Utilities',                           'expense', 'general'),
  ('5200', 'Freight (delivery/selling)',          'expense', 'general'),
  ('5300', 'Fuel',                                'expense', 'general'),
  ('5400', 'Packaging Consumed (period expense)', 'expense', 'general'),
  ('5500', 'Site Meals & Welfare',                'expense', 'general'),
  ('5600', 'Travel',                              'expense', 'general'),
  ('5700', 'Repairs & Maintenance',               'expense', 'general'),
  ('5800', 'Admin & Office',                      'expense', 'general'),
  ('5900', 'Other Business Expense',              'expense', 'general'),
  ('5950', 'Personal/Unclassified (review)',      'expense', 'personal'),
  ('5990', 'Opening Balance Offset',              'expense', 'control')
on conflict (code) do nothing;

-- ---------- 0.7 Invariant guard functions ----------
-- Block-because-of-invariant rules: raise on violation. No silent failures.

-- Balanced double entry per event.
create or replace function app.assert_event_balanced()
returns trigger language plpgsql as $$
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
end $$;

-- NOTE: a per-row trigger on app.events cannot enforce balance (events are inserted
-- BEFORE their ledger lines). The real enforcement is the statement-level trigger on
-- app.ledger_entries below (trg_ledger_balanced), which validates whole events via
-- transition tables once all lines of a statement are present.

-- Cash can never go negative.
create or replace function app.assert_cash_nonnegative()
returns trigger language plpgsql as $$
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
end $$;

create trigger trg_cash_nonneg
after insert or delete on app.ledger_entries
for each statement execute function app.assert_cash_nonnegative();

-- Stock can never go negative for a batch at a location.
create or replace function app.assert_stock_nonnegative()
returns trigger language plpgsql as $$
declare r record;
begin
  for r in
    select batch_id, location_id, sum(case when direction='in' then qty_grams else -qty_grams end) as q
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
end $$;

create trigger trg_stock_nonneg
after insert on app.movements
for each row execute function app.assert_stock_nonnegative();

-- Statement-level double-entry balance enforcement (fires once per statement over
-- every event touched by that statement, AFTER all its lines exist).
create or replace function app.assert_ledger_events_balanced()
returns trigger language plpgsql as $$
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
end $$;

create trigger trg_ledger_balanced
after insert on app.ledger_entries
referencing new table as ins_rows
for each statement execute function app.assert_ledger_events_balanced();
