#!/usr/bin/env python3
"""
AAA Trade House Ledger — Phase 1 import generator.

Reads AAA_Trade_House_Master_Ledger.xlsx (source of truth) and emits
supabase/migrations/20260918010000_phase1_import.sql containing, in order:

  1. Staging tables  (raw preservation of the Excel rows — audit material)
  2. Real data       (products/batches/events/ledger_entries/movements/review_queue)
  3. Verification    (assertions that fail loudly if anything drifted)

Rules honoured:
  - No silent failures: every reconciliation assertion raises.
  - Nothing is auto-classified: UNCLEAR lines land in review_queue with a
    provisional posting to account 1900 (Suspense), never to salt cost.
  - Cash reconciliation must equal the Excel closing balance to the paisa.

Deterministic: no randomness, no timestamps baked into output.
"""
import openpyxl
from pathlib import Path

EXCEL = Path(__file__).resolve().parents[2] / "AAA_Trade_House_Master_Ledger.xlsx"
OUT = Path(__file__).resolve().parents[1] / "supabase" / "migrations" / "20260918010000_phase1_import.sql"

# Excel category -> (account_code, expected side)
CAT_OUT = {
    "Capital":        None,   # handled specially (IN side)
    "Raw Purchase":   None,   # handled specially (inventory posting)
    "Vehicle CapEx":  "1400", # asset
    "Side Livestock": "1450", # asset
    "Freight":        "5200",
    "Fuel":           "5300",
    "Packaging":      "5400",
    "Labour":         "5000",
    "Utilities":      "5100",
    "Site Meals":     "5500",
    "Travel":         "5600",
    "Repairs":        "5700",
    "Admin":          "5800",
    "Other":          "5900",
}
ASSET_CATS = {"Vehicle CapEx", "Side Livestock"}

def paisa(x):
    assert float(x) == int(x * 100) / 100 or abs(float(x) * 100 - round(float(x) * 100)) < 1e-6, f"non-decimal money {x}"
    return int(round(float(x) * 100))

def q(x):
    return "NULL" if x is None else f"'{str(x).replace(chr(39), chr(39)*2)}'"

def m(x):
    return "NULL" if x is None else str(paisa(x))

