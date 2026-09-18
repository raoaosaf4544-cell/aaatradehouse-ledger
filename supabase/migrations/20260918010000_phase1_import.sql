-- ============================================================
-- AAA Trade House Ledger — Phase 1: Excel import (generated)
-- Source: AAA_Trade_House_Master_Ledger.xlsx | cash rows: 100 | generated deterministically
-- Money unit: paisa (PKR * 100)
-- ============================================================

-- ---------- 1. Staging (raw preservation of Excel rows) ----------
create table if not exists app.stg_excel_cash (
  txn_id text primary key,
  occurred_on date not null,
  category text,
  description text,
  money_in_paisa bigint not null default 0,
  money_out_paisa bigint not null default 0,
  running_balance_paisa bigint,
  month_key text
);

insert into app.stg_excel_cash (txn_id, occurred_on, category, description, money_in_paisa, money_out_paisa, running_balance_paisa, month_key) values
  ('CL-20260823-001', '2026-08-23', 'Capital', 'Opening cash / capital', 50000000, 0, 50000000, '2026-08'),
  ('CL-20260823-002', '2026-08-23', 'Utilities', 'Bill house', 0, 94200, 49905800, '2026-08'),
  ('CL-20260823-003', '2026-08-23', 'Utilities', 'Bill mobile', 0, 101600, 49804200, '2026-08'),
  ('CL-20260823-004', '2026-08-23', 'Admin', 'Bill shop', 0, 590800, 49213400, '2026-08'),
  ('CL-20260823-005', '2026-08-23', 'Other', 'UNCLEAR: Helmet Asif / Halmit Asaf', 0, 500000, 48713400, '2026-08'),
  ('CL-20260823-006', '2026-08-23', 'Utilities', 'UNCLEAR: labelled Rent office — owner owns plant; recode if electric/other', 0, 1710000, 47003400, '2026-08'),
  ('CL-20260824-007', '2026-08-24', 'Travel', 'Bus fare', 0, 120000, 46883400, '2026-08'),
  ('CL-20260824-008', '2026-08-24', 'Site Meals', 'Fruit', 0, 37000, 46846400, '2026-08'),
  ('CL-20260824-009', '2026-08-24', 'Travel', 'Indrive', 0, 20000, 46826400, '2026-08'),
  ('CL-20260824-010', '2026-08-24', 'Site Meals', 'Lunch', 0, 20000, 46806400, '2026-08'),
  ('CL-20260824-011', '2026-08-24', 'Other', 'UNCLEAR: Eisha for marriage (personal?)', 0, 1000000, 45806400, '2026-08'),
  ('CL-20260824-012', '2026-08-24', 'Travel', 'UNCLEAR: Skasi to Pasida', 0, 45000, 45761400, '2026-08'),
  ('CL-20260825-013', '2026-08-25', 'Site Meals', 'Dinner', 0, 25000, 45736400, '2026-08'),
  ('CL-20260825-014', '2026-08-25', 'Site Meals', 'Egg and soap', 0, 31000, 45705400, '2026-08'),
  ('CL-20260826-015', '2026-08-26', 'Site Meals', 'Dinner', 0, 34000, 45671400, '2026-08'),
  ('CL-20260826-016', '2026-08-26', 'Site Meals', 'Fruit', 0, 67000, 45604400, '2026-08'),
  ('CL-20260826-017', '2026-08-26', 'Site Meals', 'Yogurt', 0, 11000, 45593400, '2026-08'),
  ('CL-20260827-018', '2026-08-27', 'Site Meals', 'Breakfast', 0, 40000, 45553400, '2026-08'),
  ('CL-20260827-019', '2026-08-27', 'Travel', 'Fare Bahawalpur', 0, 65000, 45488400, '2026-08'),
  ('CL-20260827-020', '2026-08-27', 'Travel', 'Fare Indrive', 0, 15000, 45473400, '2026-08'),
  ('CL-20260827-021', '2026-08-27', 'Travel', 'Fare Khanewal / Multan', 0, 50000, 45423400, '2026-08'),
  ('CL-20260827-022', '2026-08-27', 'Other', 'UNCLEAR: Abda Abid ko diye', 0, 100000, 45323400, '2026-08'),
  ('CL-20260828-023', '2026-08-28', 'Travel', 'Fare Bahawalpur / Multan', 0, 65000, 45258400, '2026-08'),
  ('CL-20260828-024', '2026-08-28', 'Site Meals', 'Fruit', 0, 60000, 45198400, '2026-08'),
  ('CL-20260828-025', '2026-08-28', 'Travel', 'Indrive', 0, 15000, 45183400, '2026-08'),
  ('CL-20260828-026', '2026-08-28', 'Site Meals', 'Lunch', 0, 25000, 45158400, '2026-08'),
  ('CL-20260828-027', '2026-08-28', 'Repairs', 'Mobile repair', 0, 20000, 45138400, '2026-08'),
  ('CL-20260828-028', '2026-08-28', 'Other', 'Nasir ki beti ko diya', 0, 100000, 45038400, '2026-08'),
  ('CL-20260828-029', '2026-08-28', 'Fuel', 'Petrol', 0, 500000, 44538400, '2026-08'),
  ('CL-20260828-030', '2026-08-28', 'Travel', 'UNCLEAR: Fare Peshada', 0, 20000, 44518400, '2026-08'),
  ('CL-20260828-031', '2026-08-28', 'Site Meals', 'UNCLEAR: Tofft', 0, 48000, 44470400, '2026-08'),
  ('CL-20260829-032', '2026-08-29', 'Side Livestock', 'Bakri (goat + kid) purchase — SIDE ASSET not salt COGS', 0, 5500000, 38970400, '2026-08'),
  ('CL-20260829-033', '2026-08-29', 'Side Livestock', 'Bakri feed 5 kg', 0, 50000, 38920400, '2026-08'),
  ('CL-20260829-034', '2026-08-29', 'Site Meals', 'Lunch', 0, 60000, 38860400, '2026-08'),
  ('CL-20260829-035', '2026-08-29', 'Vehicle CapEx', 'Motorcycle advance — NEW BIKE', 0, 3500000, 35360400, '2026-08'),
  ('CL-20260829-036', '2026-08-29', 'Vehicle CapEx', 'Motorcycle repairing / fit-out with new bike', 0, 900000, 34460400, '2026-08'),
  ('CL-20260829-037', '2026-08-29', 'Site Meals', 'Patti (tea)', 0, 38000, 34422400, '2026-08'),
  ('CL-20260829-038', '2026-08-29', 'Fuel', 'Petrol', 0, 150000, 34272400, '2026-08'),
  ('CL-20260829-039', '2026-08-29', 'Labour', 'Qasim advance salary', 0, 1000000, 33272400, '2026-08'),
  ('CL-20260829-040', '2026-08-29', 'Labour', 'Qasim khana', 0, 50000, 33222400, '2026-08'),
  ('CL-20260829-041', '2026-08-29', 'Admin', 'Register', 0, 140000, 33082400, '2026-08'),
  ('CL-20260829-042', '2026-08-29', 'Other', 'UNCLEAR: Corur', 0, 45000, 33037400, '2026-08'),
  ('CL-20260829-043', '2026-08-29', 'Other', 'UNCLEAR: Jabaruko deya', 0, 10000, 33027400, '2026-08'),
  ('CL-20260830-044', '2026-08-30', 'Site Meals', 'Chicken', 0, 50000, 32977400, '2026-08'),
  ('CL-20260830-045', '2026-08-30', 'Site Meals', 'Egg biscuit cake', 0, 44000, 32933400, '2026-08'),
  ('CL-20260830-046', '2026-08-30', 'Vehicle CapEx', 'Motorcycle permit — NEW BIKE (confirm 75,000 vs book)', 0, 7500000, 25433400, '2026-08'),
  ('CL-20260830-047', '2026-08-30', 'Site Meals', 'Sabzi and chai', 0, 37000, 25396400, '2026-08'),
  ('CL-20260830-048', '2026-08-30', 'Other', 'UNCLEAR: Drmti CTC', 0, 50000, 25346400, '2026-08'),
  ('CL-20260830-049', '2026-08-30', 'Other', 'UNCLEAR: Tap for baksi water', 0, 110000, 25236400, '2026-08'),
  ('CL-20260831-050', '2026-08-31', 'Admin', 'Medicines', 0, 150000, 25086400, '2026-08'),
  ('CL-20260831-051', '2026-08-31', 'Repairs', 'Motorcycle repairing', 0, 200000, 24886400, '2026-08'),
  ('CL-20260831-052', '2026-08-31', 'Fuel', 'Petrol', 0, 50000, 24836400, '2026-08'),
  ('CL-20260831-053', '2026-08-31', 'Site Meals', 'Sabzi sarf etc', 0, 37000, 24799400, '2026-08'),
  ('CL-20260831-054', '2026-08-31', 'Admin', 'Stamp paper / photocopy', 0, 30000, 24769400, '2026-08'),
  ('CL-20260831-055', '2026-08-31', 'Other', 'UNCLEAR: Ghai-bursh kill', 0, 80000, 24689400, '2026-08'),
  ('CL-20260901-056', '2026-09-01', 'Site Meals', 'Chai', 0, 30000, 24659400, '2026-09'),
  ('CL-20260901-057', '2026-09-01', 'Vehicle CapEx', 'Helmet', 0, 550000, 24109400, '2026-09'),
  ('CL-20260901-058', '2026-09-01', 'Fuel', 'Petrol', 0, 100000, 24009400, '2026-09'),
  ('CL-20260902-059', '2026-09-02', 'Packaging', 'Bardaana 700 bags — first packing material', 0, 1150000, 22859400, '2026-09'),
  ('CL-20260902-060', '2026-09-02', 'Labour', 'Hamali (loading labour)', 0, 70000, 22789400, '2026-09'),
  ('CL-20260902-061', '2026-09-02', 'Site Meals', 'Khana', 0, 50000, 22739400, '2026-09'),
  ('CL-20260902-062', '2026-09-02', 'Travel', 'Parking', 0, 3000, 22736400, '2026-09'),
  ('CL-20260902-063', '2026-09-02', 'Admin', 'Shoe polish', 0, 12000, 22724400, '2026-09'),
  ('CL-20260902-064', '2026-09-02', 'Other', 'UNCLEAR small', 0, 5000, 22719400, '2026-09'),
  ('CL-20260903-065', '2026-09-03', 'Site Meals', 'Gosht', 0, 13000, 22706400, '2026-09'),
  ('CL-20260903-066', '2026-09-03', 'Travel', 'Kiraya makhan', 0, 30000, 22676400, '2026-09'),
  ('CL-20260903-067', '2026-09-03', 'Travel', 'Kiraya wapsi', 0, 75000, 22601400, '2026-09'),
  ('CL-20260903-068', '2026-09-03', 'Vehicle CapEx', 'Motorcycle 15 din (running with new bike)', 0, 57000, 22544400, '2026-09'),
  ('CL-20260903-069', '2026-09-03', 'Fuel', 'Petrol', 0, 100000, 22444400, '2026-09'),
  ('CL-20260903-070', '2026-09-03', 'Labour', 'Qasim kapre (clothes)', 0, 100000, 22344400, '2026-09'),
  ('CL-20260903-071', '2026-09-03', 'Travel', 'Rickshaw', 0, 60000, 22284400, '2026-09'),
  ('CL-20260903-072', '2026-09-03', 'Raw Purchase', 'Rock salt first load 15,210 kg (BATCH-001) landed cost PKR 114,270', 0, 11427000, 10857400, '2026-09'),
  ('CL-20260903-073', '2026-09-03', 'Other', 'UNCLEAR 5300', 0, 530000, 10327400, '2026-09'),
  ('CL-20260904-074', '2026-09-04', 'Repairs', 'Bulb', 0, 20000, 10307400, '2026-09'),
  ('CL-20260904-075', '2026-09-04', 'Travel', 'Rickshaw', 0, 30000, 10277400, '2026-09'),
  ('CL-20260904-076', '2026-09-04', 'Other', 'UNCLEAR 1500', 0, 150000, 10127400, '2026-09'),
  ('CL-20260904-077', '2026-09-04', 'Other', 'UNCLEAR: 3 din Julai labour/other 4700', 0, 470000, 9657400, '2026-09'),
  ('CL-20260905-078', '2026-09-05', 'Site Meals', 'Anda', 0, 4000, 9653400, '2026-09'),
  ('CL-20260905-079', '2026-09-05', 'Site Meals', 'Cheeni 0.5 kg', 0, 8000, 9645400, '2026-09'),
  ('CL-20260905-080', '2026-09-05', 'Site Meals', 'Doodh', 0, 6000, 9639400, '2026-09'),
  ('CL-20260905-081', '2026-09-05', 'Site Meals', 'Lays', 0, 3000, 9636400, '2026-09'),
  ('CL-20260905-082', '2026-09-05', 'Fuel', 'Motorcycle oil', 0, 40000, 9596400, '2026-09'),
  ('CL-20260905-083', '2026-09-05', 'Fuel', 'Petrol bike', 0, 105000, 9491400, '2026-09'),
  ('CL-20260905-084', '2026-09-05', 'Site Meals', 'Rafiq chai', 0, 10000, 9481400, '2026-09'),
  ('CL-20260905-085', '2026-09-05', 'Labour', 'Rafiq dawai', 0, 140000, 9341400, '2026-09'),
  ('CL-20260906-086', '2026-09-06', 'Other', 'Income UNCLEAR 50 (roznamcha aamdani)', 5000, 0, 9346400, '2026-09'),
  ('CL-20260906-087', '2026-09-06', 'Other', 'Ali', 0, 500000, 8846400, '2026-09'),
  ('CL-20260906-088', '2026-09-06', 'Travel', 'Kiraya', 0, 35000, 8811400, '2026-09'),
  ('CL-20260906-089', '2026-09-06', 'Freight', 'Kiraya / freight linked to salt move', 0, 40000, 8771400, '2026-09'),
  ('CL-20260906-090', '2026-09-06', 'Travel', 'Kiraya Faisalabad', 0, 224000, 8547400, '2026-09'),
  ('CL-20260906-091', '2026-09-06', 'Site Meals', 'Sham ka khana', 0, 30000, 8517400, '2026-09'),
  ('CL-20260906-092', '2026-09-06', 'Freight', 'Unload labour salt', 0, 240000, 8277400, '2026-09'),
  ('CL-20260907-093', '2026-09-07', 'Other', 'Income UNCLEAR 170 (roznamcha aamdani)', 17000, 0, 8294400, '2026-09'),
  ('CL-20260907-094', '2026-09-07', 'Other', 'Income UNCLEAR 270 (roznamcha aamdani)', 27000, 0, 8321400, '2026-09'),
  ('CL-20260907-095', '2026-09-07', 'Site Meals', 'Anday 6 adad', 0, 15000, 8306400, '2026-09'),
  ('CL-20260907-096', '2026-09-07', 'Repairs', 'Bijli ki tar', 0, 20000, 8286400, '2026-09'),
  ('CL-20260907-097', '2026-09-07', 'Site Meals', 'Dal', 0, 10000, 8276400, '2026-09'),
  ('CL-20260907-098', '2026-09-07', 'Admin', 'Jota cycle', 0, 10000, 8266400, '2026-09'),
  ('CL-20260907-099', '2026-09-07', 'Other', 'UNCLEAR: Kulb — check book subtotal vs lines', 0, 530000, 7736400, '2026-09'),
  ('CL-20260908-100', '2026-09-08', 'Site Meals', 'Sabzi', 0, 32000, 7704400, '2026-09');

