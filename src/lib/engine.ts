import * as Sentry from '@sentry/react'
import { supabase } from './supabase'
import { markUsingCache, recall, remember } from './offline'
import type {
  AccountBalance,
  EventRow,
  LedgerEntryRow,
  PostEventInput,
  ProcessRunResult,
  Product,
  PurchaseResult,
  ReviewItem,
  StockOnHand,
  Location,
  BatchRow,
  GradeOutput,
  Customer,
  SaleRow,
  DispatchAllocationRow,
  DebtorRow,
  AccountLineRow,
  AccountTotals,
  SalesTotals,
  LedgerHealth,
  CashBookDay,
  CashDay,
  CashLine,
  DeletePreview,
  DeletedEntry,
  CrushPreview,
  CorrectionStart,
  CorrectionPlan,
  UnclassifiedRow,
  SupplierBalance,
  PaySupplierResult,
} from './types'

/**
 * Data-access layer over the `app` schema.
 * Rules:
 *  - Every write goes through app.post_event (guarded, append-only).
 *  - Every read comes from derived views or direct row selects — the DB is the
 *    single calculator; the client never re-derives balances its own way.
 *  - Invariant violations surface as thrown errors carrying the DB's exact message.
 */

export class InvariantError extends Error {
  /**
   * true  = the database (or the form's own check) clearly said NO: nothing was saved.
   * false = no clear answer (no signal, timeout): the save MAY have reached the server.
   */
  definite: boolean
  /** true = the message is the database's own text: never shown as-is (see lib/friendly.ts). */
  fromServer: boolean
  constructor(message: string, definite = true, fromServer = false) {
    super(message)
    this.name = 'InvariantError'
    this.definite = definite
    this.fromServer = fromServer
  }
}

/** Page size for long lists. The API returns at most 1000 rows per request, so nothing loads "everything". */
export const PAGE_SIZE = 30

/** A save with no reply for this long is treated as "not saved — retry". */
export const SAVE_TIMEOUT_MS = 20_000

/** Postgres/PostgREST error codes mean the server answered; anything else is a network problem. */
function rpcError(error: { message: string; code?: string | null }): InvariantError {
  const answered = /^(PGRST\d+|[0-9A-Z]{5})$/.test(error.code ?? '')
  return new InvariantError(error.message, answered, answered)
}

/**
 * Write RPCs give up after SAVE_TIMEOUT_MS so the form can offer Retry with the same key.
 * Every save the database refuses is reported to Sentry with the RPC name and the reason. Numbers are masked (#):
 * financial figures never leave the machine in error payloads.
 */
async function saveRpc(fn: string, args: Record<string, unknown>) {
  const res = await supabase.rpc(fn, args).abortSignal(AbortSignal.timeout(SAVE_TIMEOUT_MS))
  if (res.error && /^(PGRST\d+|[0-9A-Z]{5})$/.test(res.error.code ?? '')) {
    const reason = res.error.message.replace(/\d[\d.,]*/g, '#')
    Sentry.captureMessage(`Refused save: ${fn}`, {
      level: 'warning',
      tags: { rpc: fn, pg_code: res.error.code ?? '' },
      extra: { reason },
      fingerprint: ['refused-save', fn, reason],
    })
  }
  return res
}

/** Crush arguments shared by the save and the preview. Only kg and the rate go to the database; it computes every value. */
function crushArgs(i: { inputBatchCode: string; inputQtyKg: number; outputs: GradeOutput[]; wastageKg: number; ratePkrPerKg: number }) {
  return {
    p_input_batch_code: i.inputBatchCode,
    p_input_qty_grams: Math.round(i.inputQtyKg * 1000),
    p_outputs: i.outputs.map((o) => ({ product_code: o.product_code, qty_grams: Math.round(o.qty_kg * 1000) })),
    p_wastage_grams: Math.round(i.wastageKg * 1000),
    p_rate_paisa_per_kg: Math.round(i.ratePkrPerKg * 100),
  }
}

/** What the database confirms for an entry saved under an idempotency key. */
export type ConfirmedEntry = { event_ref: string; occurred_on: string; total_paisa: number }

type AccountRow = { id: number; code: string; name: string }

