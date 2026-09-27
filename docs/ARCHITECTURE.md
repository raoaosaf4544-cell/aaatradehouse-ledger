# AAA Trade House Ledger — Architecture & Data Model (v1, agreed)

Status: **Design agreed with owner 2026-09-17. Implementation phases below are not yet built.**
Author: Buffy (Codebuff) with raoaosaf

---

## 0. Source of truth for this document

Decisions below come from (a) code review of this repo, (b) analysis of
`AAA_Trade_House_Master_Ledger.xlsx` (100 cash txns 2026-08-23→09-08, closing 77,044;
BATCH-001 15,210 kg @ 7.5128/kg = 114,270; 18 UNCLEAR lines; AR/AP/orders empty on purpose),
and (c) the owner's interview answers on 2026-09-17:

| Topic | Decision |
|---|---|
| Purchases | Raw **and** already-crushed salt both bought |
| Production | One crush pass → screen into grades (fine/coarse/mesh) |
| Wastage | Weighed every run; fairly steady % — stored per run |
| Packaging | 1 kg retail pouches + 25/50 kg bulk bags + branded pouches planned ("all of the above") |
| Revenue recognition | At **dispatch** (stock leaves on dispatch) |
| Customer payments | **Advances and credit both** exist |
| Locations | Plant-only today; schema supports more |
| Processing costs | My recommended treatment (see §7) |
| Bike / goats / personal | Bike = business asset; goats = side asset outside salt P&L; personal = drawings |
| Users | Two named users, same rights, every entry attributed |
| Deployment | Hosted web app + cloud DB (Supabase Postgres) |
| Excel migration | Import all 100 rows + BATCH-001; UNCLEAR → review queue |
| Reporting | Internal only for now; tax-ready bookkeeping shape |

---

## 1. Product & packaging model

`products` = master list, fully user-extensible:

```
id, name, form,                 -- RAW_ROCK | CRUSHED | SCREENED_GRADE | BULK | PACKAGED | MATERIAL | WIP
    grain,                      -- nullable: FINE | COARSE | MESH_<n> | null
    sell_unit,                  -- KG | BAG | CARTON
    default_pkg_weight_kg,      -- null for bulk/raw/materials
    active, tracked             -- tracked=false → consumables expensed on purchase
```

Examples seeded: Raw Rock Salt (RAW_ROCK/kg), Crushed Salt (CRUSHED/kg),
Fine Crushed (SCREENED_GRADE/kg), Coarse Crushed (SCREENED_GRADE/kg),
25 kg Bag (PACKAGED, 25 kg/bag, unit BAG), 1 kg Pouch (PACKAGED, 1 kg, unit POUCH),
Packaging Material (MATERIAL, tracked=false).

Rules:
- Adding a grade or a package size = adding a row. **No code change.**
- Packaged sale in kg (e.g., loose from a torn bag) stays possible: `sale_lines.uom` supports
  KG for a PACKAGED product; conversion uses `default_pkg_weight_kg`.
- Work-in-progress is a real form (WIP) so partially-crushed lots are visible if needed.

## 2. Batches, locations, movements

**Batches** are created by purchase receipt, processing output, packaging, or opening balance.
```
batches: id, product_id, location_id, source_event_id, created_at, note
```

**Locations** (seeded: Khanewal Plant, Lahore Office): `locations(id, name, kind)`.

**Inventory movements — the single source of truth for stock.** Append-only:
```
movements: id, ts, product_id, location_id, batch_id (nullable), direction (+1/−1),
           qty, uom, unit_cost, value, reason enum:
             PURCHASE_RECEIPT | SALE_DISPATCH | SALE_RETURN_IN | PURCHASE_RETURN_OUT |
             PROCESS_INPUT | PROCESS_OUTPUT | PROCESS_WASTAGE | PACK_INPUT | PACK_OUTPUT |
             PACK_WASTAGE | TRANSFER_OUT | TRANSFER_IN | COUNT_ADJUST | OPENING_BALANCE
           event_id, reason_text (nullable), created_by
```
Every on-hand number in the app = SUM(movements). Nothing else may modify stock.

