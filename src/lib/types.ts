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
  value_pkr?: number
}

export type PurchaseResult = {
  event_ref: string
  batch_code: string
}

export type ProcessRunResult = {
  event_ref: string
  input_batch: string
  input_value_paisa: number
  wastage_grams: number
  wastage_value_paisa: number
  wastage_expense_paisa: number
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

export type SaleLineRow = {
  id: number
  sale_id: number
  line_no: number
  product_id: number
  qty_grams: number
  unit_price_paisa_per_kg: number
  revenue_paisa: number
  dispatched_grams: number
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