/**
 * Read-only methods. With no signal they return the last answer remembered for this login, so the
 * screens still show the books (read-only). Writes and entryByKey are never answered from memory.
 */
const OFFLINE_READS = [
  'listEvents', 'accountBalances', 'stockOnHand', 'batches', 'products', 'locations', 'openReviewItems',
  'eventLines', 'accountLines', 'accountTotals', 'customers', 'customerAdvanceBalance', 'sales', 'salesTotals',
  'dispatchAllocations', 'debtors', 'ledgerHealth', 'cashDay', 'deletedEntries', 'supplierNames', 'supplierBalances', 'unclassified',
] as const

export class LedgerEngine {
  /** app.users.id of the signed-in person; set by App after login via current_app_user(). */
  userId: string | null = null

  constructor() {
    const self = this as unknown as Record<string, (...args: unknown[]) => Promise<unknown>>
    for (const name of OFFLINE_READS) {
      const live = self[name].bind(this)
      self[name] = async (...args: unknown[]) => {
        const key = name + JSON.stringify(args)
        if (!navigator.onLine) {
          // phone says no signal: show the remembered figures at once (no slow retries)
          const last = recall(key)
          if (last !== undefined) {
            markUsingCache(true)
            return last
          }
        }
        try {
          const value = await live(...args)
          remember(key, value)
          markUsingCache(false)
          return value
        } catch (e) {
          if (e instanceof InvariantError && !e.definite) {
            const last = recall(key)
            if (last !== undefined) {
              markUsingCache(true)
              return last
            }
          }
          throw e
        }
      }
    }
  }

  private createdBy(): string {
    if (!this.userId) throw new InvariantError('Not signed in — please sign in again before recording.')
    return this.userId
  }

  /** One page of events, newest first (from app.v_events_with_party). */
  async listEvents(limit = PAGE_SIZE, offset = 0): Promise<EventRow[]> {
    const { data, error } = await supabase
      .from('v_events_with_party')
      .select('*')
      .order('occurred_on', { ascending: false })
      .order('event_ref', { ascending: true })
      .range(offset, offset + limit - 1)
    if (error) throw rpcError(error)
    return data as EventRow[]
  }

  /** Account balances (from app.v_account_balances). */
  async accountBalances(): Promise<AccountBalance[]> {
    const { data, error } = await supabase
      .from('v_account_balances')
      .select('*')
      .order('code', { ascending: true })
    if (error) throw rpcError(error)
    return data as AccountBalance[]
  }

  /** Stock on hand per batch/product/location (from app.v_stock_onhand). */
  async stockOnHand(): Promise<StockOnHand[]> {
    const { data, error } = await supabase
      .from('v_stock_onhand')
      .select('*')
      .order('batch_code', { ascending: true })
    if (error) throw rpcError(error)
    return data as StockOnHand[]
  }

  /** All batches with on-hand, value and wastage (from public.v_batches). */
  async batches(): Promise<BatchRow[]> {
    const { data, error } = await supabase
      .from('v_batches')
      .select('*')
      .order('opened_on', { ascending: false })
    if (error) throw rpcError(error)
    return data as BatchRow[]
  }

  /** Active products for dropdowns. */
  async products(): Promise<Product[]> {
    const { data, error } = await supabase
      .from('v_products')
      .select('*')
      .eq('is_active', true)
      .order('code', { ascending: true })
    if (error) throw rpcError(error)
    return data as Product[]
  }

  /** Active locations for dropdowns. */
  async locations(): Promise<Location[]> {
    const { data, error } = await supabase
      .from('v_locations')
      .select('*')
      .eq('is_active', true)
      .order('name', { ascending: true })
    if (error) throw rpcError(error)
    return data as Location[]
  }

  /** Open review-queue items (from public.v_review_queue). */
  async openReviewItems(): Promise<ReviewItem[]> {
    const { data, error } = await supabase
      .from('v_review_queue')
      .select('*')
      .eq('status', 'open')
      .order('id', { ascending: true })
      .limit(200)
    if (error) throw rpcError(error)
    return data as ReviewItem[]
  }