## 3. Costing: batch weighted-average with wastage and conversion cost

Chosen over pure FIFO / pure moving average — reasons in §8. Mechanics:

1. **Purchase receipt**: batch gets `total_cost = goods + freight + other attributable`,
   `unit_cost = total_cost / qty`. Freight invoices that arrive later attach to the batch
   and re-average. **Unknown-cost receipts enter at provisional cost** and are flagged.
2. **Processing run** (form: input product+qty, output product+qty per grade, weighed wastage):
   - Input cost = input qty × input batch unit cost.
   - Wastage: weighed kg valued at input unit cost. Steady % ⇒ expected yield shown to the
     operator before save; a run far outside the normal band asks for a reason.
   - Output cost pool = input cost − wastage value + attributable conversion costs attached
     to the run. Output unit cost = pool ÷ output kg (per grade; if one run yields several
     grades, allocate by output-kg weights or user-split — see §5).
3. **Packaging run**: consumed bulk salt + counted packaging materials + conversion costs →
   output batch in BAG/POUCH units. Both weight and units tracked on movements.
4. **Sale at dispatch**: COGS = dispatched qty × unit cost of the batch(es) consumed
   (batch pick recorded on the sale; default = oldest open batch). Unit costs are fixed at
   dispatch; later freight corrections adjust the *batch*, and the engine proposes a
   correction entry rather than rewriting the sale.
5. **Count adjustment**: reason required; adjustment value = qty diff × batch unit cost;
   large diffs flagged for review, never auto-silenced.

Stock valuation on the balance sheet = Σ(batch remaining qty × batch unit cost).

## 4. Events, double-entry, and the money model

**`events`** = what happened (user-facing), **`ledger_entries`** = financial consequence.
Every event posts balanced lines (debits = credits) across a small chart of accounts:

```
1000 Cash                     2100 Accounts Payable
1010 Cash - Bike/vehicle cashbox (optional, later)   2200 Customer Advances
1100 Accounts Receivable      3000 Owner Capital
1200 Inventory - Raw Rock     3100 Owner Drawings
1210 Inventory - Crushed      4000 Sales Revenue
1220 Inventory - Fine/Coarse  4100 COGS
1230 Inventory - Packaged     5000–5199 Operating expenses (per category)
1240 Inventory - Packaging Materials   5200 Wastage expense (P&L visible)
1300 Prepaid/Advances to suppliers     5300 Payroll
1400 Motorcycle (at cost)     5400 Depreciation (later)
1450 Livestock - Side Asset   9000 Suspense (must trend to zero)
```

Event catalog (one simple form each):
`PURCHASE · SALE · SALE_RETURN · PURCHASE_RETURN · PROCESS_RUN · PACK_RUN ·
CUSTOMER_PAYMENT · SUPPLIER_PAYMENT · EXPENSE · CAPITAL_IN · DRAWING ·
ASSET_PURCHASE · TRANSFER · COUNT_ADJUSTMENT · CORRECTION · OPENING_BALANCE`

Non-negotiable posting rules:
- **Advance received** → Dr Cash / Cr Customer Advances. NOT revenue.
- **Sale at dispatch** → Dr AR or Cash / Cr Revenue; **simultaneously** Dr COGS / Cr Inventory.
- **Customer payment** → Dr Cash / Cr AR. **Supplier payment** → Dr AP / Cr Cash.
- **Credit purchase** → Dr Inventory / Cr AP; **paid purchase** → Dr Inventory / Cr Cash.
- **Drawing** → Dr Drawings / Cr Cash. **Capital in** → Dr Cash / Cr Capital.
- **Motorcycle** → Dr Motorcycle asset / Cr Cash (+ depreciation later). Never salt cost.
- **Livestock** → Dr Side Asset / Cr Cash. Outside salt P&L, still on the books.
- **Processing run** → Dr output Inventory + Dr Wastage expense / Cr input Inventory.
- Anything questionable → post to **Suspense** with a review flag. Never auto-classify.

