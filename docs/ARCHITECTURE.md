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

## 15. Pending corrections — awaiting owner confirmation

Found by auditing the app against the paper register. **Nothing has been changed in the books.** Each
error will be fixed with a reversing entry (never a delete) only after the owner confirms it.

| Date | Entry | App says | Register says | Status |
|---|---|---|---|---|
| 28 Aug | "Petrol" CL-20260828-029 | Rs 5,000 | Rs 500 | awaiting confirmation |
| 6 Sep | EV-000246 | Rs 900 | not in register | awaiting father |
| 6 Sep | EV-000247 | Rs 24,000 | not in register | awaiting father |
| 13 Sep | EV-000210 "sell Rs 3,150 (no kg)" | Rs 3,150 | duplicate of Hakim Ali's Rs 3,100 payment EV-000174 | awaiting confirmation |
| 14 Sep | Salt purchase EV-000169 | Rs 117,500 held as a payable | **confirmed by owner: paid in cash in full that day** | confirmed — correction to be posted |

Not errors, recategorisation only:

- "Sabiqa" EV-000211 to EV-000214 (Rs 1,650 cash-in): real cash received for earlier sales.
  Amounts are correct; they only need moving out of Suspense later.
- 8 Sep correction entries EV-000252 to EV-000262 (Rs 3,630 total) are in the register and correct — no action.