  /**
   * Ledger lines for given events (from public.v_ledger_lines — account codes
   * resolved server-side).
   */
  async eventLines(eventIds: number[]): Promise<Map<number, LedgerEntryRow[]>> {
    const result = new Map<number, LedgerEntryRow[]>()
    if (eventIds.length === 0) return result

    const { data, error } = await supabase
      .from('v_ledger_lines')
      .select('id, event_id, entry_seq, debit_paisa, credit_paisa, account_code, account_name')
      .in('event_id', eventIds)
      .order('entry_seq', { ascending: true })
    if (error) throw rpcError(error)

    for (const l of (data ?? []) as LedgerEntryRow[]) {
      const list = result.get(l.event_id) ?? []
      list.push(l)
      result.set(l.event_id, list)
    }
    return result
  }

  /** One page of an account's ledger lines, newest first, with date/ref/description (public.v_account_lines). */
  async accountLines(accountCode: string, limit = PAGE_SIZE, offset = 0): Promise<AccountLineRow[]> {
    const { data, error } = await supabase
      .from('v_account_lines')
      .select('event_id, entry_seq, debit_paisa, credit_paisa, occurred_on, event_ref, description')
      .eq('account_code', accountCode)
      .order('occurred_on', { ascending: false })
      .order('event_id', { ascending: false })
      .order('entry_seq', { ascending: true })
      .range(offset, offset + limit - 1)
    if (error) throw rpcError(error)
    return data as AccountLineRow[]
  }

  /** Line count and debit/credit totals of one account, computed by the database. */
  async accountTotals(accountCode: string): Promise<AccountTotals> {
    const { data, error } = await supabase.from('v_account_totals').select('*').eq('code', accountCode).single()
    if (error) throw rpcError(error)
    return data as AccountTotals
  }

  /**
   * One day of the cash book: that day's cash lines with running balance, the day totals, the last day before it
   * that has entries (its closing is the opening when this day has none) and the next day that has entries.
   */
  async cashDay(date: string): Promise<CashBookDay> {
    const [day, lines, before, after] = await Promise.all([
      supabase.from('v_cash_days').select('*').eq('occurred_on', date).maybeSingle(),
      supabase.from('v_cash_book').select('*').eq('occurred_on', date)
        .order('event_id', { ascending: true }).order('entry_seq', { ascending: true }),
      supabase.from('v_cash_days').select('*').lt('occurred_on', date).order('occurred_on', { ascending: false }).limit(1).maybeSingle(),
      supabase.from('v_cash_days').select('occurred_on').gt('occurred_on', date).order('occurred_on', { ascending: true }).limit(1).maybeSingle(),
    ])
    for (const r of [day, lines, before, after]) if (r.error) throw rpcError(r.error)
    return {
      day: (day.data as CashDay | null) ?? null,
      lines: (lines.data ?? []) as CashLine[],
      before: (before.data as CashDay | null) ?? null,
      after: (after.data as { occurred_on: string } | null)?.occurred_on ?? null,
    }
  }

  /** Integrity checks computed by the database (debits = credits, stock tie, no negative cash day). */
  async ledgerHealth(): Promise<LedgerHealth> {
    const { data, error } = await supabase.from('v_ledger_health').select('*').single()
    if (error) throw rpcError(error)
    return data as LedgerHealth
  }

  /** Post a balanced event through the guarded RPC. Returns the new event_ref. */
  async postEvent(input: PostEventInput): Promise<string> {
    if (input.lines.length < 2) {
      throw new InvariantError('A posting needs at least two ledger lines.')
    }
    if (!input.description.trim()) {
      throw new InvariantError('A description is required — every event must be explainable.')
    }
    const { data, error } = await saveRpc('post_event', {
      p_event_type: input.eventType,
      p_occurred_on: input.occurredOn,
      p_description: input.description,
      p_lines: input.lines,
      p_party_type: input.partyType ?? null,
      p_party_name: input.partyName ?? null,
      p_created_by: this.createdBy(),
      p_idempotency_key: input.idempotencyKey,
    })
    if (error) throw rpcError(error)
    return data as string
  }