-- staging self-check: running balance chain intact
do $$
declare r record; bal bigint := 0; n int := 0;
begin
  for r in select * from app.stg_excel_cash order by occurred_on, txn_id loop
    bal := bal + coalesce(r.money_in_paisa,0) - coalesce(r.money_out_paisa,0);
    if r.running_balance_paisa is not null and bal <> r.running_balance_paisa then
      raise exception 'STAGING MISMATCH at %: computed % vs excel %', r.txn_id, bal, r.running_balance_paisa;
    end if;
    n := n + 1;
  end loop;
  if n <> 100 then raise exception 'STAGING row count % <> 100', n; end if;
  if bal <> 7704400 then raise exception 'STAGING closing cash % <> 7704400', bal; end if;
end $$;

-- ---------- 1b. Products & batches ----------
insert into app.products (code, name, form) values ('SALT_ROCK','Rock Salt (in-house crush)','bulk_processed') on conflict (code) do nothing;
insert into app.batches (batch_code, product_id, location_id, opened_on, note)
  select 'BATCH-001', p.id, l.id, date '2026-09-03',
    'Imported from Excel Salt Inventory sheet: 15,210 kg rock salt @ PKR 7.512820.../kg, landed cost 114,270.00'
  from app.products p, app.locations l
  where p.code = 'SALT_ROCK' and l.code = 'KHANEWAL_PLANT'
  on conflict (batch_code) do nothing;