def main():
    wb = openpyxl.load_workbook(EXCEL, data_only=True)

    # ---------- read cash ledger ----------
    ws = wb["Cash Ledger"]
    cash = []
    for r in ws.iter_rows(min_row=3, values_only=True):
        if r[1] is None:
            continue
        d = r[0]
        cash.append({
            "date": d.strftime("%Y-%m-%d"),
            "txn": str(r[1]).strip(),
            "cat": (str(r[2]).strip() if r[2] else ""),
            "desc": str(r[3]).strip() if r[3] else "",
            "in": float(r[4] or 0),
            "out": float(r[5] or 0),
            "bal": r[6],
        })
    assert len(cash) == 100, f"expected 100 cash rows, got {len(cash)}"

    total_in = sum(c["in"] for c in cash)
    total_out = sum(c["out"] for c in cash)
    net = total_in - total_out
    closing_excel = paisa(cash[-1]["bal"])
    assert paisa(net) == closing_excel, "excel internal mismatch: net != closing balance"

    capital_in = sum(c["in"] for c in cash if c["cat"] == "Capital")
    other_in = sum(c["in"] for c in cash if c["cat"] != "Capital")
    assert paisa(capital_in) == 50_000_000, f"capital expected 500,000.00, got {capital_in}"
    raw_total = sum(c["out"] for c in cash if c["cat"] == "Raw Purchase")

    sql = []
    sql.append("-- ============================================================")
    sql.append("-- AAA Trade House Ledger — Phase 1: Excel import (generated)")
    sql.append(f"-- Source: {EXCEL.name} | cash rows: {len(cash)} | generated deterministically")
    sql.append("-- Money unit: paisa (PKR * 100)")
    sql.append("-- ============================================================")
    sql.append("")
    sql.append("-- ---------- 1. Staging (raw preservation of Excel rows) ----------")
    sql.append("""create table if not exists app.stg_excel_cash (
  txn_id text primary key,
  occurred_on date not null,
  category text,
  description text,
  money_in_paisa bigint not null default 0,
  money_out_paisa bigint not null default 0,
  running_balance_paisa bigint,
  month_key text
);""")
    sql.append("")

    # running balance check inside staging too
    sql.append("insert into app.stg_excel_cash (txn_id, occurred_on, category, description, money_in_paisa, money_out_paisa, running_balance_paisa, month_key) values")
    lines = []
    for c in cash:
        lines.append(f"  ({q(c['txn'])}, {q(c['date'])}, {q(c['cat'])}, {q(c['desc'])}, {m(c['in'])}, {m(c['out'])}, {m(c['bal'])}, {q(c['date'][:7])})")
    sql.append(",\n".join(lines) + ";")
    sql.append("")

    sql.append("""-- staging self-check: running balance chain intact
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
end $$;""")
    sql.append("")

    # ---------- 1b. reference rows ----------
    sql.append("-- ---------- 1b. Products & batches ----------")
    sql.append("insert into app.products (code, name, form) values ('SALT_ROCK','Rock Salt (in-house crush)','bulk_processed') on conflict (code) do nothing;")
    sql.append("insert into app.batches (batch_code, product_id, location_id, opened_on, note)")
    sql.append("  select 'BATCH-001', p.id, l.id, date '2026-09-03',")
    sql.append("    'Imported from Excel Salt Inventory sheet: 15,210 kg rock salt @ PKR 7.512820.../kg, landed cost 114,270.00'")
    sql.append("  from app.products p, app.locations l")
    sql.append("  where p.code = 'SALT_ROCK' and l.code = 'KHANEWAL_PLANT'")
    sql.append("  on conflict (batch_code) do nothing;")
    sql.append("")

    # ---------- 1c. events + ledger + movements + review queue ----------
    sql.append("-- ---------- 1c. Events, ledger entries, movements ----------")
    ev_n = 0
    rq_n = 0
    event_sql = []
    review_sql = []
    review_rows = []

    for c in cash:
        ev_n += 1
        amt = paisa(c["in"] if c["in"] else c["out"])
        side = "in" if c["in"] else "out"
        is_unclear = "UNCLEAR" in c["desc"].upper() or "UNCLEAR" in c["cat"].upper()
        d = c["date"]

        if c["cat"] == "Capital":
            et = "capital_injection"
            desc = c["desc"] or "Capital introduced"
            lines_sql = f"(1, (select id from app.accounts where code='1000'), {amt}, 0), (2, (select id from app.accounts where code='3000'), 0, {amt})"
        elif side == "in":
            et = "other"
            if is_unclear:
                desc = c["desc"]
                lines_sql = f"(1, (select id from app.accounts where code='1000'), {amt}, 0), (2, (select id from app.accounts where code='1900'), 0, {amt})"
            else:
                desc = c["desc"] or "Other income"
                lines_sql = f"(1, (select id from app.accounts where code='1000'), {amt}, 0), (2, (select id from app.accounts where code='4900'), 0, {amt})"
        elif c["cat"] == "Raw Purchase":
            et = "purchase"
            desc = c["desc"] or "Raw salt purchase"
            # Clean 2-line posting: the Excel figure 114,270 IS the total landed cost.
            # (An earlier 3-line split double-counted inventory value; caught by verification.)
            lines_sql = (
                f"(1, (select id from app.accounts where code='1200'), {amt}, 0), "
                f"(2, (select id from app.accounts where code='1000'), 0, {amt})"
            )
        elif is_unclear:
            et = "expense"
            desc = c["desc"]
            lines_sql = f"(1, (select id from app.accounts where code='1900'), {amt}, 0), (2, (select id from app.accounts where code='1000'), 0, {amt})"
        elif c["cat"] in ASSET_CATS:
            et = "asset_purchase"
            desc = c["desc"] or f"{c['cat']} (asset)"
            lines_sql = f"(1, (select id from app.accounts where code='{CAT_OUT[c['cat']]}'), {amt}, 0), (2, (select id from app.accounts where code='1000'), 0, {amt})"
        else:
            et = "expense"
            desc = c["desc"] or c["cat"]
            lines_sql = f"(1, (select id from app.accounts where code='{CAT_OUT[c['cat']]}'), {amt}, 0), (2, (select id from app.accounts where code='1000'), 0, {amt})"

        party = "owner" if c["cat"] == "Capital" else "other"
        event_sql.append(
            "insert into app.events (event_ref, event_type, occurred_on, description, party_type, party_name, source, source_ref, created_by) values\n"
            f"  ({q(c['txn'])}, {q(et)}, {q(d)}, {q(desc)}, {q(party)}, {q('AAA Owner' if party=='owner' else None)}, 'excel_import', {q(c['txn'])}, '33333333-3333-3333-3333-333333333333');\n"
            "insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)\n"
            f"select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values {lines_sql}) as x(seq, acc, dr, cr)\n"
            "where e.event_ref = " + q(c['txn']) + ";\n"
        )

        if is_unclear:
            rq_n += 1
            review_rows.append(
                f"  ('excel_import', 'needs_review', {q('UNCLEAR line ' + c['txn'])}, "
                f"jsonb_build_object('excel_txn', {q(c['txn'])}, 'date', {q(d)}, 'category', {q(c['cat'])}, "
                f"'description', {q(c['desc'])}, 'amount_paisa', {amt}, 'amount_display', {q(f'PKR {amt/100:,.2f}')}, "
                f"'provisional_account', '1900 Suspense', 'side', {q(side.upper())}), {q(c['txn'])})"
            )

    sql.extend(event_sql)

    # BATCH-001 inventory event (2026-09-03)
    sql.append("-- BATCH-001 opening inventory (from Salt Inventory sheet)")
    sql.append("insert into app.events (event_ref, event_type, occurred_on, description, source, source_ref, created_by) values")
    sql.append("  ('IMP-BATCH001', 'opening_inventory', date '2026-09-03',")
    sql.append("   'BATCH-001 opening inventory: 15,210 kg rock salt at Khanewal Plant, total landed cost PKR 114,270.00 (7.512820.../kg)',")
    sql.append("   'excel_import', 'Salt Inventory!A3', '33333333-3333-3333-3333-333333333333');")
    sql.append("insert into app.ledger_entries (event_id, entry_seq, account_id, debit_paisa, credit_paisa)")
    sql.append("select e.id, x.seq, x.acc, x.dr, x.cr from app.events e, (values")
    sql.append("  (1, (select id from app.accounts where code='1200'), 11396985, 0),")
    sql.append("  (2, (select id from app.accounts where code='1240'), 30015, 0),")
    sql.append("  (3, (select id from app.accounts where code='1900'), 0, 11427000)")
    sql.append(") as x(seq, acc, dr, cr) where e.event_ref = 'IMP-BATCH001';")
    sql.append("insert into app.movements (event_id, movement_seq, product_id, batch_id, location_id, direction, qty_grams, value_paisa)")
    sql.append("select e.id, 1, p.id, b.id, l.id, 'in', 15210000, 11427000")
    sql.append("from app.events e, app.products p, app.batches b, app.locations l")
    sql.append("where e.event_ref = 'IMP-BATCH001' and p.code = 'SALT_ROCK' and b.batch_code = 'BATCH-001' and l.code = 'KHANEWAL_PLANT';")
    sql.append("")

    if review_rows:
        sql.append("-- ---------- 1d. Review queue: imported UNCLEAR lines ----------")
        sql.append("insert into app.review_queue (source, severity, title, detail, source_ref) values")
        sql.append(",\n".join(review_rows) + ";")
        sql.append("")

    # ---------- 1e. verification ----------
    sql.append("-- ============================================================")
    sql.append("-- 1e. VERIFICATION — fails loudly on any drift")
    sql.append("-- ============================================================")
    sql.append("""do $$
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
    from app.ledger_entries m join app.accounts a on a.id=m.account_id where a.code in ('1200','1240');
  if inv_val <> 11427000 then raise exception 'VERIFY FAIL: inventory ledger value % <> 11427000', inv_val; end if;

  select count(*) into imp_n from app.stg_excel_cash;
  if imp_n <> 100 then raise exception 'VERIFY FAIL: staging rows % <> 100', imp_n; end if;

  raise notice 'PHASE 1 VERIFIED: cash=PKR 77,044.00 | books balanced | 101 events | 20 review items | inventory 15,210 kg = PKR 114,270.00';
end $$;""")
    sql.append("")

    OUT.write_text("\n".join(sql), encoding="utf-8")
    print(f"OK wrote {OUT}")
    print(f"  events: {ev_n} (100 cash + 1 BATCH-001)")
    print(f"  review queue rows: {rq_n}")
    print(f"  capital in: PKR {capital_in:,.2f} | other income in: PKR {other_in:,.2f}")
    print(f"  total in: PKR {total_in:,.2f} | total out: PKR {total_out:,.2f} | net: PKR {net:,.2f}")
    print(f"  raw purchase total: PKR {raw_total:,.2f}")

if __name__ == "__main__":
    main()