  /**
   * Record a salt purchase. Creates a new batch (BATCH-00n) + PURCHASE_RECEIPT
   * movement and posts Dr Inventory / Cr Cash-or-AP through the guarded RPC.
   */
  async recordPurchase(input: {
    /** One key per entry attempt; reused on every retry of that same entry. */
    idempotencyKey: string
    supplier: string
    productCode: string
    locationCode: string
    qtyKg: number
    landedCostPkr: number
    payCash: boolean
    occurredOn: string
    note?: string
  }): Promise<PurchaseResult> {
    if (!input.supplier.trim()) throw new InvariantError('Supplier name is required.')
    if (!(input.qtyKg > 0)) throw new InvariantError('Quantity must be positive.')
    if (!(input.landedCostPkr > 0)) throw new InvariantError('Landed cost must be positive.')
    const { data, error } = await saveRpc('record_purchase', {
      p_supplier: input.supplier.trim(),
      p_product_code: input.productCode,
      p_location_code: input.locationCode,
      p_qty_grams: Math.round(input.qtyKg * 1000),
      p_landed_cost_paisa: Math.round(input.landedCostPkr * 100),
      p_pay_cash: input.payCash,
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_created_by: this.createdBy(),
      p_idempotency_key: input.idempotencyKey,
    })
    if (error) throw rpcError(error)
    return data as PurchaseResult
  }

  /**
   * Record a crush run (public.record_crush). The database prices everything, one calculation shared with
   * crushPreview: cost = rock value used + plant cost (rate x rock kg, credited to 5490); the good salt carries all
   * of it (loss absorbed), split by weight. No cash moves on a crush.
   */
  async recordCrush(input: {
    /** One key per entry attempt; reused on every retry of that same entry. */
    idempotencyKey: string
    inputBatchCode: string
    inputQtyKg: number
    outputs: GradeOutput[]
    wastageKg: number
    ratePkrPerKg: number
    occurredOn: string
    note?: string
  }): Promise<ProcessRunResult> {
    if (!(input.inputQtyKg > 0)) throw new InvariantError('Input quantity must be positive.')
    if (input.outputs.length === 0) throw new InvariantError('At least one output grade is required.')
    if (!(input.wastageKg >= 0)) throw new InvariantError('Wastage cannot be negative.')
    const { data, error } = await saveRpc('record_crush', {
      ...crushArgs(input),
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_idempotency_key: input.idempotencyKey,
    })
    if (error) throw rpcError(error)
    return data as ProcessRunResult
  }

  /** The database's figures for a crush run, without saving anything. */
  async crushPreview(input: { inputBatchCode: string; inputQtyKg: number; outputs: GradeOutput[]; wastageKg: number; ratePkrPerKg: number }): Promise<CrushPreview> {
    const { data, error } = await supabase.rpc('crush_preview', crushArgs(input))
    if (error) throw rpcError(error)
    return data as CrushPreview
  }

  /** The crushing rate (Rs per kg of rock) used on the last crush, or null before the first one. */
  async lastCrushRate(): Promise<number | null> {
    const { data, error } = await supabase.from('v_last_crush_rate').select('rate_paisa_per_kg').maybeSingle()
    if (error) throw rpcError(error)
    return data?.rate_paisa_per_kg != null ? data.rate_paisa_per_kg / 100 : null
  }

  /** Every supplier with what we owe them now (public.v_supplier_balances), biggest first. */
  async supplierBalances(): Promise<SupplierBalance[]> {
    const { data, error } = await supabase.from('v_supplier_balances').select('*').order('owed_paisa', { ascending: false }).order('name')
    if (error) throw rpcError(error)
    return data as SupplierBalance[]
  }

  /** Supplier names already used in the books (for "pick or type"). */
  async supplierNames(): Promise<string[]> {
    return (await this.supplierBalances()).map((s) => s.name).sort((a, b) => a.localeCompare(b))
  }

  /**
   * Pay a supplier (public.pay_supplier): Dr 2000 for that supplier / Cr cash. Never more than owed — except a
   * monthly bill (electricity), where the extra goes to its expense account and the answer says how much.
   */
  async paySupplier(input: { idempotencyKey: string; partyId: number; amountPkr: number; occurredOn: string; note?: string }): Promise<PaySupplierResult> {
    if (!(input.amountPkr > 0)) throw new InvariantError('Payment amount must be positive.')
    const { data, error } = await saveRpc('pay_supplier', {
      p_party_id: input.partyId,
      p_amount_paisa: Math.round(input.amountPkr * 100),
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_idempotency_key: input.idempotencyKey,
    })
    if (error) throw rpcError(error)
    return data as PaySupplierResult
  }