-- ---------- 1c. Events, ledger entries, movements ----------
insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260823-001', 'capital_injection', '2026-08-23', 'Opening cash / capital', 'owner', 'AAA Owner', 'excel_import', 'CL-20260823-001', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1000'), 50000000, 0), (2, (select id from app.accounts where code='3000'), 0, 50000000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260823-001';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260823-002', 'expense', '2026-08-23', 'Bill house', 'other', NULL, 'excel_import', 'CL-20260823-002', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5100'), 94200, 0), (2, (select id from app.accounts where code='1000'), 0, 94200)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260823-002';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260823-003', 'expense', '2026-08-23', 'Bill mobile', 'other', NULL, 'excel_import', 'CL-20260823-003', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5100'), 101600, 0), (2, (select id from app.accounts where code='1000'), 0, 101600)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260823-003';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260823-004', 'expense', '2026-08-23', 'Bill shop', 'other', NULL, 'excel_import', 'CL-20260823-004', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5800'), 590800, 0), (2, (select id from app.accounts where code='1000'), 0, 590800)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260823-004';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260823-005', 'expense', '2026-08-23', 'UNCLEAR: Helmet Asif / Halmit Asaf', 'other', NULL, 'excel_import', 'CL-20260823-005', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 500000, 0), (2, (select id from app.accounts where code='1000'), 0, 500000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260823-005';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260823-006', 'expense', '2026-08-23', 'UNCLEAR: labelled Rent office — owner owns plant; recode if electric/other', 'other', NULL, 'excel_import', 'CL-20260823-006', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 1710000, 0), (2, (select id from app.accounts where code='1000'), 0, 1710000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260823-006';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260824-007', 'expense', '2026-08-24', 'Bus fare', 'other', NULL, 'excel_import', 'CL-20260824-007', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 120000, 0), (2, (select id from app.accounts where code='1000'), 0, 120000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260824-007';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260824-008', 'expense', '2026-08-24', 'Fruit', 'other', NULL, 'excel_import', 'CL-20260824-008', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 37000, 0), (2, (select id from app.accounts where code='1000'), 0, 37000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260824-008';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260824-009', 'expense', '2026-08-24', 'Indrive', 'other', NULL, 'excel_import', 'CL-20260824-009', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 20000, 0), (2, (select id from app.accounts where code='1000'), 0, 20000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260824-009';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260824-010', 'expense', '2026-08-24', 'Lunch', 'other', NULL, 'excel_import', 'CL-20260824-010', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 20000, 0), (2, (select id from app.accounts where code='1000'), 0, 20000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260824-010';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260824-011', 'expense', '2026-08-24', 'UNCLEAR: Eisha for marriage (personal?)', 'other', NULL, 'excel_import', 'CL-20260824-011', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 1000000, 0), (2, (select id from app.accounts where code='1000'), 0, 1000000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260824-011';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260824-012', 'expense', '2026-08-24', 'UNCLEAR: Skasi to Pasida', 'other', NULL, 'excel_import', 'CL-20260824-012', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 45000, 0), (2, (select id from app.accounts where code='1000'), 0, 45000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260824-012';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260825-013', 'expense', '2026-08-25', 'Dinner', 'other', NULL, 'excel_import', 'CL-20260825-013', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 25000, 0), (2, (select id from app.accounts where code='1000'), 0, 25000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260825-013';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260825-014', 'expense', '2026-08-25', 'Egg and soap', 'other', NULL, 'excel_import', 'CL-20260825-014', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 31000, 0), (2, (select id from app.accounts where code='1000'), 0, 31000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260825-014';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260826-015', 'expense', '2026-08-26', 'Dinner', 'other', NULL, 'excel_import', 'CL-20260826-015', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 34000, 0), (2, (select id from app.accounts where code='1000'), 0, 34000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260826-015';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260826-016', 'expense', '2026-08-26', 'Fruit', 'other', NULL, 'excel_import', 'CL-20260826-016', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 67000, 0), (2, (select id from app.accounts where code='1000'), 0, 67000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260826-016';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260826-017', 'expense', '2026-08-26', 'Yogurt', 'other', NULL, 'excel_import', 'CL-20260826-017', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 11000, 0), (2, (select id from app.accounts where code='1000'), 0, 11000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260826-017';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260827-018', 'expense', '2026-08-27', 'Breakfast', 'other', NULL, 'excel_import', 'CL-20260827-018', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 40000, 0), (2, (select id from app.accounts where code='1000'), 0, 40000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260827-018';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260827-019', 'expense', '2026-08-27', 'Fare Bahawalpur', 'other', NULL, 'excel_import', 'CL-20260827-019', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 65000, 0), (2, (select id from app.accounts where code='1000'), 0, 65000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260827-019';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260827-020', 'expense', '2026-08-27', 'Fare Indrive', 'other', NULL, 'excel_import', 'CL-20260827-020', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 15000, 0), (2, (select id from app.accounts where code='1000'), 0, 15000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260827-020';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260827-021', 'expense', '2026-08-27', 'Fare Khanewal / Multan', 'other', NULL, 'excel_import', 'CL-20260827-021', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 50000, 0), (2, (select id from app.accounts where code='1000'), 0, 50000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260827-021';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260827-022', 'expense', '2026-08-27', 'UNCLEAR: Abda Abid ko diye', 'other', NULL, 'excel_import', 'CL-20260827-022', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 100000, 0), (2, (select id from app.accounts where code='1000'), 0, 100000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260827-022';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260828-023', 'expense', '2026-08-28', 'Fare Bahawalpur / Multan', 'other', NULL, 'excel_import', 'CL-20260828-023', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 65000, 0), (2, (select id from app.accounts where code='1000'), 0, 65000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260828-023';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260828-024', 'expense', '2026-08-28', 'Fruit', 'other', NULL, 'excel_import', 'CL-20260828-024', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 60000, 0), (2, (select id from app.accounts where code='1000'), 0, 60000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260828-024';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260828-025', 'expense', '2026-08-28', 'Indrive', 'other', NULL, 'excel_import', 'CL-20260828-025', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 15000, 0), (2, (select id from app.accounts where code='1000'), 0, 15000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260828-025';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260828-026', 'expense', '2026-08-28', 'Lunch', 'other', NULL, 'excel_import', 'CL-20260828-026', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 25000, 0), (2, (select id from app.accounts where code='1000'), 0, 25000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260828-026';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260828-027', 'expense', '2026-08-28', 'Mobile repair', 'other', NULL, 'excel_import', 'CL-20260828-027', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5700'), 20000, 0), (2, (select id from app.accounts where code='1000'), 0, 20000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260828-027';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260828-028', 'expense', '2026-08-28', 'Nasir ki beti ko diya', 'other', NULL, 'excel_import', 'CL-20260828-028', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5900'), 100000, 0), (2, (select id from app.accounts where code='1000'), 0, 100000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260828-028';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260828-029', 'expense', '2026-08-28', 'Petrol', 'other', NULL, 'excel_import', 'CL-20260828-029', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5300'), 500000, 0), (2, (select id from app.accounts where code='1000'), 0, 500000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260828-029';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260828-030', 'expense', '2026-08-28', 'UNCLEAR: Fare Peshada', 'other', NULL, 'excel_import', 'CL-20260828-030', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 20000, 0), (2, (select id from app.accounts where code='1000'), 0, 20000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260828-030';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260828-031', 'expense', '2026-08-28', 'UNCLEAR: Tofft', 'other', NULL, 'excel_import', 'CL-20260828-031', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 48000, 0), (2, (select id from app.accounts where code='1000'), 0, 48000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260828-031';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-032', 'asset_purchase', '2026-08-29', 'Bakri (goat + kid) purchase — SIDE ASSET not salt COGS', 'other', NULL, 'excel_import', 'CL-20260829-032', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1450'), 5500000, 0), (2, (select id from app.accounts where code='1000'), 0, 5500000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-032';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-033', 'asset_purchase', '2026-08-29', 'Bakri feed 5 kg', 'other', NULL, 'excel_import', 'CL-20260829-033', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1450'), 50000, 0), (2, (select id from app.accounts where code='1000'), 0, 50000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-033';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-034', 'expense', '2026-08-29', 'Lunch', 'other', NULL, 'excel_import', 'CL-20260829-034', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 60000, 0), (2, (select id from app.accounts where code='1000'), 0, 60000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-034';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-035', 'asset_purchase', '2026-08-29', 'Motorcycle advance — NEW BIKE', 'other', NULL, 'excel_import', 'CL-20260829-035', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1400'), 3500000, 0), (2, (select id from app.accounts where code='1000'), 0, 3500000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-035';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-036', 'asset_purchase', '2026-08-29', 'Motorcycle repairing / fit-out with new bike', 'other', NULL, 'excel_import', 'CL-20260829-036', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1400'), 900000, 0), (2, (select id from app.accounts where code='1000'), 0, 900000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-036';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-037', 'expense', '2026-08-29', 'Patti (tea)', 'other', NULL, 'excel_import', 'CL-20260829-037', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 38000, 0), (2, (select id from app.accounts where code='1000'), 0, 38000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-037';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-038', 'expense', '2026-08-29', 'Petrol', 'other', NULL, 'excel_import', 'CL-20260829-038', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5300'), 150000, 0), (2, (select id from app.accounts where code='1000'), 0, 150000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-038';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-039', 'expense', '2026-08-29', 'Qasim advance salary', 'other', NULL, 'excel_import', 'CL-20260829-039', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5000'), 1000000, 0), (2, (select id from app.accounts where code='1000'), 0, 1000000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-039';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-040', 'expense', '2026-08-29', 'Qasim khana', 'other', NULL, 'excel_import', 'CL-20260829-040', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5000'), 50000, 0), (2, (select id from app.accounts where code='1000'), 0, 50000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-040';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-041', 'expense', '2026-08-29', 'Register', 'other', NULL, 'excel_import', 'CL-20260829-041', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5800'), 140000, 0), (2, (select id from app.accounts where code='1000'), 0, 140000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-041';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-042', 'expense', '2026-08-29', 'UNCLEAR: Corur', 'other', NULL, 'excel_import', 'CL-20260829-042', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 45000, 0), (2, (select id from app.accounts where code='1000'), 0, 45000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-042';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260829-043', 'expense', '2026-08-29', 'UNCLEAR: Jabaruko deya', 'other', NULL, 'excel_import', 'CL-20260829-043', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 10000, 0), (2, (select id from app.accounts where code='1000'), 0, 10000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260829-043';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260830-044', 'expense', '2026-08-30', 'Chicken', 'other', NULL, 'excel_import', 'CL-20260830-044', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 50000, 0), (2, (select id from app.accounts where code='1000'), 0, 50000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260830-044';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260830-045', 'expense', '2026-08-30', 'Egg biscuit cake', 'other', NULL, 'excel_import', 'CL-20260830-045', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 44000, 0), (2, (select id from app.accounts where code='1000'), 0, 44000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260830-045';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260830-046', 'asset_purchase', '2026-08-30', 'Motorcycle permit — NEW BIKE (confirm 75,000 vs book)', 'other', NULL, 'excel_import', 'CL-20260830-046', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1400'), 7500000, 0), (2, (select id from app.accounts where code='1000'), 0, 7500000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260830-046';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260830-047', 'expense', '2026-08-30', 'Sabzi and chai', 'other', NULL, 'excel_import', 'CL-20260830-047', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 37000, 0), (2, (select id from app.accounts where code='1000'), 0, 37000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260830-047';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260830-048', 'expense', '2026-08-30', 'UNCLEAR: Drmti CTC', 'other', NULL, 'excel_import', 'CL-20260830-048', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 50000, 0), (2, (select id from app.accounts where code='1000'), 0, 50000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260830-048';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260830-049', 'expense', '2026-08-30', 'UNCLEAR: Tap for baksi water', 'other', NULL, 'excel_import', 'CL-20260830-049', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 110000, 0), (2, (select id from app.accounts where code='1000'), 0, 110000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260830-049';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260831-050', 'expense', '2026-08-31', 'Medicines', 'other', NULL, 'excel_import', 'CL-20260831-050', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5800'), 150000, 0), (2, (select id from app.accounts where code='1000'), 0, 150000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260831-050';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260831-051', 'expense', '2026-08-31', 'Motorcycle repairing', 'other', NULL, 'excel_import', 'CL-20260831-051', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5700'), 200000, 0), (2, (select id from app.accounts where code='1000'), 0, 200000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260831-051';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260831-052', 'expense', '2026-08-31', 'Petrol', 'other', NULL, 'excel_import', 'CL-20260831-052', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5300'), 50000, 0), (2, (select id from app.accounts where code='1000'), 0, 50000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260831-052';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260831-053', 'expense', '2026-08-31', 'Sabzi sarf etc', 'other', NULL, 'excel_import', 'CL-20260831-053', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 37000, 0), (2, (select id from app.accounts where code='1000'), 0, 37000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260831-053';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260831-054', 'expense', '2026-08-31', 'Stamp paper / photocopy', 'other', NULL, 'excel_import', 'CL-20260831-054', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5800'), 30000, 0), (2, (select id from app.accounts where code='1000'), 0, 30000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260831-054';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260831-055', 'expense', '2026-08-31', 'UNCLEAR: Ghai-bursh kill', 'other', NULL, 'excel_import', 'CL-20260831-055', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 80000, 0), (2, (select id from app.accounts where code='1000'), 0, 80000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260831-055';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260901-056', 'expense', '2026-09-01', 'Chai', 'other', NULL, 'excel_import', 'CL-20260901-056', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 30000, 0), (2, (select id from app.accounts where code='1000'), 0, 30000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260901-056';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260901-057', 'asset_purchase', '2026-09-01', 'Helmet', 'other', NULL, 'excel_import', 'CL-20260901-057', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1400'), 550000, 0), (2, (select id from app.accounts where code='1000'), 0, 550000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260901-057';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260901-058', 'expense', '2026-09-01', 'Petrol', 'other', NULL, 'excel_import', 'CL-20260901-058', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5300'), 100000, 0), (2, (select id from app.accounts where code='1000'), 0, 100000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260901-058';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260902-059', 'expense', '2026-09-02', 'Bardaana 700 bags — first packing material', 'other', NULL, 'excel_import', 'CL-20260902-059', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5400'), 1150000, 0), (2, (select id from app.accounts where code='1000'), 0, 1150000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260902-059';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260902-060', 'expense', '2026-09-02', 'Hamali (loading labour)', 'other', NULL, 'excel_import', 'CL-20260902-060', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5000'), 70000, 0), (2, (select id from app.accounts where code='1000'), 0, 70000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260902-060';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260902-061', 'expense', '2026-09-02', 'Khana', 'other', NULL, 'excel_import', 'CL-20260902-061', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 50000, 0), (2, (select id from app.accounts where code='1000'), 0, 50000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260902-061';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260902-062', 'expense', '2026-09-02', 'Parking', 'other', NULL, 'excel_import', 'CL-20260902-062', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 3000, 0), (2, (select id from app.accounts where code='1000'), 0, 3000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260902-062';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260902-063', 'expense', '2026-09-02', 'Shoe polish', 'other', NULL, 'excel_import', 'CL-20260902-063', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5800'), 12000, 0), (2, (select id from app.accounts where code='1000'), 0, 12000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260902-063';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260902-064', 'expense', '2026-09-02', 'UNCLEAR small', 'other', NULL, 'excel_import', 'CL-20260902-064', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 5000, 0), (2, (select id from app.accounts where code='1000'), 0, 5000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260902-064';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260903-065', 'expense', '2026-09-03', 'Gosht', 'other', NULL, 'excel_import', 'CL-20260903-065', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 13000, 0), (2, (select id from app.accounts where code='1000'), 0, 13000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260903-065';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260903-066', 'expense', '2026-09-03', 'Kiraya makhan', 'other', NULL, 'excel_import', 'CL-20260903-066', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 30000, 0), (2, (select id from app.accounts where code='1000'), 0, 30000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260903-066';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260903-067', 'expense', '2026-09-03', 'Kiraya wapsi', 'other', NULL, 'excel_import', 'CL-20260903-067', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 75000, 0), (2, (select id from app.accounts where code='1000'), 0, 75000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260903-067';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260903-068', 'asset_purchase', '2026-09-03', 'Motorcycle 15 din (running with new bike)', 'other', NULL, 'excel_import', 'CL-20260903-068', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1400'), 57000, 0), (2, (select id from app.accounts where code='1000'), 0, 57000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260903-068';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260903-069', 'expense', '2026-09-03', 'Petrol', 'other', NULL, 'excel_import', 'CL-20260903-069', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5300'), 100000, 0), (2, (select id from app.accounts where code='1000'), 0, 100000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260903-069';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260903-070', 'expense', '2026-09-03', 'Qasim kapre (clothes)', 'other', NULL, 'excel_import', 'CL-20260903-070', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5000'), 100000, 0), (2, (select id from app.accounts where code='1000'), 0, 100000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260903-070';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260903-071', 'expense', '2026-09-03', 'Rickshaw', 'other', NULL, 'excel_import', 'CL-20260903-071', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 60000, 0), (2, (select id from app.accounts where code='1000'), 0, 60000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260903-071';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260903-072', 'purchase', '2026-09-03', 'Rock salt first load 15,210 kg (BATCH-001) landed cost PKR 114,270', 'other', NULL, 'excel_import', 'CL-20260903-072', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1200'), 11396985, 0), (2, (select id from app.accounts where code='1240'), 30015, 0), (3, (select id from app.accounts where code='1000'), 0, 11427000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260903-072';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260903-073', 'expense', '2026-09-03', 'UNCLEAR 5300', 'other', NULL, 'excel_import', 'CL-20260903-073', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 530000, 0), (2, (select id from app.accounts where code='1000'), 0, 530000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260903-073';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260904-074', 'expense', '2026-09-04', 'Bulb', 'other', NULL, 'excel_import', 'CL-20260904-074', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5700'), 20000, 0), (2, (select id from app.accounts where code='1000'), 0, 20000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260904-074';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260904-075', 'expense', '2026-09-04', 'Rickshaw', 'other', NULL, 'excel_import', 'CL-20260904-075', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 30000, 0), (2, (select id from app.accounts where code='1000'), 0, 30000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260904-075';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260904-076', 'expense', '2026-09-04', 'UNCLEAR 1500', 'other', NULL, 'excel_import', 'CL-20260904-076', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 150000, 0), (2, (select id from app.accounts where code='1000'), 0, 150000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260904-076';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260904-077', 'expense', '2026-09-04', 'UNCLEAR: 3 din Julai labour/other 4700', 'other', NULL, 'excel_import', 'CL-20260904-077', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 470000, 0), (2, (select id from app.accounts where code='1000'), 0, 470000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260904-077';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260905-078', 'expense', '2026-09-05', 'Anda', 'other', NULL, 'excel_import', 'CL-20260905-078', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 4000, 0), (2, (select id from app.accounts where code='1000'), 0, 4000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260905-078';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260905-079', 'expense', '2026-09-05', 'Cheeni 0.5 kg', 'other', NULL, 'excel_import', 'CL-20260905-079', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 8000, 0), (2, (select id from app.accounts where code='1000'), 0, 8000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260905-079';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260905-080', 'expense', '2026-09-05', 'Doodh', 'other', NULL, 'excel_import', 'CL-20260905-080', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 6000, 0), (2, (select id from app.accounts where code='1000'), 0, 6000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260905-080';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260905-081', 'expense', '2026-09-05', 'Lays', 'other', NULL, 'excel_import', 'CL-20260905-081', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 3000, 0), (2, (select id from app.accounts where code='1000'), 0, 3000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260905-081';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260905-082', 'expense', '2026-09-05', 'Motorcycle oil', 'other', NULL, 'excel_import', 'CL-20260905-082', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5300'), 40000, 0), (2, (select id from app.accounts where code='1000'), 0, 40000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260905-082';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260905-083', 'expense', '2026-09-05', 'Petrol bike', 'other', NULL, 'excel_import', 'CL-20260905-083', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5300'), 105000, 0), (2, (select id from app.accounts where code='1000'), 0, 105000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260905-083';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260905-084', 'expense', '2026-09-05', 'Rafiq chai', 'other', NULL, 'excel_import', 'CL-20260905-084', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 10000, 0), (2, (select id from app.accounts where code='1000'), 0, 10000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260905-084';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260905-085', 'expense', '2026-09-05', 'Rafiq dawai', 'other', NULL, 'excel_import', 'CL-20260905-085', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5000'), 140000, 0), (2, (select id from app.accounts where code='1000'), 0, 140000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260905-085';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260906-086', 'other', '2026-09-06', 'Income UNCLEAR 50 (roznamcha aamdani)', 'other', NULL, 'excel_import', 'CL-20260906-086', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1000'), 5000, 0), (2, (select id from app.accounts where code='1900'), 0, 5000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260906-086';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260906-087', 'expense', '2026-09-06', 'Ali', 'other', NULL, 'excel_import', 'CL-20260906-087', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5900'), 500000, 0), (2, (select id from app.accounts where code='1000'), 0, 500000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260906-087';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260906-088', 'expense', '2026-09-06', 'Kiraya', 'other', NULL, 'excel_import', 'CL-20260906-088', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 35000, 0), (2, (select id from app.accounts where code='1000'), 0, 35000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260906-088';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260906-089', 'expense', '2026-09-06', 'Kiraya / freight linked to salt move', 'other', NULL, 'excel_import', 'CL-20260906-089', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5200'), 40000, 0), (2, (select id from app.accounts where code='1000'), 0, 40000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260906-089';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260906-090', 'expense', '2026-09-06', 'Kiraya Faisalabad', 'other', NULL, 'excel_import', 'CL-20260906-090', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5600'), 224000, 0), (2, (select id from app.accounts where code='1000'), 0, 224000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260906-090';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260906-091', 'expense', '2026-09-06', 'Sham ka khana', 'other', NULL, 'excel_import', 'CL-20260906-091', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 30000, 0), (2, (select id from app.accounts where code='1000'), 0, 30000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260906-091';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260906-092', 'expense', '2026-09-06', 'Unload labour salt', 'other', NULL, 'excel_import', 'CL-20260906-092', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5200'), 240000, 0), (2, (select id from app.accounts where code='1000'), 0, 240000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260906-092';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260907-093', 'other', '2026-09-07', 'Income UNCLEAR 170 (roznamcha aamdani)', 'other', NULL, 'excel_import', 'CL-20260907-093', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1000'), 17000, 0), (2, (select id from app.accounts where code='1900'), 0, 17000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260907-093';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260907-094', 'other', '2026-09-07', 'Income UNCLEAR 270 (roznamcha aamdani)', 'other', NULL, 'excel_import', 'CL-20260907-094', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1000'), 27000, 0), (2, (select id from app.accounts where code='1900'), 0, 27000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260907-094';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260907-095', 'expense', '2026-09-07', 'Anday 6 adad', 'other', NULL, 'excel_import', 'CL-20260907-095', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 15000, 0), (2, (select id from app.accounts where code='1000'), 0, 15000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260907-095';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260907-096', 'expense', '2026-09-07', 'Bijli ki tar', 'other', NULL, 'excel_import', 'CL-20260907-096', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5700'), 20000, 0), (2, (select id from app.accounts where code='1000'), 0, 20000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260907-096';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260907-097', 'expense', '2026-09-07', 'Dal', 'other', NULL, 'excel_import', 'CL-20260907-097', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 10000, 0), (2, (select id from app.accounts where code='1000'), 0, 10000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260907-097';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260907-098', 'expense', '2026-09-07', 'Jota cycle', 'other', NULL, 'excel_import', 'CL-20260907-098', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5800'), 10000, 0), (2, (select id from app.accounts where code='1000'), 0, 10000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260907-098';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260907-099', 'expense', '2026-09-07', 'UNCLEAR: Kulb — check book subtotal vs lines', 'other', NULL, 'excel_import', 'CL-20260907-099', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='1900'), 530000, 0), (2, (select id from app.accounts where code='1000'), 0, 530000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260907-099';

insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values
  ('CL-20260908-100', 'expense', '2026-09-08', 'Sabzi', 'other', NULL, 'excel_import', 'CL-20260908-100', '33333333-3333-3333-3333-333333333333');
insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)
select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values (1, (select id from app.accounts where code='5500'), 32000, 0), (2, (select id from app.accounts where code='1000'), 0, 32000)) as x(seq, acc, dr, cr)
where e.event_ref = 'CL-20260908-100';