### Corrections — append-only, never delete
A CORRECTION event references the original event, stores who/when/why, and posts *reversing*
entries (or targeted reversing lines) plus the corrected ones. The original stays visible.
Movement corrections mirror this on the stock side. Deletion exists only as a UI-visible
"void" for events that were pure mistakes, still leaving an audit trail.

## 5. Open costing decisions (flagged, not hidden)

| # | Question | My default until you say otherwise |
|---|---|---|
| C1 | One crush run yields several grades: allocate cost by output kg, or set grade premia (e.g., fine 1.2×) to reflect extra handling? | **Output-kg proportional** (simple, defensible; premia distort if screens change) |
| C2 | General plant electricity (whole-plant meter): allocate to process runs, or expense? | **Expense in P&L, not salt cost** — allocation would be guesswork with one meter; revisit if a meter/sub-meter is installed |
| C3 | Crushing labour paid per day/per run | **Per-run when attributable** (enter on the process form), otherwise daily wages → P&L |
| C4 | Direct freight on sales (ex-works vs delivered pricing) | **Delivered = selling expense** unless you price FOB-plant; decide per sale at entry time |
| C5 | Weighed wastage outside the normal band | **Prompt for reason, post to wastage with flag** — never silently averaged away |

## §6. Reconciliation & integrity checks (dashboard-level, read-only)

Run after every write, shown on a "Health" panel; **they flag, never auto-fix**:
1. Σ movements per batch/product/location = displayed on-hand (trivially true by construction).
2. Σ ledger by account = reported balance (cash, AR, AP, inventory).
3. Inventory account balance = Σ batch value (product-internal consistency).
4. **Zero-cash guard**: a cash-out event may take book cash negative — allowed (real life:
   float from unrecorded capital) but flagged loudly as "capital injection likely missing".
5. UNCLEAR/review queue count shown on dashboard until cleared.
6. Excel-imported opening cash vs Σ events — must equal 77,044 + later events.
   (100 imported rows closing 77,044 on 2026-09-08 is the checksum.)

## 7. Schema summary (Postgres, hosted on Supabase)

```
users(id, name, is_admin)                       -- 2 seeded, simple PIN/password auth
products, locations, batches                    -- §1, §2
events(id, ts, type, ref, note, created_by, created_at, status ACTIVE|VOID,
       corrected_by_event, correction_reason)
event_payloads(event_id, jsonb)                 -- type-specific fields, validated server-side
movements(...)                                  -- §2
ledger_entries(id, event_id, account, side D|C, amount, memo)   -- balanced per event
parties(id, kind CUSTOMER|SUPPLIER|BOTH, name, phone, notes)
sales(id, event_id, party_id, ...)  sale_lines(sale_id, product_id, qty, uom, unit_price)
purchases(id, event_id, party_id, ...)  purchase_lines + landed-cost components
process_runs(id, event_id, inputs jsonb, outputs jsonb, wastage_kg, costs jsonb)
pack_runs(id, event_id, inputs jsonb, outputs jsonb, materials jsonb, costs jsonb)
payments(id, event_id, party_id, direction, amount, method, ref)  -- AR/AP settlement
expenses(id, event_id, category, party_id nullable, is_personal flag)
review_queue(id, event_id nullable, kind UNCLEAR|YIELD_OUTLIER|NEGATIVE_CASH|IMPORT_RECODE,
             severity, question, resolved_by_event, resolved_at)
audit_log(id, ts, user_id, action, entity, entity_id, before jsonb, after jsonb)
```

- Money: PKR integers (paisa via `numeric(14,2)` where needed); quantities `numeric(12,3)` kg.
- Every table carries `created_at`/`created_by`. `events.status` supports voids.
- RLS row-level security on Supabase; service key only on the server.

## 8. Rejected alternatives and why

- **Pure FIFO per grade**: with crush+screen splitting one batch into several grades and
  steady wastage, FIFO forces arbitrary cost splits at every run; weighted-average per batch
  is smoother and just as traceable here (batch identity is preserved through processing).