  /** A bill estimate that was more than the real bill: remove what is left owed (public.clear_supplier_leftover). */
  async clearSupplierLeftover(input: { idempotencyKey: string; partyId: number; occurredOn: string; reason: string }): Promise<{ event_ref: string; cleared_paisa: number }> {
    const { data, error } = await saveRpc('clear_supplier_leftover', {
      p_party_id: input.partyId,
      p_occurred_on: input.occurredOn,
      p_reason: input.reason.trim(),
      p_idempotency_key: input.idempotencyKey,
    })
    if (error) throw rpcError(error)
    return data as { event_ref: string; cleared_paisa: number }
  }

  /* ---------- Phase 3: Sales & Dispatch ---------- */

  /** Customers for the sale form dropdown (public.v_customers). */
  async customers(): Promise<Customer[]> {
    const { data, error } = await supabase
      .from('v_customers')
      .select('party_id, party_ref, name, phone')
      .eq('is_active', true)
      .order('name', { ascending: true })
    if (error) throw rpcError(error)
    return (data ?? []).map((c: any) => ({ id: c.party_id, party_ref: c.party_ref, name: c.name, phone: c.phone, kind: 'customer' }))
  }

  /** Quick-add a customer through the guarded RPC. */
  async createCustomer(name: string, phone?: string): Promise<Customer> {
    if (!name.trim()) throw new InvariantError('Customer name is required.')
    const { data, error } = await saveRpc('create_customer', {
      p_name: name.trim(),
      p_phone: phone?.trim() || null,
      p_note: null,
    })
    if (error) throw rpcError(error)
    const created = (Array.isArray(data) ? data[0] : data) as Customer
    if (!created?.id) throw new InvariantError('Customer could not be created.')
    return created
  }

  /** How much advance credit this customer holds (public.v_advances). */
  async customerAdvanceBalance(partyId: number): Promise<number> {
    const { data, error } = await supabase
      .from('v_advances')
      .select('advance_balance_paisa')
      .eq('party_id', partyId)
      .maybeSingle()
    if (error) throw rpcError(error)
    return data?.advance_balance_paisa ?? 0
  }

  /** One page of invoices (public.v_sales), newest first, with dispatch progress and gross margin. */
  async sales(limit = PAGE_SIZE, offset = 0): Promise<SaleRow[]> {
    const { data, error } = await supabase
      .from('v_sales')
      .select('*')
      .order('occurred_on', { ascending: false })
      .order('sale_ref', { ascending: false })
      .range(offset, offset + limit - 1)
    if (error) throw rpcError(error)
    return data as SaleRow[]
  }

  /** Totals over ALL invoices, computed by the database (public.v_sales_totals). */
  async salesTotals(): Promise<SalesTotals> {
    const { data, error } = await supabase.from('v_sales_totals').select('*').single()
    if (error) throw rpcError(error)
    return data as SalesTotals
  }

  /** Per-batch COGS allocations of one invoice (public.v_dispatch_allocations). */
  async dispatchAllocations(saleRef: string): Promise<DispatchAllocationRow[]> {
    const { data, error } = await supabase
      .from('v_dispatch_allocations')
      .select('*')
      .eq('sale_ref', saleRef)
      .order('occurred_on', { ascending: true })
    if (error) throw rpcError(error)
    return data as DispatchAllocationRow[]
  }

  /** Who owes what (public.v_debtors). */
  async debtors(): Promise<DebtorRow[]> {
    const { data, error } = await supabase
      .from('v_debtors')
      .select('*')
      .order('outstanding_paisa', { ascending: false })
    if (error) throw rpcError(error)
    return data as DebtorRow[]
  }