-- BATCH-001 opening inventory (from Salt Inventory sheet)
insert into app.events (event_ref, event_type, occurred_on, description, source, source_ref, created_by) values
  ('IMP-BATCH001', 'opening_inventory', date '2026-09-03',
   'BATCH-001 opening inventory: 15,210 kg rock salt at Khanewal Plant, total landed cost PKR 114,270.00 (7.512820.../kg)',
   'excel_import', 'Salt Inventory!A3', '33333333-3333-3333-3333-333333333333');
-- NOTE (post-remediation): value is ALREADY on the books via purchase event
-- CL-20260903-072 (Dr Inventory 1200 / Cr Cash 114,270.00). IMP-BATCH001 records
-- the physical movement only - no second value posting (no double-count).
insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)
select e.id, 1, p.id, b.id, l.id, 'in', 15210000, 11427000
from app.events e, app.products p, app.batches b, app.locations l
where e.event_ref = 'IMP-BATCH001' and p.code = 'SALT_ROCK' and b.batch_code = 'BATCH-001' and l.code = 'KHANEWAL_PLANT';

-- ---------- 1d. Review queue: imported UNCLEAR lines ----------
insert into app.review_queue (source, severity, title, detail, source_ref) values
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260823-005', jsonb_build_object('excel_txn', 'CL-20260823-005', 'date', '2026-08-23', 'category', 'Other', 'description', 'UNCLEAR: Helmet Asif / Halmit Asaf', 'amount_paisa', 500000, 'amount_display', 'PKR 5,000.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260823-005'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260823-006', jsonb_build_object('excel_txn', 'CL-20260823-006', 'date', '2026-08-23', 'category', 'Utilities', 'description', 'UNCLEAR: labelled Rent office — owner owns plant; recode if electric/other', 'amount_paisa', 1710000, 'amount_display', 'PKR 17,100.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260823-006'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260824-011', jsonb_build_object('excel_txn', 'CL-20260824-011', 'date', '2026-08-24', 'category', 'Other', 'description', 'UNCLEAR: Eisha for marriage (personal?)', 'amount_paisa', 1000000, 'amount_display', 'PKR 10,000.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260824-011'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260824-012', jsonb_build_object('excel_txn', 'CL-20260824-012', 'date', '2026-08-24', 'category', 'Travel', 'description', 'UNCLEAR: Skasi to Pasida', 'amount_paisa', 45000, 'amount_display', 'PKR 450.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260824-012'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260827-022', jsonb_build_object('excel_txn', 'CL-20260827-022', 'date', '2026-08-27', 'category', 'Other', 'description', 'UNCLEAR: Abda Abid ko diye', 'amount_paisa', 100000, 'amount_display', 'PKR 1,000.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260827-022'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260828-030', jsonb_build_object('excel_txn', 'CL-20260828-030', 'date', '2026-08-28', 'category', 'Travel', 'description', 'UNCLEAR: Fare Peshada', 'amount_paisa', 20000, 'amount_display', 'PKR 200.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260828-030'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260828-031', jsonb_build_object('excel_txn', 'CL-20260828-031', 'date', '2026-08-28', 'category', 'Site Meals', 'description', 'UNCLEAR: Tofft', 'amount_paisa', 48000, 'amount_display', 'PKR 480.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260828-031'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260829-042', jsonb_build_object('excel_txn', 'CL-20260829-042', 'date', '2026-08-29', 'category', 'Other', 'description', 'UNCLEAR: Corur', 'amount_paisa', 45000, 'amount_display', 'PKR 450.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260829-042'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260829-043', jsonb_build_object('excel_txn', 'CL-20260829-043', 'date', '2026-08-29', 'category', 'Other', 'description', 'UNCLEAR: Jabaruko deya', 'amount_paisa', 10000, 'amount_display', 'PKR 100.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260829-043'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260830-048', jsonb_build_object('excel_txn', 'CL-20260830-048', 'date', '2026-08-30', 'category', 'Other', 'description', 'UNCLEAR: Drmti CTC', 'amount_paisa', 50000, 'amount_display', 'PKR 500.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260830-048'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260830-049', jsonb_build_object('excel_txn', 'CL-20260830-049', 'date', '2026-08-30', 'category', 'Other', 'description', 'UNCLEAR: Tap for baksi water', 'amount_paisa', 110000, 'amount_display', 'PKR 1,100.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260830-049'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260831-055', jsonb_build_object('excel_txn', 'CL-20260831-055', 'date', '2026-08-31', 'category', 'Other', 'description', 'UNCLEAR: Ghai-bursh kill', 'amount_paisa', 80000, 'amount_display', 'PKR 800.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260831-055'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260902-064', jsonb_build_object('excel_txn', 'CL-20260902-064', 'date', '2026-09-02', 'category', 'Other', 'description', 'UNCLEAR small', 'amount_paisa', 5000, 'amount_display', 'PKR 50.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260902-064'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260903-073', jsonb_build_object('excel_txn', 'CL-20260903-073', 'date', '2026-09-03', 'category', 'Other', 'description', 'UNCLEAR 5300', 'amount_paisa', 530000, 'amount_display', 'PKR 5,300.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260903-073'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260904-076', jsonb_build_object('excel_txn', 'CL-20260904-076', 'date', '2026-09-04', 'category', 'Other', 'description', 'UNCLEAR 1500', 'amount_paisa', 150000, 'amount_display', 'PKR 1,500.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260904-076'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260904-077', jsonb_build_object('excel_txn', 'CL-20260904-077', 'date', '2026-09-04', 'category', 'Other', 'description', 'UNCLEAR: 3 din Julai labour/other 4700', 'amount_paisa', 470000, 'amount_display', 'PKR 4,700.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260904-077'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260906-086', jsonb_build_object('excel_txn', 'CL-20260906-086', 'date', '2026-09-06', 'category', 'Other', 'description', 'Income UNCLEAR 50 (roznamcha aamdani)', 'amount_paisa', 5000, 'amount_display', 'PKR 50.00', 'provisional_account', '1900 Suspense', 'side', 'IN'), 'CL-20260906-086'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260907-093', jsonb_build_object('excel_txn', 'CL-20260907-093', 'date', '2026-09-07', 'category', 'Other', 'description', 'Income UNCLEAR 170 (roznamcha aamdani)', 'amount_paisa', 17000, 'amount_display', 'PKR 170.00', 'provisional_account', '1900 Suspense', 'side', 'IN'), 'CL-20260907-093'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260907-094', jsonb_build_object('excel_txn', 'CL-20260907-094', 'date', '2026-09-07', 'category', 'Other', 'description', 'Income UNCLEAR 270 (roznamcha aamdani)', 'amount_paisa', 27000, 'amount_display', 'PKR 270.00', 'provisional_account', '1900 Suspense', 'side', 'IN'), 'CL-20260907-094'),
  ('excel_import', 'needs_review', 'UNCLEAR line CL-20260907-099', jsonb_build_object('excel_txn', 'CL-20260907-099', 'date', '2026-09-07', 'category', 'Other', 'description', 'UNCLEAR: Kulb — check book subtotal vs lines', 'amount_paisa', 530000, 'amount_display', 'PKR 5,300.00', 'provisional_account', '1900 Suspense', 'side', 'OUT'), 'CL-20260907-099');

-- ============================================================
-- 1e. VERIFICATION — fails loudly on any drift
-- ============================================================
do $$
declare
  cash bal bigint; dr bigint; cr bigint; rq int; ev int; mvq bigint; mvv bigint;
  inv_qty bigint; inv_val bigint; imp_n int;
begin
  select coalesce(sum(debit_paisa-credit_paisa),0) into cash bal
    from app.ledger_entries le join app.accounts a on a.id=le.account_id where a.code='1000';
  if cash_bal <> 7704400 then
    raise exception 'VERIFY FAIL: cash % paisa <> 7704400 (PKR 77,044.00)', cash_bal;
  end if;

  select coalesce(sum(debit_paisa),0), coalesce(sum(credit_paisa),0) into dr, cr from app.ledger_entries;
  if dr <> cr then
    raise exception 'VERIFY FAIL: books unbalanced Dr % <> Cr % paisa', dr, cr;
  end if;

  select count(*) into ev from app.events where source='excel_import';
  if ev <> 101 then raise exception 'VERIFY FAIL: imported events % <> 101', ev; end if;

  select count(*) into rq from app.review_queue where status='open' and source='excel_import';
  if rq <> 20 then raise exception 'VERIFY FAIL: review queue % <> 20 unclear rows', rq; end if;

  select coalesce(sum(case when direction='in' then qty_grams else -qty_grams end),0) into mvq
    from app.movements;
  if mvq <> 15210000 then raise exception 'VERIFY FAIL: on-hand qty % g <> 15,210,000 g', mvq; end if;

  select coalesce(sum(value_paisa),0) into mvv from app.movements;
  if mvv <> 11427000 then raise exception 'VERIFY FAIL: inventory value % <> 11427000 paisa', mvv; end if;

  select coalesce(sum(m.debit_paisa-credit_paisa),0) into inv_val
    from app.ledger_entries m join app.accounts a on a.id=m.account_id
    where a.code in ('1200','1210','1220','1230','1300','1310');
  if inv_val <> 11427000 then raise exception 'VERIFY FAIL: inventory ledger % <> 11427000', inv_val; end if;

  select coalesce(sum(le.debit_paisa-le.credit_paisa),0) into susp
    from app.ledger_entries le join app.accounts a on a.id=le.account_id where a.code='1900';
  if susp < 0 then raise exception 'VERIFY FAIL: Suspense negative (%)', susp; end if;

  select count(*) into imp_n from app.stg_excel_cash;
  if imp_n <> 100 then raise exception 'VERIFY FAIL: staging rows % <> 100', imp_n; end if;

  raise notice 'PHASE 1 VERIFIED: cash=PKR 77,044.00 | books balanced | 101 events | 20 review items | inventory 15,210 kg = PKR 114,270.00';
end $$;