- **Pure moving average across all stock**: destroys the batch traceability you explicitly
  required (which mine, which cost, which run) for no simplicity gain at this scale.
- **Specific identification**: manual layer-picking on every sale — unnecessary for bulk salt.
- **Full manual chart of accounts / journal UI**: you'd be doing accounting, not running a
  business; the event catalog maps 1:1 to balanced postings instead.
- **Spreadsheet-as-DB / localStorage**: corruption + no audit + the current app's failure modes.

## 9. UI shape (stays simple; the engine is the smart part)

- **Record** screen: 8 plain buttons (Buy Salt, Process, Pack, Sell, Payment In, Payment Out,
  Expense, Correction). Each opens one short form. Father-proof: big fields, kg everywhere,
  expected-yield hint on process runs, clear warnings before saving odd numbers.
- **Books** screen: cash book (running balance), AR by customer, AP by supplier, inventory by
  product/location/batch with full movement history per batch.
- **Health** screen: reconciliation checks + review queue (UNCLEAR, yield outliers, negative
  cash flags) — the "no silent failure" layer.
- **Reports**: P&L (revenue, COGS, gross profit, opex, net), balance sheet, wastage %, yield
  by run, customer/supplier statements, Excel export preserving your current workbook shape.

## 10. Excel migration plan

1. Parse the 100 cash rows; map category → event type + account (mapping table in
   `docs/import_mapping.md`, reviewed before import).
2. BATCH-001 → opening inventory batch @ 7.5128/kg (15,210 kg, 114,270) at Khanewal.
3. 18 UNCLEAR rows → `review_queue` with the original text; amounts untouched.
4. "Rent office 17,100" → flagged recode (owner owns plant per READ_ME).
5. Vehicle CapEx lines → Motorcycle asset; Side Livestock → side asset; Eisha-type personal
   → drawings. Personal/unclear never touch salt cost.
6. Post-import report: every total reconciled to the paisa, printed and eyeballed by you.
7. The old workbook becomes read-only reference; the app is the system of record from cutover.

## 11. Implementation phases

- **P0 — Foundations (build first):** Supabase schema + migrations, auth (2 users),
  event/ledger engine with the posting rules, movement engine, reconciliation service,
  seed data (products, locations, chart of accounts). Tests: posting balance, movement sums.
- **P1 — Money & simple entries:** Cash book + expense + capital/drawing + party payments;
  import Excel opening history (§10). Tests: imported closing cash = 77,044 ± 0.
- **P2 — Inventory core:** Purchase receipt with landed cost; batches; stock views; count
  adjustments. Tests: BATCH-001 scenario reproduced to the paisa; movement-sum invariants.
- **P3 — Processing & packaging:** process/pack runs with wastage, yield hints, cost pooling,
  multi-grade allocation (C1). Tests: 10,000→9,700+300 worked example; cost conservation.
- **P4 — Sales & AR:** sale at dispatch, COGS at dispatch, advances vs credit, customer
  statements, returns. Tests: advance ≠ revenue; AR aging; return restores batch qty.
- **P5 — Supplier AP, corrections, audit log, review queue UI.**
- **P6 — Reports & dashboards** (all derived from ledger/movements, zero hardcoded numbers),
  Excel export.

Ordering rationale: money before stock (cash accuracy first, mirrors real usage), stock
before processing, processing before packaging (packaging is a special case of processing),
sales after inventory exists (COGS needs batches).

## 12. Testing strategy — "no silent failure"

- Unit tests for the posting engine: every event type must post balanced entries.
- Property tests: Σ(movements) == on-hand everywhere; Σ(Dr) == Σ(Cr) globally, always.
- Golden tests: the Excel history imports to the paisa (closing 77,044).
- Scenario tests: worked examples from this document (10,000→9,700+300; 1,000 kg sold →
  revenue/COGS/GP split; advance-then-dispatch-then-pay lifecycle).
- Invariant service runs on every mutation; failures block save with a clear message
  (e.g., "You have 3,200 kg crushed left; this sale of 4,000 kg is not possible").