  /**
   * ONE-TAP udhaar sale (public.record_udhaar_sale): invoice + immediate FIFO
   * dispatch in one transaction. Pass either unitPricePkrPerKg or lineTotalPkr
   * per line — the DB books the exact total when lineTotalPkr is given.
   */
  async recordUdhaarSale(input: {
    /** One key per entry attempt; reused on every retry of that same entry. */
    idempotencyKey: string
    customerName: string
    /** batchCode: take the whole line from this batch instead of oldest-first (record_dispatch "manual" allocation) */
    items: { productCode: string; qtyKg: number; unitPricePkrPerKg?: number; lineTotalPkr?: number; batchCode?: string }[]
    cashReceivedPkr: number
    customerPhone?: string
    occurredOn: string
    note?: string
  }): Promise<{ sale_ref: string; dispatch_ref: string; revenue_paisa: number; cash_paisa: number; ar_paisa: number; cogs_paisa: number; party_created: boolean } | { duplicate: boolean; sale_ref: string }> {
    if (!input.customerName.trim()) throw new InvariantError('Customer name is required.')
    if (input.items.length === 0) throw new InvariantError('At least one sale line is required.')
    if (!(input.cashReceivedPkr >= 0)) throw new InvariantError('Cash received cannot be negative.')
    const { data, error } = await saveRpc('record_udhaar_sale', {
      p_party: input.customerName.trim(),
      p_items: input.items.map((it) => {
        const qtyKg = Math.round(it.qtyKg * 1000) / 1000
        const batch = it.batchCode
          ? { allocations: [{ batch_code: it.batchCode, qty_kg: qtyKg }], override_reason: 'Batch picked on the Sell screen' }
          : {}
        if (it.lineTotalPkr !== undefined && it.lineTotalPkr > 0) {
          return { product_code: it.productCode, qty_kg: qtyKg, line_total_paisa: Math.round(it.lineTotalPkr * 100), ...batch }
        }
        if (!(it.unitPricePkrPerKg && it.unitPricePkrPerKg > 0)) {
          throw new InvariantError('Each line needs a price per kg or a line total.')
        }
        return { product_code: it.productCode, qty_kg: qtyKg, unit_price_paisa_per_kg: Math.round(it.unitPricePkrPerKg * 100), ...batch }
      }),
      p_cash_received_paisa: Math.round(input.cashReceivedPkr * 100),
      p_customer_phone: input.customerPhone?.trim() || null,
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_idempotency_key: input.idempotencyKey,
      p_created_by: this.createdBy(),
    })
    if (error) throw rpcError(error)
    return data as { sale_ref: string; dispatch_ref: string; revenue_paisa: number; cash_paisa: number; ar_paisa: number; cogs_paisa: number; party_created: boolean } | { duplicate: boolean; sale_ref: string }
  }

  /** Record a customer payment (Dr Cash / Cr AR) through the guarded RPC. */
  async recordCustomerPayment(input: {
    /** One key per entry attempt; reused on every retry of that same entry. */
    idempotencyKey: string
    customerName: string
    amountPkr: number
    occurredOn: string
    note?: string
  }): Promise<void> {
    if (!(input.amountPkr > 0)) throw new InvariantError('Payment amount must be positive.')
    if (!input.customerName.trim()) throw new InvariantError('Customer name is required.')
    const { error } = await saveRpc('record_customer_payment', {
      p_customer: input.customerName.trim(),
      p_amount_paisa: Math.round(input.amountPkr * 100),
      p_occurred_on: input.occurredOn,
      p_note: input.note?.trim() || null,
      p_created_by: this.createdBy(),
      p_idempotency_key: input.idempotencyKey,
    })
    if (error) throw rpcError(error)
  }

  /**
   * Resolve a review item. NOTE: writes to review_queue require RLS policies /
   * auth; this method is wired for the Phase 4+ authenticated release.
   */
  async resolveReviewItem(id: number, note: string, dismissed = false): Promise<void> {
    if (!note.trim()) {
      throw new InvariantError('A resolution note is required — corrections must never be silent.')
    }
    const { error } = await saveRpc('resolve_review_item', {
      p_id: id,
      p_note: note,
      p_dismissed: dismissed,
    })
    if (error) throw rpcError(error)
  }

