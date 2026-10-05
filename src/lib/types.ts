/**
 * Shared types mirroring the database (Phase 0 schema, `app` schema).
 * Money is paisa (PKR × 100) — BigInt-safe via number (max ~90 trillion paisa).
 * Quantities are grams.
 */

export type LedgerLine = {
  account: string
  debit?: number
  credit?: number
}

export type PostEventInput = {
  eventType: string
  occurredOn: string
  description: string
  lines: LedgerLine[]
  partyType?: string
  partyName?: string
  /** One key per entry attempt; reused on every retry of that same entry. */
  idempotencyKey: string
}

export type EventRow = {
  id: number
  event_ref: string
  event_type: string
  occurred_on: string
  description: string
  party_type: string | null
  party_name: string | null
  source: string
  source_ref: string | null
  created_at: string
  created_by_name: string | null
  total_paisa: number
  /** real cash effect of the entry on 1000 Cash on Hand: + in, − out, 0 = no cash moved */
  cash_net_paisa: number
}

/** One ledger line with its event context — used for account drill-downs. */
export type AccountLineRow = {
  event_id: number
  entry_seq: number
  occurred_on: string
  event_ref: string
  description: string
  debit_paisa: number
  credit_paisa: number
}

/** What deleting an entry would do (public.delete_entry_preview). Amounts in paisa, stock in kg. */
export type DeletePreview = {
  found: boolean
  ref: string
  blockers?: string[]
  entries?: { ref: string; type: string; date: string; description: string; amount_paisa: number }[]
  cash_before_paisa?: number
  cash_change_paisa?: number
  stock?: { batch: string; kg_before: number; kg_change: number; value_change_paisa: number }[] | null
  customers?: { name: string; owes_before_paisa: number; owes_after_paisa: number }[] | null
  suppliers_owed_before_paisa?: number
  suppliers_owed_change_paisa?: number
  advances_change_paisa?: number
  batches_removed?: string[] | null
  customers_removed?: string[] | null
  /** every account the delete changes, balance on its normal side */
  accounts?: { code: string; name: string; before_paisa: number; change_paisa: number; after_paisa: number }[]
  /** when the entry is a correction: what it corrects, and other corrections of the same original that would stay */
  corrections?: { ref: string; original_ref: string; original_description: string | null; others_staying: string | null }[]
  /** the word to type before the database allows the delete ('UNDO' for a correction) */
  needs_word?: string | null
}

/** A money entry as the correction form opens it (public.correct_entry_preview without lines). */
/** One entry still in 5950 Personal/Unclassified (public.v_unclassified). */
export type UnclassifiedRow = {
  original_ref: string
  original_date: string | null
  /** the paper register wording of the original entry */
  original_description: string | null
  /** the latest version of the entry: the one to correct */
  latest_ref: string
  entry_date: string
  amount_paisa: number
}

/** The entry as it is now: the original + all its corrections added up (the latest version is the one to correct). */
export type CorrectionStart = {
  ref: string
  original_ref: string
  date: string
  type: string
  description: string
  lines: { account: string; name: string; debit: number; credit: number }[]
  /** why this entry cannot be corrected here (null = it can) */
  blocker: string | null
}

/** What a correction will post (preview) or posted (save). */
export type CorrectionPlan = {
  plan: { kind: 'fix' | 'reverse' | 'repost'; date: string; lines: { account: string; debit: number; credit: number }[] }[]
  accounts?: { code: string; name: string; before_paisa: number; after_paisa: number }[]
  event_refs?: string[]
  duplicate?: boolean
}

/** A deleted entry kept for restore (public.v_deleted_entries). */
export type DeletedEntry = {
  id: number
  deleted_at: string
  deleted_by_name: string | null
  reason: string
  event_refs: string[]
  summary: DeletePreview & { requested_ref?: string }
  restored_at: string | null
  restored_by_name: string | null
}

/** One day of the cash book (public.v_cash_days). */
export type CashDay = { occurred_on: string; lines: number; in_paisa: number; out_paisa: number; opening_paisa: number; closing_paisa: number }

/** One line of the cash book with its running balance (public.v_cash_book). */
export type CashLine = {
  occurred_on: string
  event_id: number
  event_ref: string
  description: string
  source: string
  entry_seq: number
  in_paisa: number
  out_paisa: number
  balance_paisa: number
}

/** A day as the cash book screen shows it: the day's lines plus the days either side that have entries. */
export type CashBookDay = { day: CashDay | null; lines: CashLine[]; before: CashDay | null; after: string | null }

/** Per-account totals computed by the database (public.v_account_totals). */
export type AccountTotals = { code: string; line_count: number; debit_paisa: number; credit_paisa: number }

/** Sales totals over all invoices (public.v_sales_totals). */
export type SalesTotals = {
  invoices: number
  revenue_paisa: number
  cogs_paisa: number
  dispatched_revenue_paisa: number
  dispatched_cogs_paisa: number
  not_fully_dispatched: number
}

/** Integrity checks computed by the database (public.v_ledger_health). */
export type LedgerHealth = {
  total_debit_paisa: number
  total_credit_paisa: number
  stock_ledger_paisa: number
  stock_movements_paisa: number
  stock_mismatched_accounts: number
  negative_cash_days: number
  lowest_cash_paisa: number | null
}

export type AccountBalance = {
  code: string
  name: string
  type: 'asset' | 'liability' | 'equity' | 'income' | 'expense'
  kind: string
  balance_paisa: number
}

export type StockOnHand = {
  batch_code: string
  product_code: string
  product_name: string
  location_code: string
  location_name: string
  qty_grams: number
  value_paisa: number
}