## 13. Unknowns — need business input (tracked, non-blocking)

- Actual grade list + whether grades carry different selling prices today (affects C1 only).
- Whether any supplier bills freight separately after delivery (C4 scope).
- Depreciation policy for the motorcycle (asset is booked at cost for now).
- Exact PIN/password approach for father's login (recommend 4-digit PIN per user, no email).

## 14. Known gaps

Recorded 2026-09-27 after adding the baseline migration `20260926231834_baseline_live_state.sql`.
Not fixed yet — tracked here so nobody relies on the missing behaviour.

- **An empty database cannot be rebuilt from `supabase/migrations/` alone.** `app.parties` is only
  created in the baseline (dated after phase3), but the phase3 migrations already reference it.
  Replaying the migrations in order against an empty database fails at phase3. The live database
  is unaffected: every baseline statement is a no-op against it.
- **Two JARVIS tables need sequences that are not in any migration file.** `public.notifications`
  and `public.reject_log` default their `id` to `notifications_id_seq` / `reject_log_id_seq`,
  which the baseline does not create. On an empty database those two `create table` statements fail.

- **Sales 6–13 Sep drew stock from BATCH-075 before it arrived (14 Sep).** The true source was BATCH-001
  rock salt, ground at the plant, and the grinding was never recorded as a crush run. Fix with one
  adjustment at the first physical stock count. From now on every grinding is recorded in Crush Salt.

## 15. Corrections against the paper register

The paper register is the source of truth. Every fix is a **new** correcting entry posted through
`public.post_correction` (never an edit or delete): `source = 'correction'`, `source_ref` = the original
ref, its own idempotency key, created by the signed-in user. Posted 2026-09-27 by Rao Aosaf (Operator).

| | Original | What was wrong | Register says | Correcting entry | Status |
|---|---|---|---|---|---|
| A | CL-20260828-029 "Petrol", 28 Aug | booked Rs 5,000 | Rs 500 | **EV-000265** (28 Aug): Dr Cash 4,500 / Cr Fuel 4,500 | corrected |
| B | EV-000246 (Rs 900), EV-000247 (Rs 24,000), 6 Sep | not in register | — | two entries (6 Sep): Dr Cash / Cr Suspense 900 and 24,000 (Task 3c, below) | corrected |
| C | EV-000210 "sell Rs 3,150 (no kg)", 13 Sep | duplicate of Hakim Ali's Rs 3,100 payment EV-000174 | only one payment | **EV-000266** (13 Sep): Dr Suspense 3,150 / Cr Cash 3,150 | corrected |
| D | EV-000169 salt purchase Rs 117,500, 14 Sep | held as a payable | paid in cash in full that day | **EV-000267** (14 Sep): Dr Accounts Payable 117,500 / Cr Cash 117,500 | corrected |
| E | EV-000248 capital Rs 600,000, 19 Sep | typed in on 19 Sep | money arrived earlier; owner decision: 23 Aug | **EV-000263** (23 Aug): Dr Cash / Cr Owner Capital 600,000, then **EV-000264** (19 Sep): exact reverse of EV-000248 | corrected |

Results after A, C, D, E: cash on hand Rs 492,545.00; Owner Capital Rs 1,100,000; Accounts Payable
Rs 0; debtors Rs 21,390; debits = credits; day-by-day cash from 23 Aug never below zero (lowest
Rs 492,545 on 18 Sep).

### Task 3c — Suspense recategorised (posted 2026-09-27)

All mapping owner-confirmed. 68 new entries **EV-000336 to EV-000403**, each keyed `3c-<ref>` (`-a`/`-b`
for two-step items), dated the same day as its original, `source_ref` = the original, created by Rao
Aosaf (Operator), posted in one transaction:

