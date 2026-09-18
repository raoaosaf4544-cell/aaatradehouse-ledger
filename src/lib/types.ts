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

export function paisaToPkr(paisa: number): string {
  return (paisa / 100).toLocaleString('en-PK', {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

export function gramsToKg(grams: number): string {
  return (grams / 1000).toLocaleString('en-PK', { maximumFractionDigits: 1 })
}