export type ReviewItem = {
  id: number
  source: string
  severity: string
  title: string
  detail: {
    excel_txn?: string
    date?: string
    category?: string
    description?: string
    amount_paisa?: number
    amount_display?: string
    provisional_account?: string
    side?: string
  }
  source_ref: string | null
  status: string
  created_at: string
}

export type Product = {
  id: number
  code: string
  name: string
  form: 'raw' | 'bulk_processed' | 'packaged' | 'packaging_material' | string
  base_unit: string | null
  is_active: boolean
}

export type Location = {
  id: number
  code: string
  name: string
  kind: string
  is_active: boolean
}

export type BatchRow = {
  id: number
  batch_code: string
  product_code: string
  product_name: string
  location_code: string
  location_name: string
  status: string
  opened_on: string
  note: string | null
  onhand_grams: number
  value_paisa: number
  wastage_grams: number
  wastage_value_paisa: number
}

export type GradeOutput = {
  product_code: string
  qty_kg: number
}

/** One crushing-cost line: the full amount goes into the salt cost; paid now = cash, the rest is owed to `owed_to`. */
export type CrushCost = {
  kind: 'labour' | 'electricity' | 'diesel' | 'bags' | 'other'
  amount_paisa: number
  paid_now_paisa: number
  owed_to?: string
  expected_on?: string
}

/** The database's crush figures (public.crush_preview) — the same calculation the save uses. */
export type CrushPreview = {
  input_value_paisa: number
  /** rock value used + crushing cost: all of it goes to the good salt */
  pool_paisa: number
  output_grams: number
  outputs: { product_code: string; product_name: string; qty_grams: number; value_paisa: number }[]
  lines: { account: string; debit: number; credit: number; party?: string }[]
  costs: { total_paisa: number; paid_now_paisa: number; later_paisa: number; owed: { name: string; amount_paisa: number; bill: boolean }[]; words: string }
}

/** What we owe one supplier (public.v_supplier_balances). extra_to_account set = a monthly bill (paying more is fine). */
export type SupplierBalance = {
  party_id: number
  party_ref: string
  name: string
  extra_to_account: string | null
  owed_paisa: number
  last_owed_on: string | null
  last_paid_on: string | null
}

export type PaySupplierResult = {
  event_ref: string
  supplier: string
  paid_paisa: number
  cleared_paisa: number
  extra_paisa: number
  extra_account: string | null
  owed_after_paisa: number
}

export type PurchaseResult = {
  event_ref: string
  batch_code: string
}

export type ProcessRunResult = {
  event_ref: string
  input_batch: string
  input_value_paisa: number
  cost_paisa: number
  pool_paisa: number
  output_grams: number
  wastage_grams: number
  outputs: { batch_code: string; product_code: string; product_name: string; qty_grams: number; value_paisa: number }[]
}

/** Per-event ledger lines for the drill-down view. */
export type LedgerEntryRow = {
  id: number
  event_id: number
  entry_seq: number
  debit_paisa: number
  credit_paisa: number
  account_code: string
  account_name: string
}

/* ---------- Phase 3: Sales & Dispatch ---------- */

export type Customer = {
  id: number
  party_ref: string
  name: string
  phone: string | null
  kind: string
}

export type SaleRow = {
  id: number
  sale_ref: string
  occurred_on: string
  customer_name: string
  party_ref: string
  status: 'invoiced' | 'dispatched' | string
  currency: string
  fx_rate: number
  total_revenue_paisa: number
  cash_received_paisa: number
  advance_applied_paisa: number
  ar_paisa: number
  cogs_paisa: number
  gross_profit_paisa: number
  gross_margin_pct: number
  dispatched_grams: number
  invoiced_grams: number
}

export type DispatchAllocationRow = {
  dispatch_ref: string
  occurred_on: string
  sale_ref: string
  customer_name: string
  product_code: string
  product_name: string
  batch_code: string
  qty_grams: number
  unit_cost_paisa_per_kg: number
  cogs_paisa: number
  allocation_mode: string
  override_reason: string | null
  total_cogs_paisa: number
}

export type DebtorRow = {
  party_id: number
  party_ref: string
  customer_name: string
  phone: string | null
  outstanding_paisa: number
  total_invoiced_paisa: number
  total_paid_paisa: number
  last_sale_on: string | null
  last_payment_on: string | null
}

/** Row of app.fifo_pool(p_product_id, p_location_id) — open batches, oldest first. */
export type FifoBatch = {
  batch_id: number
  batch_code: string
  opened_on: string
  onhand_grams: number
  unit_cost_ppk: number
}

export type SaleResult = {
  sale_ref: string
  event_ref: string
  party_ref: string
  party_created: boolean
  revenue_paisa: number
  cash_paisa: number
  advance_applied_paisa: number
  ar_paisa: number
  duplicate?: boolean
  lines: {
    line_no: number
    product_code: string
    qty_grams: number
    unit_price_paisa_per_kg: number
    revenue_paisa: number
  }[]
}

export type DispatchResult = {
  dispatch_ref: string
  sale_ref: string
  cogs_paisa: number
  revenue_paisa: number
  gross_profit_paisa: number
  duplicate?: boolean
  allocations: {
    sale_line_id: number
    product_id: number
    batch_id: number
    batch_code: string
    qty_grams: number
    unit_cost_ppk: number
    cogs_paisa: number
    mode: 'fifo' | 'manual'
    reason: string | null
  }[]
}

export type DispatchLineInput = {
  productCode: string
  qtyKg: number
  locationCode: string
  mode: 'fifo' | 'manual'
  overrideReason?: string
  allocations?: { batchCode: string; qtyKg: number }[]
}

export function paisaToPkr(paisa: number): string {
  return (paisa / 100).toLocaleString('en-PK', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

export function gramsToKg(grams: number): string {
  return (grams / 1000).toLocaleString('en-PK', { maximumFractionDigits: 1 })
}