  /** What deleting this entry would change, and anything that must be deleted first. Always live (never offline). */
  async deletePreview(ref: string): Promise<DeletePreview> {
    const { data, error } = await supabase.rpc('delete_entry_preview', { p_ref: ref }).abortSignal(AbortSignal.timeout(SAVE_TIMEOUT_MS))
    if (error) throw rpcError(error)
    return data as DeletePreview
  }

  /**
   * Delete a whole entry. One transaction in the database: full copy saved, books re-checked, cancelled if any
   * check fails. Safe to repeat: a second call answers already_deleted.
   */
  async deleteEntry(ref: string, reason: string, confirm?: string): Promise<{ event_refs: string[]; deleted_id: number; already_deleted?: boolean }> {
    if (!reason.trim()) throw new InvariantError('Write why this entry is being deleted.')
    const { data, error } = await saveRpc('delete_entry', { p_ref: ref, p_reason: reason.trim(), p_confirm: confirm?.trim() || null })
    if (error) throw rpcError(error)
    return data as { event_refs: string[]; deleted_id: number; already_deleted?: boolean }
  }

  /** What is still in 5950 Personal/Unclassified, one row per entry (public.v_unclassified), oldest first. */
  async unclassified(): Promise<UnclassifiedRow[]> {
    const { data, error } = await supabase.from('v_unclassified').select('*').order('entry_date').order('latest_ref')
    if (error) throw rpcError(error)
    return data as UnclassifiedRow[]
  }

  /** The entry as the correction form opens it, or why it cannot be corrected here. */
  async correctionStart(ref: string): Promise<CorrectionStart> {
    const { data, error } = await supabase.rpc('correct_entry_preview', { p_ref: ref })
    if (error) throw rpcError(error)
    return data as CorrectionStart
  }

  /** What correcting the entry to this version would post — worked out by the database, nothing saved. */
  async correctionPreview(ref: string, date: string, lines: { account: string; debit?: number; credit?: number }[]): Promise<CorrectionPlan> {
    const { data, error } = await supabase.rpc('correct_entry_preview', { p_ref: ref, p_date: date, p_lines: lines })
    if (error) throw rpcError(error)
    return data as CorrectionPlan
  }

  /**
   * Correct a money entry: the database posts one correction (same date) or a reversal + the correct entry (other
   * date), together in one transaction. The original stays as it was. Safe to repeat with the same key.
   */
  async correctEntry(input: {
    idempotencyKey: string
    ref: string
    date: string
    lines: { account: string; debit?: number; credit?: number }[]
    reason: string
  }): Promise<CorrectionPlan> {
    if (!input.reason.trim()) throw new InvariantError('Write why this entry is being corrected.')
    const { data, error } = await saveRpc('correct_entry', {
      p_ref: input.ref,
      p_date: input.date,
      p_lines: input.lines,
      p_reason: input.reason.trim(),
      p_idempotency_key: input.idempotencyKey,
    })
    if (error) throw rpcError(error)
    return data as CorrectionPlan
  }

  /** Put a deleted entry back exactly as it was (same numbers). Safe to repeat. */
  async restoreEntry(deletedId: number): Promise<{ event_refs: string[]; already_restored?: boolean }> {
    const { data, error } = await saveRpc('restore_entry', { p_deleted_id: deletedId })
    if (error) throw rpcError(error)
    return data as { event_refs: string[]; already_restored?: boolean }
  }

  /** One page of deleted entries, newest first (public.v_deleted_entries). */
  async deletedEntries(limit = PAGE_SIZE, offset = 0): Promise<DeletedEntry[]> {
    const { data, error } = await supabase
      .from('v_deleted_entries')
      .select('*')
      .order('deleted_at', { ascending: false })
      .range(offset, offset + limit - 1)
    if (error) throw rpcError(error)
    return data as DeletedEntry[]
  }

  /** The entry the database holds under this key (ref, date, posted amount), or null if none. */
  async entryByKey(idempotencyKey: string): Promise<ConfirmedEntry | null> {
    const { data, error } = await saveRpc('entry_by_key', { p_idempotency_key: idempotencyKey })
    if (error) throw rpcError(error)
    return (data as ConfirmedEntry | null) ?? null
  }
}

export const engine = new LedgerEngine()