- **Correction B:** EV-000246 and EV-000247 reversed (Dr 1000 / Cr 1900, Rs 24,900).
- **Money out (Dr account / Cr 1900):** 49 lines recoded to 1400 motorcycle (helmet, transfer fee),
  1500 fixed assets (weighing scale + transport), 3100 owner drawings (Eisha marriage), 5000 labour,
  5300 fuel, 5400 packaging (sacks, thread), 5500 site meals, 5600 travel, 5700 repairs (mistri,
  welding, clip and cable), 5800 admin (Valencia office rent, courier), 5900 other (gifts/help, small
  site costs, tap for goats' water).
- **EV-000243 travel Rs 1,500:** (a) 16 Sep Dr 1000 / Cr 1900 reverses it; (b) 15 Sep, the register
  date, Dr 5600 / Cr 1000.
- **Money in (Dr 1900 / Cr 4000):** sabit sales EV-000211/212/213/214 (Rs 1,650) plus EV-000209
  crushed salt Rs 100 (income only, kg unknown). The sabit 132 kg (40 + 48 + 4 + 40, owner rate
  40 kg = Rs 500) left BATCH-001 through `public.post_stock_correction` at BATCH-001's own cost
  (Rs 7.51/kg, Rs 991.32: Dr 4100 / Cr 1200 plus an 'out' movement).
- **Wrong category outside Suspense:** EV-000233 13,500 → 1500 (plant electrical goods, not the bill);
  EV-000236 580 and EV-000237 1,600 → 5700; CL-20260829-033 500 goat feed 1450 → 5900;
  CL-20260901-056 300 chai → 1400 (motorcycle key); CL-20260902-061 500 khana → 5900.
- **Master data:** SALT_ROCK's form set to `raw` (migration `20260927091550`) so rock salt leaves the
  account it was bought into (1200), not 1210.
- **No change (owner):** EV-000179; the rock-salt load date (3 vs 6 Sep); BATCH-075 stays 12,500 kg;
  INV-00037/38/39/53 and the 6–12 Sep dispatches.

Results, all checked after posting: Suspense Rs 0.00; cash Rs 517,445.00; debits = credits (no
unbalanced event); no negative cash day 23 Aug onward; debtors Rs 21,390; Utilities Rs 17,638 →
1,958 (−15,680); BATCH-001 15,210 → 15,078 kg; stock tie holds per account (1200 = 113,278.68,
1210 = 92,284.50, ledger = movements).

### EV-000404 — security cameras (posted 2026-09-27)

EV-000404 "3 security cameras" Rs 11,297 was entered on the phone as Vehicle (1400) dated 27 Sep; the
Money Out form had no Equipment option and the date defaulted to today. Owner-confirmed:
**EV-000405** (27 Sep, key `3c-EV-000404-a`) Dr 1000 / Cr 1400 11,297 reverses it; **EV-000406**
(24 Sep, key `3c-EV-000404-b`) Dr 1500 / Cr 1000 11,297, paid 24 Sep. After: cash Rs 506,148.00,
1400 Rs 135,670.00, 1500 Rs 35,197.00, debits = credits, no negative cash day. Form fixed the same
day: Money Out has no default type (Equipment / other assets 1500 added) and every entry form shows
its date first, in words, with "change if not today" (Pakistan time).

EV numbers 268–335 are unused: a rolled-back dry run consumed them (Postgres sequences never roll
back). No entry was lost; the numbers are simply skipped.

**Future task:** make the cash guard check the day-by-day running balance, not only the total.
`app.assert_cash_nonnegative` checks today's total cash only, so a back-dated entry could make
history show a negative day without being blocked. The 2026-09-27 corrections were checked by hand
(no negative day), but the database does not enforce it yet.

## 16. Access control (Task 3, 2026-09-27)

- **anon (the public key) can do nothing**: no EXECUTE on any `app`/`public` function, no SELECT on any
  table/view/sequence, no USAGE on schema `app`. Verified by curl: every call returns HTTP 401 `42501`.
- **Signed-in users** reach data only if `app.is_allowed_user()` is true (their `auth.users.id` is linked
  in `app.users.auth_user_id` and the row is active). Every `app` table has one policy, `auth_read`, and
  every `app.v_*` / `public.v_*` view is `security_invoker`, so RLS applies all the way down.
- **Writes** go only through guarded `public.*` wrappers (`app.require_user()` raises "Not authorised").
  The real logic lives in `app.*_impl` (callable only by `postgres`). `created_by` is always taken from
  the signed-in user on the server; the `p_created_by` argument sent by the app is ignored.
- **JARVIS** tables (`public.contacts`, `research_leads`, `notifications`, `reject_log`,
  `staging_candidates`): RLS on, no policies, no anon/authenticated privileges. JARVIS connects as
  `postgres` (owner, BYPASSRLS) through the pooler and is unaffected.
- **JARVIS and the ledger (built 2026-09-28, migration `20260927191127`):** JARVIS has its own
  Supabase login (`aaa_trading.pk+jarvis@outlook.com`) linked to the `app.users` row
  "JARVIS (Rao's assistant)", role `assistant`. It reads the ledger through the same RLS as the app
  (every `public.v_*` view, including `v_ledger_health`) and cannot read the JARVIS tables above.
  It is **read-only**: `app.require_user()` refuses role `assistant`, so every save function answers
  "Not authorised". Writing stays closed until `post_event` is restricted (Wave 2 item 8) and the owner
  approves; then it would call the same guarded RPCs and every entry would be attributed to it.
  JARVIS must stop using the `postgres` role for the ledger.
- Remaining advisor WARNs are intentional: the 10 guarded RPCs are SECURITY DEFINER and executable by
  `authenticated` (that is how the app writes); "leaked password protection" is an Auth dashboard switch.
  Supabase's own `supabase_admin` default privileges in `public` still grant new objects to anon; only
  objects created by `postgres` (all of ours) are covered by the new defaults.

### Rollback (only if the app breaks after Task 3)

Run in the Supabase SQL editor, **only the part you need**, undoing C, then B, then A.
3D (dropping the 9-argument `record_purchase`) should **not** be undone — it fixed the Salt Purchase form.

```sql
-- Undo 3C (JARVIS tables back to open)
alter table public.contacts disable row level security;
alter table public.research_leads disable row level security;
alter table public.notifications disable row level security;
alter table public.reject_log disable row level security;
grant all on public.contacts, public.research_leads, public.notifications, public.reject_log,
  public.staging_candidates to anon, authenticated;
grant all on sequence public.notifications_id_seq, public.reject_log_id_seq to anon, authenticated;

-- Undo 3B (reads: views back to owner-run, anon read policies and grants back)
alter view public.v_debtors set (security_invoker = false);
alter view public.v_parties set (security_invoker = false);
alter view app.v_account_balances set (security_invoker = false);
alter view app.v_batch_costs set (security_invoker = false);
alter view app.v_batches set (security_invoker = false);
alter view app.v_cash_summary set (security_invoker = false);
alter view app.v_debtors set (security_invoker = false);
alter view app.v_dispatch_allocations set (security_invoker = false);
alter view app.v_events_with_party set (security_invoker = false);
alter view app.v_sales set (security_invoker = false);
alter view app.v_stock_onhand set (security_invoker = false);
grant usage on schema app to anon;
grant select on all tables in schema app to anon;
grant select on all sequences in schema app to anon;
grant all on public.v_account_balances, public.v_accounts, public.v_advances, public.v_batch_costs, public.v_batches,
  public.v_customers, public.v_debtors, public.v_dispatch_allocations, public.v_events_with_party, public.v_ledger_lines,
  public.v_locations, public.v_parties, public.v_products, public.v_review_queue, public.v_sales, public.v_stock_onhand
  to anon, authenticated, service_role;
do $$
declare t text;
begin
  foreach t in array array['accounts','batches','events','ledger_entries','locations','movements',
                           'products','review_queue','stg_excel_cash','users'] loop
    execute format('create policy anon_read on app.%I for select to anon using (true)', t);
  end loop;
  foreach t in array array['sales','sale_lines','dispatches','dispatch_allocations','customer_advances','batch_cost_components'] loop
    execute format('create policy read_only on app.%I for select to anon, authenticated using (true)', t);
  end loop;
end $$;
create policy "parties read" on app.parties for select to public using (true);
alter default privileges for role postgres in schema public grant all on tables to anon;
alter default privileges for role postgres in schema public grant all on sequences to anon;
alter default privileges for role postgres in schema public grant execute on functions to anon;
alter default privileges for role postgres in schema app grant select on tables to anon;
alter default privileges for role postgres grant execute on functions to public;

-- Undo 3A (functions: remove wrappers, move the original functions back, reopen EXECUTE)
drop function public.create_customer(text, text, text);
drop function public.record_customer_payment(text, bigint, date, text, uuid, text);
drop function public.record_dispatch(text, jsonb, date, text, text, uuid);
drop function public.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid);
drop function public.record_purchase(text, text, text, bigint, bigint, boolean, date, text, uuid, text, jsonb);
drop function public.record_sale(text, jsonb, bigint, text, date, text, text, uuid);
drop function public.record_udhaar_sale(text, jsonb, bigint, text, date, text, text, uuid, text);
drop function public.resolve_review_item(integer, text, boolean);
drop function public.suggest_sale_price(text, text, numeric);
alter function app.create_customer_impl(text, text, text) rename to create_customer;
alter function app.create_customer(text, text, text) set schema public;
alter function app.record_customer_payment_impl(text, bigint, date, text, uuid, text) rename to record_customer_payment;
alter function app.record_customer_payment(text, bigint, date, text, uuid, text) set schema public;
alter function app.record_dispatch_impl(text, jsonb, date, text, text, uuid) rename to record_dispatch;
alter function app.record_dispatch(text, jsonb, date, text, text, uuid) set schema public;
alter function app.record_process_run_impl(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid) rename to record_process_run;
alter function app.record_process_run(text, bigint, jsonb, bigint, bigint, boolean, date, text, uuid) set schema public;
alter function app.record_purchase_impl(text, text, text, bigint, bigint, boolean, date, text, uuid, text, jsonb) rename to record_purchase;
alter function app.record_purchase(text, text, text, bigint, bigint, boolean, date, text, uuid, text, jsonb) set schema public;
alter function app.record_sale_impl(text, jsonb, bigint, text, date, text, text, uuid) rename to record_sale;
alter function app.record_sale(text, jsonb, bigint, text, date, text, text, uuid) set schema public;
alter function app.record_udhaar_sale_impl(text, jsonb, bigint, text, date, text, text, uuid, text) rename to record_udhaar_sale;
alter function app.record_udhaar_sale(text, jsonb, bigint, text, date, text, text, uuid, text) set schema public;
alter function app.resolve_review_item_impl(integer, text, boolean) rename to resolve_review_item;
alter function app.resolve_review_item(integer, text, boolean) set schema public;
alter function app.suggest_sale_price_impl(text, text, numeric) rename to suggest_sale_price;
alter function app.suggest_sale_price(text, text, numeric) set schema public;
create or replace function public.post_event(p_event_type text, p_occurred_on date, p_description text, p_lines jsonb,
  p_party_type text default null, p_party_name text default null, p_created_by uuid default null)
returns text language plpgsql security definer set search_path = app as $$
begin
  return app.post_event(p_event_type, p_occurred_on, p_description, p_lines, p_party_type, p_party_name, p_created_by);
end $$;
create or replace function public.record_customer_advance(p_customer text, p_amount_paisa bigint, p_occurred_on date default current_date,
  p_note text default null, p_idempotency_key text default null, p_created_by uuid default null)
returns jsonb language sql security definer set search_path = app as $$
  select app.record_advance(p_customer, p_amount_paisa, p_occurred_on, p_note, p_idempotency_key, p_created_by)
$$;
grant execute on all functions in schema public to public, anon, authenticated, service_role;
grant execute on all functions in schema app to public, anon, authenticated;
```

After undoing 3A the app still works for the signed-in user (it always sends `p_created_by`), but writes
are no longer guarded and the anon key regains the old, unsafe access.
